defmodule WeGoNext.EncounterStore do
  @moduledoc """
  Provides access to encounters for the current combat log file.
  Queries database directly - no caching layer.

  The current file is tracked by FileWatcher. This module provides
  convenience functions for accessing encounters from that file.
  """

  alias WeGoNext.{Importer, Repo, CombatLogFile, FileWatcher}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord

  @doc """
  Imports a combat log file into the database.
  Returns {:ok, count} on success, {:error, reason} on failure.

  Options:
    - :progress_topic - PubSub topic to broadcast progress updates to
    - :force_reimport - If true, deletes existing encounters and starts from byte 0
  """
  def import_log(log_path, user_id, opts \\ []) do
    case Importer.import_log(log_path, user_id, opts) do
      {:ok, %{file: clf, new_encounters: count}} ->
        # Start watching this file for changes
        FileWatcher.watch(clf)

        Phoenix.PubSub.broadcast(
          WeGoNext.PubSub,
          "encounters",
          {:encounters_loaded, count}
        )

        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Syncs a combat log file (only parses new content since last import).
  Returns {:ok, new_count} on success, {:error, reason} on failure.
  """
  def sync_log(log_path) do
    case Importer.sync_log(log_path) do
      {:ok, %{file: clf, new_encounters: count}} ->
        # Update FileWatcher with fresh CLF (has updated byte offsets)
        FileWatcher.watch(clf)

        if count > 0 do
          Phoenix.PubSub.broadcast(
            WeGoNext.PubSub,
            "encounters",
            {:encounters_loaded, count}
          )
        end

        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Loads encounters from database for display.
  """
  def load_from_db(combat_log_file_id) do
    case Repo.get(CombatLogFile, combat_log_file_id) do
      nil ->
        {:error, :not_found}

      clf ->
        # Start watching this file for changes
        FileWatcher.watch(clf)

        count = length(Importer.list_encounters(clf))
        {:ok, count}
    end
  end

  @doc """
  Returns all encounter records (Ecto structs) for the current file.
  Fetches directly from database.
  """
  def list_encounter_records do
    case current_combat_log_file() do
      nil -> []
      clf -> Importer.list_encounters(clf)
    end
  end

  @doc """
  Returns all encounters for display (lightweight, no parsed events).
  These are Encounter structs with basic metadata but empty events list.
  Use get_encounter/1 to get a fully parsed encounter with events for analysis.
  """
  def list_encounters do
    records = list_encounter_records()
    Enum.map(records, &to_lightweight_encounter/1)
  end

  @doc """
  Returns a single fully-parsed encounter by database ID.
  This parses all events from raw_log - use for analysis on detail pages.
  Only use this when you need the events list (e.g., computing fresh analysis).
  """
  def get_encounter(id) when is_integer(id) do
    case Importer.get_encounter(id) do
      nil -> nil
      record -> EncounterRecord.to_encounter_struct(record)
    end
  end

  @doc """
  Returns a lightweight encounter by database ID - no raw_log parsing.
  Use this when you have cached analysis and don't need the events list.
  Much faster than get_encounter/1.
  """
  def get_encounter_lightweight(id) when is_integer(id) do
    case Importer.get_encounter(id) do
      nil -> nil
      record -> EncounterRecord.to_lightweight_struct(record)
    end
  end

  @doc """
  Returns a single encounter record by database ID.
  """
  def get_encounter_record(id) when is_integer(id) do
    Importer.get_encounter(id)
  end

  @doc """
  Returns cached analysis for an encounter by database ID.
  Returns the analysis map if available, nil otherwise.
  """
  def get_cached_analysis(id) when is_integer(id) do
    case get_encounter_record(id) do
      nil -> nil
      record -> Map.get(record, :analysis)
    end
  end

  @doc """
  Returns true if the encounter has pre-computed analysis cached.
  """
  def has_cached_analysis?(id) when is_integer(id) do
    case get_cached_analysis(id) do
      nil -> false
      analysis when analysis == %{} -> false
      _analysis -> true
    end
  end

  @doc """
  Returns the currently loaded log path.
  """
  def current_log_path do
    case FileWatcher.current_file() do
      nil -> nil
      clf -> clf.file_path
    end
  end

  @doc """
  Returns the current CombatLogFile record if one is loaded.
  Fetches fresh from database to ensure up-to-date byte offsets.
  """
  def current_combat_log_file do
    case FileWatcher.current_file() do
      nil -> nil
      clf -> Repo.get(CombatLogFile, clf.id)
    end
  end

  @doc """
  Clears the current file reference.
  """
  def clear do
    FileWatcher.stop_watching()
    :ok
  end

  # Convert Ecto record to lightweight Encounter struct (no events parsing)
  defp to_lightweight_encounter(%EncounterRecord{} = enc) do
    %WeGoNext.Encounter{
      id: enc.wow_encounter_id,
      name: enc.name,
      difficulty_id: enc.difficulty_id,
      difficulty_name: enc.difficulty_name,
      group_size: enc.group_size,
      instance_id: enc.instance_id,
      start_time: enc.start_time,
      end_time: enc.end_time,
      success: enc.success,
      fight_time_ms: enc.fight_time_ms,
      events: []
    }
  end
end
