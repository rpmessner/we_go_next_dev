defmodule WeGoNext.EncounterStore do
  @moduledoc """
  Stores parsed encounters in ETS for quick access by the web UI.
  Now backed by database with ETS as a cache layer.
  """
  use GenServer

  alias WeGoNext.{Importer, Repo, CombatLogFile, FileWatcher}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord

  @table_name :encounter_store

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Imports a combat log file into the database and caches encounters.
  Returns {:ok, count} on success, {:error, reason} on failure.
  """
  def import_log(log_path, user_id) do
    GenServer.call(__MODULE__, {:import_log, log_path, user_id}, :infinity)
  end

  @doc """
  Syncs a combat log file (only parses new content since last import).
  Returns {:ok, new_count} on success, {:error, reason} on failure.
  """
  def sync_log(log_path) do
    GenServer.call(__MODULE__, {:sync_log, log_path}, :infinity)
  end

  @doc """
  Loads encounters from database for display.
  """
  def load_from_db(combat_log_file_id) do
    GenServer.call(__MODULE__, {:load_from_db, combat_log_file_id})
  end

  @doc """
  Returns all cached encounters (as in-memory structs for analysis).
  """
  def list_encounters do
    case :ets.lookup(@table_name, :encounters) do
      [{:encounters, encounters}] -> encounters
      [] -> []
    end
  end

  @doc """
  Returns all cached encounter records (Ecto structs for display).
  """
  def list_encounter_records do
    case :ets.lookup(@table_name, :encounter_records) do
      [{:encounter_records, records}] -> records
      [] -> []
    end
  end

  @doc """
  Returns a single encounter by index (1-based).
  """
  def get_encounter(index) when is_integer(index) do
    encounters = list_encounters()
    Enum.at(encounters, index - 1)
  end

  @doc """
  Returns a single encounter record by index (1-based).
  """
  def get_encounter_record(index) when is_integer(index) do
    records = list_encounter_records()
    Enum.at(records, index - 1)
  end

  @doc """
  Returns the currently loaded log path.
  """
  def current_log_path do
    case :ets.lookup(@table_name, :log_path) do
      [{:log_path, path}] -> path
      [] -> nil
    end
  end

  @doc """
  Returns the current CombatLogFile record if one is loaded.
  """
  def current_combat_log_file do
    case :ets.lookup(@table_name, :combat_log_file) do
      [{:combat_log_file, clf}] -> clf
      [] -> nil
    end
  end

  @doc """
  Clears all stored encounters.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:import_log, log_path, user_id}, _from, state) do
    case Importer.import_log(log_path, user_id) do
      {:ok, %{file: clf, new_encounters: count}} ->
        # Load encounters into cache
        cache_encounters_from_db(clf)

        # Start watching this file for changes
        FileWatcher.watch(clf)

        Phoenix.PubSub.broadcast(
          WeGoNext.PubSub,
          "encounters",
          {:encounters_loaded, count}
        )

        {:reply, {:ok, count}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:sync_log, log_path}, _from, state) do
    case Importer.sync_log(log_path) do
      {:ok, %{file: clf, new_encounters: count}} ->
        # Refresh cache
        cache_encounters_from_db(clf)

        if count > 0 do
          Phoenix.PubSub.broadcast(
            WeGoNext.PubSub,
            "encounters",
            {:encounters_loaded, count}
          )
        end

        {:reply, {:ok, count}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:load_from_db, combat_log_file_id}, _from, state) do
    case Repo.get(CombatLogFile, combat_log_file_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      clf ->
        cache_encounters_from_db(clf)

        # Start watching this file for changes
        FileWatcher.watch(clf)

        {:reply, {:ok, length(list_encounter_records())}, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete(@table_name, :encounters)
    :ets.delete(@table_name, :encounter_records)
    :ets.delete(@table_name, :log_path)
    :ets.delete(@table_name, :combat_log_file)
    {:reply, :ok, state}
  end

  # Private functions

  defp cache_encounters_from_db(%CombatLogFile{} = clf) do
    # Get encounter records from DB
    records = Importer.list_encounters(clf)

    # Convert to in-memory structs for analysis
    encounters = Enum.map(records, &EncounterRecord.to_encounter_struct/1)

    # Store both in ETS
    :ets.insert(@table_name, {:encounter_records, records})
    :ets.insert(@table_name, {:encounters, encounters})
    :ets.insert(@table_name, {:log_path, clf.file_path})
    :ets.insert(@table_name, {:combat_log_file, clf})
  end
end
