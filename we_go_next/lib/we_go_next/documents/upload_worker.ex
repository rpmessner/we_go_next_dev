defmodule WeGoNext.Documents.UploadWorker do
  @moduledoc """
  Runtime worker that drains pending public document uploads from the outbox.
  """

  use GenServer

  alias WeGoNext.Mirror.Outbox

  @default_interval_ms 5_000
  @default_limit 5
  @default_max_concurrency 2

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Drains one bounded outbox batch synchronously.
  """
  def drain_once(server \\ __MODULE__, opts \\ []) do
    GenServer.call(server, {:drain_once, opts}, Keyword.get(opts, :call_timeout, 60_000))
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms:
        Keyword.get(
          opts,
          :interval_ms,
          Application.get_env(
            :we_go_next,
            :document_upload_worker_interval_ms,
            @default_interval_ms
          )
        ),
      limit: Keyword.get(opts, :limit, @default_limit),
      max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
      outbox: Keyword.get(opts, :outbox, Outbox),
      outbox_opts: Keyword.get(opts, :outbox_opts, [])
    }

    schedule_next(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:drain_once, opts}, _from, state) do
    {:reply, drain(state, opts), state}
  end

  @impl true
  def handle_info(:drain, state) do
    _result = drain(state, [])
    schedule_next(state)
    {:noreply, state}
  end

  defp drain(state, opts) do
    opts =
      state.outbox_opts
      |> Keyword.merge(limit: state.limit, max_concurrency: state.max_concurrency)
      |> Keyword.merge(opts)

    state.outbox.process_pending(opts)
  end

  defp schedule_next(%{interval_ms: interval_ms})
       when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :drain, interval_ms)
  end

  defp schedule_next(_state), do: :ok
end
