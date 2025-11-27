defmodule WeGoNext.FileWatcher do
  @moduledoc """
  Watches the active combat log file for changes and automatically imports new encounters.

  Polls the file every second to detect when new content is written (typically on ENCOUNTER_END).
  WoW buffers combat log writes during combat, but flushes immediately on encounter end.
  """
  use GenServer
  require Logger

  alias WeGoNext.{EncounterStore, CombatLogFile, Repo}

  @poll_interval 1000  # 1 second

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts watching a combat log file.
  """
  def watch(%CombatLogFile{} = clf) do
    GenServer.cast(__MODULE__, {:watch, clf})
  end

  @doc """
  Starts watching by file path (looks up the CombatLogFile record).
  """
  def watch(file_path) when is_binary(file_path) do
    case Repo.get_by(CombatLogFile, file_path: file_path) do
      nil -> {:error, :not_found}
      clf -> watch(clf)
    end
  end

  @doc """
  Stops watching the current file.
  """
  def stop_watching do
    GenServer.cast(__MODULE__, :stop_watching)
  end

  @doc """
  Returns the currently watched file.
  """
  def current_file do
    GenServer.call(__MODULE__, :current_file)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{clf: nil, timer_ref: nil}}
  end

  @impl true
  def handle_cast({:watch, %CombatLogFile{} = clf}, state) do
    # Cancel existing timer if any
    state = cancel_timer(state)

    Logger.info("FileWatcher: Started watching #{Path.basename(clf.file_path)}")

    # Schedule first check
    timer_ref = Process.send_after(self(), :check_file, @poll_interval)

    {:noreply, %{state | clf: clf, timer_ref: timer_ref}}
  end

  @impl true
  def handle_cast(:stop_watching, state) do
    Logger.info("FileWatcher: Stopped watching")
    state = cancel_timer(state)
    {:noreply, %{state | clf: nil}}
  end

  @impl true
  def handle_call(:current_file, _from, state) do
    {:reply, state.clf, state}
  end

  @impl true
  def handle_info(:check_file, %{clf: nil} = state) do
    # Not watching anything, do nothing
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_file, %{clf: clf} = state) do
    # Refresh the clf record from database to get latest metadata
    clf = Repo.get!(CombatLogFile, clf.id)

    # Check if file has new content
    if CombatLogFile.has_new_content?(clf) do
      Logger.debug("FileWatcher: Detected changes in #{Path.basename(clf.file_path)}")

      case EncounterStore.sync_log(clf.file_path) do
        {:ok, count} when count > 0 ->
          Logger.info("FileWatcher: Imported #{count} new encounter(s)")
          # Note: EncounterStore.sync_log already broadcasts to PubSub

        {:ok, 0} ->
          # File changed but no new encounters (partial write, non-encounter events, etc.)
          :ok

        {:error, reason} ->
          Logger.error("FileWatcher: Failed to sync log: #{inspect(reason)}")
      end
    end

    # Schedule next check
    timer_ref = Process.send_after(self(), :check_file, @poll_interval)
    {:noreply, %{state | clf: clf, timer_ref: timer_ref}}
  end

  # Private helpers

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: timer_ref} = state) do
    Process.cancel_timer(timer_ref)
    %{state | timer_ref: nil}
  end
end
