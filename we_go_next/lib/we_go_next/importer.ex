defmodule WeGoNext.Importer do
  @moduledoc """
  Imports combat log files into the database with incremental parsing support.

  Tracks byte offsets so subsequent imports only parse new content.
  """

  alias WeGoNext.{Repo, CombatLogFile, LogReader, Encounter}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord
  alias WeGoNext.Encounters.EventParser
  alias WeGoNext.Analyzers.AnalysisCache
  import Ecto.Query

  @doc """
  Imports a combat log file, creating or updating the CombatLogFile record.
  Returns {:ok, %{file: combat_log_file, new_encounters: count}} on success.

  Options:
    - :progress_topic - PubSub topic to broadcast progress updates to
    - :force_reimport - If true, deletes existing encounters and starts from byte 0
  """
  def import_log(file_path, user_id, opts \\ []) do
    case get_or_create_combat_log_file(file_path, user_id) do
      {:ok, clf} ->
        clf =
          if Keyword.get(opts, :force_reimport, false) do
            reset_for_reimport(clf)
          else
            clf
          end

        do_import(clf, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reset_for_reimport(clf) do
    # Delete all existing encounters for this file
    from(e in EncounterRecord, where: e.combat_log_file_id == ^clf.id)
    |> Repo.delete_all()

    # Reset parsing progress
    {:ok, updated} =
      clf
      |> Ecto.Changeset.change(%{last_parsed_byte: 0, is_complete: false})
      |> Repo.update()

    updated
  end

  @doc """
  Syncs a combat log file, parsing only new content since last import.
  Accepts either a CombatLogFile struct or a file path string.
  """
  def sync_log(file_or_path)

  def sync_log(%CombatLogFile{} = clf) do
    # Check for new content OR unparsed bytes in existing content
    has_unparsed = (clf.last_parsed_byte || 0) < (clf.file_size || 0)

    if has_unparsed or CombatLogFile.has_new_content?(clf) do
      do_import(clf)
    else
      {:ok, %{file: clf, new_encounters: 0}}
    end
  end

  def sync_log(file_path) when is_binary(file_path) do
    case Repo.get_by(CombatLogFile, file_path: file_path) do
      nil -> {:error, :not_found}
      clf -> sync_log(clf)
    end
  end

  @doc """
  Lists all encounters for a combat log file.
  """
  def list_encounters(%CombatLogFile{id: id}, _opts \\ []) do
    EncounterRecord
    |> where([e], e.combat_log_file_id == ^id)
    |> order_by([e], asc: e.start_time)
    |> Repo.all()
  end

  @doc """
  Lists all encounters across all combat log files for a user.
  """
  def list_all_encounters(user_id) do
    EncounterRecord
    |> join(:inner, [e], clf in CombatLogFile, on: e.combat_log_file_id == clf.id)
    |> where([e, clf], clf.user_id == ^user_id)
    |> order_by([e], desc: e.start_time)
    |> Repo.all()
  end

  @doc """
  Gets an encounter by ID.
  """
  def get_encounter(id) do
    Repo.get(EncounterRecord, id)
  end

  @doc """
  Purges all encounters and events for a combat log file.
  Also deletes the combat log file record itself.
  """
  def purge_log(combat_log_file_id) do
    # Delete events first (foreign key constraint)
    from(e in "encounter_events",
      join: enc in EncounterRecord, on: e.encounter_id == enc.id,
      where: enc.combat_log_file_id == ^combat_log_file_id
    )
    |> Repo.delete_all()

    # Delete encounters
    from(e in EncounterRecord, where: e.combat_log_file_id == ^combat_log_file_id)
    |> Repo.delete_all()

    # Delete the combat log file record
    from(clf in CombatLogFile, where: clf.id == ^combat_log_file_id)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Toggles the is_reset flag on an encounter.
  Returns {:ok, updated_encounter} or {:error, changeset}.
  """
  def toggle_reset(encounter_id) do
    case Repo.get(EncounterRecord, encounter_id) do
      nil ->
        {:error, :not_found}

      encounter ->
        encounter
        |> Ecto.Changeset.change(is_reset: not encounter.is_reset)
        |> Repo.update()
    end
  end

  @doc """
  Converts an Ecto encounter record to the in-memory struct for analysis.
  """
  def to_encounter_struct(%EncounterRecord{} = enc) do
    EncounterRecord.to_encounter_struct(enc)
  end

  # Private functions

  defp get_or_create_combat_log_file(file_path, user_id) do
    case Repo.get_by(CombatLogFile, file_path: file_path) do
      nil ->
        case CombatLogFile.attrs_from_file(file_path, user_id) do
          {:ok, attrs} ->
            %CombatLogFile{}
            |> CombatLogFile.changeset(attrs)
            |> Repo.insert()

          {:error, reason} ->
            {:error, reason}
        end

      existing ->
        {:ok, existing}
    end
  end

  defp do_import(%CombatLogFile{} = clf, opts \\ []) do
    start_byte = clf.last_parsed_byte || 0
    progress_topic = Keyword.get(opts, :progress_topic)

    progress_callback =
      if progress_topic do
        fn progress ->
          Phoenix.PubSub.broadcast(WeGoNext.PubSub, progress_topic, {:import_progress, progress})
        end
      else
        nil
      end

    # Stream encounters and insert each one immediately
    encounter_callback = fn encounter, enc_start_byte, enc_end_byte ->
      try do
        insert_single_encounter(encounter, clf.id, enc_start_byte, enc_end_byte)
        # Update last_parsed_byte after each successful encounter insert
        # This allows resuming from the last successful encounter on failure
        update_file_progress(clf, enc_end_byte)
        :ok
      rescue
        e ->
          require Logger
          Logger.error("Failed to insert encounter: #{Exception.message(e)}")
          {:error, Exception.message(e)}
      end
    end

    case LogReader.stream_encounters(clf.file_path, start_byte, encounter_callback, progress_callback: progress_callback) do
      {:ok, %{encounters_found: count, end_byte: end_byte}} ->
        # Final update to ensure file_size matches what we parsed
        {:ok, updated_clf} = update_file_progress(clf, end_byte)
        {:ok, %{file: updated_clf, new_encounters: count}}

      {:error, reason} ->
        # Even on error, we've saved progress up to the last successful encounter
        # Reload clf to get the latest last_parsed_byte
        updated_clf = Repo.get!(CombatLogFile, clf.id)
        {:error, %{reason: reason, file: updated_clf}}
    end
  end

  defp insert_single_encounter(encounter, combat_log_file_id, start_byte, end_byte) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Pre-compute analysis for this encounter
    analysis = compute_analysis(encounter)

    encounter_attrs =
      EncounterRecord.from_parsed(encounter, [], combat_log_file_id, start_byte, end_byte, analysis: analysis)
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)

    # Insert the encounter, skipping if it already exists (based on combat_log_file_id + start_time)
    # This handles resume scenarios where we might re-parse an already-imported encounter
    result =
      Repo.insert_all(
        EncounterRecord,
        [encounter_attrs],
        on_conflict: :nothing,
        conflict_target: [:combat_log_file_id, :start_time],
        returning: [:id]
      )

    case result do
      {1, [%{id: encounter_id}]} ->
        # New encounter inserted - add events
        insert_encounter_events(encounter, encounter_id, now)

      {0, []} ->
        # Encounter already exists - skip (already has events)
        :ok
    end

    :ok
  end

  defp insert_encounter_events(%Encounter{} = encounter, encounter_id, now) do
    # Parse each event into normalized format
    events =
      encounter.events
      |> Enum.reverse()  # Events are stored in reverse order
      |> Enum.map(fn event ->
        EventParser.parse(event, encounter.start_time)
        |> Map.put(:encounter_id, encounter_id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    # Insert in batches to avoid huge queries
    events
    |> Enum.chunk_every(1000)
    |> Enum.each(fn batch ->
      Repo.insert_all("encounter_events", batch)
    end)
  end

  # Compute analysis for an encounter at import time
  defp compute_analysis(%Encounter{} = encounter) do
    AnalysisCache.compute(encounter)
  rescue
    e ->
      # Log error but don't fail import - analysis can be computed later
      require Logger
      Logger.warning("Failed to compute analysis: #{Exception.message(e)}")
      %{}
  end

  defp update_file_progress(%CombatLogFile{} = clf, end_byte) do
    # Get updated file stats for mtime only
    # IMPORTANT: Use end_byte as file_size, not current disk size!
    # This avoids a race condition where WoW writes more data between
    # parsing and this update, causing us to skip content.
    {:ok, %{mtime: mtime}} = File.stat(clf.file_path)
    mtime_dt = NaiveDateTime.from_erl!(mtime) |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)

    clf
    |> Ecto.Changeset.change(%{
      last_parsed_byte: end_byte,
      last_parsed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      # Use end_byte as file_size to ensure has_new_content? detects if more was written
      file_size: end_byte,
      file_mtime: mtime_dt
    })
    |> Repo.update()
  end
end
