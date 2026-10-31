defmodule WeGoNext.ImportWorker do
  @moduledoc """
  Starts bounded import tasks and retains a durable receipt per user. Tasks commit
  and broadcast their own result, so restarting this dispatcher cannot lose a
  completion. Restart recovery re-arms deadlines and monitors surviving tasks.
  """
  use GenServer
  import Ecto.Query
  alias WeGoNext.{EncounterStore, Repo}
  alias WeGoNext.FileIngest.Operation

  @default_timeout 300_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def start_import(user_id, path, opts \\ []),
    do: GenServer.call(__MODULE__, {:start_import, user_id, path, opts})

  def get_status(user_id), do: GenServer.call(__MODULE__, {:get_status, user_id})
  def progress_topic(user_id), do: "import_progress:#{user_id}"
  def active_imports, do: GenServer.call(__MODULE__, :active_imports)

  @impl true
  def init(_) do
    # Migrations also start the application; do not query a table before it exists.
    %{rows: [[table]]} = Repo.query!("SELECT to_regclass('public.import_operations')::text")

    operations =
      if table, do: Repo.all(from(o in Operation, where: o.status == "importing")), else: []

    state = Map.new(operations, &{&1.token, recover(&1)})
    {:ok, state}
  end

  @impl true
  def handle_call({:start_import, user_id, path, opts}, _from, state) do
    case running(user_id) do
      %Operation{} = operation ->
        {:reply, {:already_importing, operation.path}, state}

      nil ->
        now = DateTime.utc_now()
        timeout = Keyword.get(opts, :timeout, @default_timeout)

        operation = %Operation{
          user_id: user_id,
          token: Ecto.UUID.generate(),
          path: path,
          status: "importing",
          started_at: now,
          deadline: DateTime.add(now, timeout, :millisecond)
        }

        operation =
          Repo.insert!(operation,
            on_conflict: {:replace_all_except, [:id, :user_id]},
            conflict_target: [:user_id]
          )

        task =
          Task.Supervisor.async_nolink(WeGoNext.ImportTaskSupervisor, fn ->
            Process.put(:ingest_operation_token, operation.token)
            finish(operation, perform(path, user_id, opts))
          end)

        timer = arm_deadline(operation)
        info = %{operation: operation, pid: task.pid, ref: task.ref, timer: timer}
        {:reply, :ok, Map.put(state, operation.token, info)}
    end
  end

  @impl true
  def handle_call({:get_status, user_id}, _from, state) do
    status =
      case running(user_id) do
        nil -> nil
        operation -> %{status: :importing, path: operation.path, started_at: operation.started_at}
      end

    {:reply, status, state}
  end

  @impl true
  def handle_call(:active_imports, _from, state) do
    statuses =
      Map.new(state, fn {_, info} ->
        {info.operation.user_id, %{status: :importing, path: info.operation.path}}
      end)

    {:reply, statuses, state}
  end

  @impl true
  def handle_info({:deadline, token}, state) do
    case Map.pop(state, token) do
      {nil, _} ->
        {:noreply, state}

      {info, remaining} ->
        # Mark first, fencing any result racing with the kill.
        finish(info.operation, {:error, :ingest_timeout})
        if info.pid, do: Task.Supervisor.terminate_child(WeGoNext.ImportTaskSupervisor, info.pid)
        if info.ref, do: Process.demonitor(info.ref, [:flush])
        {:noreply, remaining}
    end
  end

  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref), do: discard(ref, state)

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Enum.find(state, fn {_, info} -> info.ref == ref end) do
      nil ->
        {:noreply, state}

      {_, info} ->
        finish(info.operation, {:error, {:task_exit, reason}})
        discard(ref, state)
    end
  end

  defp perform(path, user_id, opts) do
    EncounterStore.import_log(
      path,
      user_id,
      Keyword.merge([generate_document: true], opts)
      |> Keyword.put(:progress_topic, progress_topic(user_id))
    )
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp finish(operation, result) do
    attrs =
      case result do
        {:ok, count} -> [status: "complete", encounters: count, error: nil]
        {:error, reason} -> [status: "failed", error: inspect(reason)]
      end

    {changed, _} =
      Repo.update_all(
        from(o in Operation,
          where:
            o.user_id == ^operation.user_id and o.token == ^operation.token and
              o.status == "importing"
        ),
        set: attrs
      )

    if changed == 1 do
      Phoenix.PubSub.broadcast(
        WeGoNext.PubSub,
        progress_topic(operation.user_id),
        {:import_complete, result}
      )
    end

    :ok
  end

  defp running(user_id), do: Repo.get_by(Operation, user_id: user_id, status: "importing")

  defp recover(operation) do
    pid =
      Enum.find(Task.Supervisor.children(WeGoNext.ImportTaskSupervisor), fn pid ->
        case Process.info(pid, :dictionary) do
          {:dictionary, dictionary} ->
            Keyword.get(dictionary, :ingest_operation_token) == operation.token

          nil ->
            false
        end
      end)

    %{
      operation: operation,
      pid: pid,
      ref: if(pid, do: Process.monitor(pid)),
      timer: arm_deadline(operation)
    }
  end

  defp arm_deadline(operation) do
    remaining = max(DateTime.diff(operation.deadline, DateTime.utc_now(), :millisecond), 0)
    Process.send_after(self(), {:deadline, operation.token}, remaining)
  end

  defp discard(ref, state) do
    Process.demonitor(ref, [:flush])

    remaining =
      Map.reject(state, fn {_, info} ->
        if info.ref == ref do
          Process.cancel_timer(info.timer)
          true
        else
          false
        end
      end)

    {:noreply, remaining}
  end
end
