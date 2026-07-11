defmodule WeGoNext.ImportWorker do
  @moduledoc """
  Manages log imports independently of LiveView processes.

  Imports run in a supervised process that survives page refreshes.
  Progress is tracked and broadcast via PubSub, and can be queried
  by LiveViews on mount to resume showing progress.
  """
  use GenServer

  alias WeGoNext.EncounterStore

  # Client API

  @doc """
  Starts an import for the given user. Returns immediately.
  Progress updates are broadcast to "import_progress:{user_id}".

  Options:
    - :force_reimport - If true, deletes existing encounters and starts fresh
  """
  def start_import(user_id, log_path, opts \\ []) do
    GenServer.call(__MODULE__, {:start_import, user_id, log_path, opts})
  end

  @doc """
  Returns the current import status for a user.
  Returns nil if no import is running, or a map with progress info.
  """
  def get_status(user_id) do
    GenServer.call(__MODULE__, {:get_status, user_id})
  end

  @doc """
  Returns all currently tracked imports.
  """
  def active_imports do
    GenServer.call(__MODULE__, :active_imports)
  end

  @doc """
  Returns the PubSub topic for import progress updates.
  """
  def progress_topic(user_id) do
    "import_progress:#{user_id}"
  end

  # Server callbacks

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    # State: %{user_id => %{status: :importing, path: path, progress: %{...}, task_ref: ref}}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:start_import, user_id, log_path, opts}, _from, state) do
    case Map.get(state, user_id) do
      %{status: :importing} = existing ->
        # Already importing for this user
        {:reply, {:already_importing, existing.path}, state}

      _ ->
        # Start import in a monitored task
        topic = progress_topic(user_id)
        force_reimport = Keyword.get(opts, :force_reimport, false)

        task =
          Task.Supervisor.async_nolink(WeGoNext.ImportTaskSupervisor, fn ->
            EncounterStore.import_log(log_path, user_id,
              progress_topic: topic,
              force_reimport: force_reimport,
              generate_document: true
            )
          end)

        new_state =
          Map.put(state, user_id, %{
            status: :importing,
            path: log_path,
            task_ref: task.ref,
            started_at: DateTime.utc_now()
          })

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:get_status, user_id}, _from, state) do
    status = Map.get(state, user_id)
    {:reply, status, state}
  end

  @impl true
  def handle_call(:active_imports, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({ref, result}, state) do
    # Task completed - find which user this was for
    case find_user_by_ref(state, ref) do
      nil ->
        {:noreply, state}

      user_id ->
        # Demonitor and flush
        Process.demonitor(ref, [:flush])

        # Broadcast completion
        topic = progress_topic(user_id)

        case result do
          {:ok, count} ->
            Phoenix.PubSub.broadcast(WeGoNext.PubSub, topic, {:import_complete, {:ok, count}})

          {:error, reason} ->
            Phoenix.PubSub.broadcast(WeGoNext.PubSub, topic, {:import_complete, {:error, reason}})
        end

        # Remove from state
        {:noreply, Map.delete(state, user_id)}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Task crashed
    case find_user_by_ref(state, ref) do
      nil ->
        {:noreply, state}

      user_id ->
        topic = progress_topic(user_id)
        Phoenix.PubSub.broadcast(WeGoNext.PubSub, topic, {:import_complete, {:error, reason}})
        {:noreply, Map.delete(state, user_id)}
    end
  end

  defp find_user_by_ref(state, ref) do
    Enum.find_value(state, fn {user_id, info} ->
      if info.task_ref == ref, do: user_id
    end)
  end
end
