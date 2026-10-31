defmodule WeGoNext.FileIngest do
  @moduledoc """
  The only ingest writer boundary. Claims a file, reloads progress under a database
  lock, and bounds the whole operation (including waiting for IO). A timeout kills
  the task; PostgreSQL releases its session lock when the connection closes.
  Completed boundaries and pending medallion markers remain available for retry.

  `Importer.sync_log/1` is the synchronous sync interface. FileWatcher may start
  it in its existing supervised task and consume the normal task result unchanged.
  Concurrent requests return `{:error, :ingest_busy}`; a later poll can retry.
  """
  import Ecto.Query
  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.FileIngest.Lifecycle

  @default_timeout 300_000

  @doc """
  Start a sync without blocking FileWatcher. Returns a monitored `Task`.
  Consume `{task.ref, result}` (or `:DOWN`) as usual. The result is
  `{:ok, %{file: file, new_encounters: count, medallion_results: results}}`
  or `{:error, reason}`; `:ingest_busy` means a later poll should retry.
  """
  def start_sync(%CombatLogFile{} = file) do
    Task.Supervisor.async_nolink(WeGoNext.ImportTaskSupervisor, fn ->
      WeGoNext.Importer.sync_log(file)
    end)
  end

  def run(%CombatLogFile{id: id} = file, event, fun, opts \\ []) do
    lock = {{__MODULE__, id}, self()}
    ctx = %{Lifecycle.initial() | offset: file.last_parsed_byte || 0}
    {:ok, phase, ctx, [effect]} = Lifecycle.step(:idle, event, ctx)

    try do
      {terminal, result} =
        claim(effect, lock, id, fun, Keyword.get(opts, :timeout, @default_timeout))

      ctx = apply_result(phase, ctx, result)
      {:ok, _phase, _ctx, effects} = Lifecycle.step(phase, terminal, ctx)
      Enum.each(effects, &release(&1, lock))
      result
    after
      :global.del_lock(lock, [node()])
    end
  end

  defp claim(:claim, lock, id, fun, timeout) do
    if :global.set_lock(lock, [node()], 0),
      do: execute(id, fun, timeout),
      else: {:error, {:error, :ingest_busy}}
  end

  defp release(effect, lock) when effect in [:release, :fail],
    do: :global.del_lock(lock, [node()])

  defp execute(id, fun, timeout) do
    owner = self()

    task =
      Task.Supervisor.async_nolink(WeGoNext.ImportTaskSupervisor, fn ->
        writer = self()

        {:ok, _guardian} =
          Task.Supervisor.start_child(WeGoNext.ImportTaskSupervisor, fn ->
            watch_owner(owner, writer)
          end)

        # Independent of the awaiting caller: even if ImportWorker's deadline kills
        # the outer task, this writer still loses its connection by its own deadline.
        {:ok, deadline} = :timer.exit_after(timeout, self(), :kill)

        try do
          Repo.checkout(
            fn ->
              # Pin a connection, not a transaction: medallion builders have their own
              # transactions and can roll them back without poisoning bronze progress.
              %{rows: [[claimed]]} =
                Repo.query!("SELECT pg_try_advisory_lock($1, $2)", [18_003, id])

              if claimed do
                try do
                  file = Repo.one!(from(f in CombatLogFile, where: f.id == ^id))
                  fun.(file)
                after
                  Repo.query!("SELECT pg_advisory_unlock($1, $2)", [18_003, id])
                end
              else
                {:error, :ingest_busy}
              end
            end,
            timeout: :infinity
          )
        after
          :timer.cancel(deadline)
        end
      end)

    await(task, timeout)
  end

  defp watch_owner(owner, writer) do
    owner_ref = Process.monitor(owner)
    writer_ref = Process.monitor(writer)

    receive do
      {:DOWN, ^owner_ref, :process, ^owner, _} -> Process.exit(writer, :kill)
      {:DOWN, ^writer_ref, :process, ^writer, _} -> :ok
    end
  end

  defp apply_result(phase, ctx, {:ok, result}) do
    offset =
      case result do
        %{file: %{last_parsed_byte: offset}} -> offset
        _ -> ctx.offset
      end

    {:ok, ^phase, ctx, _} = Lifecycle.step(phase, :advance, %{ctx | candidate: offset})

    failed =
      is_map(result) and
        Enum.any?(Map.get(result, :medallion_results, []), &match?({:error, _}, &1))

    event = if failed, do: :medallion_failed, else: :medallion_complete
    {:ok, ^phase, ctx, _} = Lifecycle.step(phase, event, ctx)
    ctx
  end

  defp apply_result(_phase, ctx, _result), do: ctx

  defp await(task, timeout) do
    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, _} = result} -> {:complete, result}
      {:ok, {:error, _} = result} -> {:error, result}
      {:exit, :killed} -> {:timeout, {:error, :ingest_timeout}}
      {:exit, reason} -> {:error, {:error, reason}}
      nil -> {:timeout, {:error, :ingest_timeout}}
    end
  end
end
