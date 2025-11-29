defmodule WeGoNext.FileWatcher do
  @moduledoc """
  Tracks the currently loaded combat log file.

  Note: Auto-polling has been removed in favor of manual refresh.
  WoW buffers combat log writes during combat and only flushes on ENCOUNTER_END,
  which made auto-polling unreliable. Manual refresh via the UI is preferred.

  ## Future Enhancement
  Auto-polling could be revisited post-MVP with better heuristics for detecting
  when WoW has actually written new encounter data.
  """
  use GenServer
  require Logger

  alias WeGoNext.{CombatLogFile, Repo}

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sets the current combat log file being viewed.
  Accepts either a CombatLogFile struct or a file path string.
  """
  def watch(file_or_path)

  def watch(%CombatLogFile{} = clf) do
    GenServer.cast(__MODULE__, {:watch, clf})
  end

  def watch(file_path) when is_binary(file_path) do
    case Repo.get_by(CombatLogFile, file_path: file_path) do
      nil -> {:error, :not_found}
      clf -> watch(clf)
    end
  end

  @doc """
  Clears the current file reference.
  """
  def stop_watching do
    GenServer.cast(__MODULE__, :stop_watching)
  end

  @doc """
  Returns the currently tracked file.
  """
  def current_file do
    GenServer.call(__MODULE__, :current_file)
  end

  @doc """
  Returns the directory of the current log file.
  """
  def watched_directory do
    GenServer.call(__MODULE__, :watched_directory)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, initial_state()}
  end

  defp initial_state do
    %{
      clf: nil,
      logs_dir: nil,
      user_id: nil
    }
  end

  @impl true
  def handle_cast({:watch, %CombatLogFile{} = clf}, _state) do
    logs_dir = Path.dirname(clf.file_path)
    Logger.info("FileWatcher: Now tracking #{Path.basename(clf.file_path)}")

    new_state = %{
      clf: clf,
      logs_dir: logs_dir,
      user_id: clf.user_id
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:stop_watching, _state) do
    Logger.info("FileWatcher: Stopped tracking")
    {:noreply, initial_state()}
  end

  @impl true
  def handle_call(:current_file, _from, state) do
    {:reply, state.clf, state}
  end

  @impl true
  def handle_call(:watched_directory, _from, state) do
    {:reply, state.logs_dir, state}
  end
end
