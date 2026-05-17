defmodule WeGoNext.Importer do
  @moduledoc """
  Imports combat log files into the database with incremental parsing support.

  Tracks byte offsets so subsequent imports only parse new content.
  """

  alias WeGoNext.{Repo, CombatLogFile, Encounter, CombatLogParser}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord
  alias WeGoNext.Analyzers.AnalysisCache
  alias WeGoNext.Bronze.CombatLogReconciler
  import Ecto.Query
  require Logger

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
    # Delete encounters (cascade will handle encounter_events if table still exists)
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
        with {:ok, nil} <- CombatLogReconciler.reconcile_archive_move(file_path, user_id),
             {:ok, attrs} <- CombatLogFile.attrs_from_file(file_path, user_id) do
          %CombatLogFile{}
          |> CombatLogFile.changeset(attrs)
          |> Repo.insert()
        else
          {:ok, %CombatLogFile{} = combat_log_file} -> {:ok, combat_log_file}
          {:error, reason} -> {:error, reason}
        end

      existing ->
        {:ok, existing}
    end
  end

  defp do_import(%CombatLogFile{} = clf, opts \\ []) do
    case ensure_importable_file(clf) do
      {:ok, %CombatLogFile{} = importable_clf} ->
        do_import_existing_file(importable_clf, opts)

      {:skip, %CombatLogFile{} = skipped_clf} ->
        {:ok, %{file: skipped_clf, new_encounters: 0}}
    end
  end

  defp do_import_existing_file(%CombatLogFile{} = clf, opts) do
    start_byte = clf.last_parsed_byte || 0
    progress_topic = Keyword.get(opts, :progress_topic)

    case CombatLogParser.scan_boundaries(clf.file_path, start_byte) do
      {:ok, boundaries, end_byte} ->
        results =
          boundaries
          |> Enum.with_index(1)
          |> Enum.map(fn {boundary, idx} ->
            result = insert_or_fetch_encounter_from_boundary(boundary, clf)

            # Broadcast progress
            if progress_topic do
              Phoenix.PubSub.broadcast(
                WeGoNext.PubSub,
                progress_topic,
                {:import_progress,
                 %{
                   bytes_read: boundary.end_byte,
                   total_bytes: end_byte,
                   encounters_found: idx
                 }}
              )
            end

            result
          end)

        new_encounters =
          Enum.count(results, fn
            {:inserted, %EncounterRecord{}} -> true
            {:existing, %EncounterRecord{}} -> false
          end)

        # Final progress update
        {:ok, updated_clf} = update_file_progress(clf, end_byte)

        # Compute analysis for newly imported encounters
        if new_encounters > 0 do
          spawn_analysis_task(updated_clf.id)
        end

        {:ok, %{file: updated_clf, new_encounters: new_encounters}}

      {:error, reason} ->
        updated_clf = Repo.get!(CombatLogFile, clf.id)
        {:error, %{reason: reason, file: updated_clf}}
    end
  end

  defp ensure_importable_file(%CombatLogFile{} = clf) do
    if File.regular?(clf.file_path) do
      {:ok, clf}
    else
      case CombatLogReconciler.reconcile_missing_file(clf) do
        {:ok, %CombatLogFile{} = reconciled_clf} ->
          {:ok, reconciled_clf}

        {:ok, nil} ->
          Logger.warning(
            "Skipping missing combat log #{clf.file_path}; no archived replacement found"
          )

          {:skip, clf}

        {:error, reason} ->
          Logger.warning(
            "Skipping missing combat log #{clf.file_path}; archive reconciliation failed: #{inspect(reason)}"
          )

          {:skip, clf}
      end
    end
  end

  # Spawn a background task to compute analysis for encounters missing it
  defp spawn_analysis_task(combat_log_file_id) do
    Task.Supervisor.start_child(WeGoNext.ImportTaskSupervisor, fn ->
      compute_pending_analyses(combat_log_file_id)
    end)
  end

  @doc """
  Computes analysis for all encounters in a log file that don't have it yet.
  Called async after import completes.
  """
  def compute_pending_analyses(combat_log_file_id) do
    # Find encounters with empty analysis
    encounters =
      EncounterRecord
      |> where([e], e.combat_log_file_id == ^combat_log_file_id)
      |> where([e], is_nil(e.analysis) or e.analysis == ^%{})
      |> order_by([e], asc: e.start_time)
      |> Repo.all()

    total = length(encounters)

    if total > 0 do
      require Logger
      Logger.info("Computing analysis for #{total} encounter(s)...")

      encounters
      |> Enum.with_index(1)
      |> Enum.each(fn {record, idx} ->
        compute_and_save_analysis(record)

        # Broadcast progress for UI updates
        Phoenix.PubSub.broadcast(
          WeGoNext.PubSub,
          "encounters",
          {:analysis_computed, record.id, idx, total}
        )
      end)

      Logger.info("Analysis computation complete for #{total} encounter(s)")
    end
  end

  defp compute_and_save_analysis(%EncounterRecord{} = record) do
    # Load the combat log file to get the path
    clf = Repo.get!(CombatLogFile, record.combat_log_file_id)

    # Parse events from the log file using byte offsets
    case CombatLogParser.parse_events(
           clf.file_path,
           record.start_byte,
           record.end_byte,
           format_timestamp(record.start_time)
         ) do
      {:ok, events} ->
        # Build Encounter struct with parsed events
        encounter = %Encounter{
          id: record.wow_encounter_id,
          name: record.name,
          difficulty_id: record.difficulty_id,
          difficulty_name: record.difficulty_name,
          group_size: record.group_size,
          instance_id: record.instance_id,
          start_time: record.start_time && DateTime.to_naive(record.start_time),
          end_time: record.end_time && DateTime.to_naive(record.end_time),
          success: record.success,
          fight_time_ms: record.fight_time_ms,
          events: events
        }

        analysis = compute_analysis(encounter)

        record
        |> Ecto.Changeset.change(%{analysis: analysis})
        |> Repo.update()

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to parse events for analysis: #{inspect(reason)}")
        {:ok, record}
    end
  end

  defp insert_or_fetch_encounter_from_boundary(boundary, clf) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Parse the start timestamp to get a NaiveDateTime for the encounter record
    start_time = parse_wow_timestamp(boundary.start_timestamp)
    end_time = parse_wow_timestamp(boundary.end_timestamp)

    difficulty_name = Encounter.difficulty_name_for(boundary.difficulty_id)

    encounter_attrs = %{
      wow_encounter_id: boundary.wow_encounter_id,
      name: boundary.name,
      difficulty_id: boundary.difficulty_id,
      difficulty_name: difficulty_name,
      group_size: boundary.group_size,
      instance_id: boundary.instance_id,
      start_time: start_time,
      end_time: end_time,
      success: boundary.success,
      fight_time_ms: boundary.fight_time_ms,
      start_byte: boundary.start_byte,
      end_byte: boundary.end_byte,
      combat_log_file_id: clf.id,
      is_reset: detect_reset?(boundary),
      analysis: %{},
      inserted_at: now,
      updated_at: now
    }

    {inserted_count, _result} =
      Repo.insert_all(
        EncounterRecord,
        [encounter_attrs],
        on_conflict: :nothing,
        conflict_target: [:combat_log_file_id, :start_time]
      )

    # Update last_parsed_byte after each encounter
    update_file_progress(clf, boundary.end_byte)

    encounter = fetch_encounter_for_boundary!(clf.id, start_time)

    case inserted_count do
      1 -> {:inserted, encounter}
      0 -> {:existing, encounter}
    end
  end

  defp fetch_encounter_for_boundary!(combat_log_file_id, start_time) do
    Repo.get_by!(EncounterRecord,
      combat_log_file_id: combat_log_file_id,
      start_time: start_time
    )
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

  # Parse WoW timestamp string "M/DD/YYYY HH:MM:SS.mmm-TZ" into DateTime
  defp parse_wow_timestamp(ts_str) when is_binary(ts_str) do
    # Strip timezone offset
    [datetime_part | _] = String.split(ts_str, ~r/[-+](?=\d+$)/)

    case String.split(datetime_part, " ") do
      [date_part, time_part] ->
        [month, day, year] = String.split(date_part, "/")
        [time_str, ms_str] = String.split(time_part, ".")
        [hour, minute, second] = String.split(time_str, ":")

        {:ok, naive} =
          NaiveDateTime.new(
            String.to_integer(year),
            String.to_integer(month),
            String.to_integer(day),
            String.to_integer(hour),
            String.to_integer(minute),
            String.to_integer(second),
            String.to_integer(ms_str) * 1000
          )

        DateTime.from_naive!(naive, "Etc/UTC")

      _ ->
        nil
    end
  end

  # Format a DateTime back to the WoW timestamp format for CombatLogParser
  defp format_timestamp(%DateTime{} = dt) do
    ms = div(dt.microsecond |> elem(0), 1000)

    "#{dt.month}/#{dt.day}/#{dt.year} #{String.pad_leading("#{dt.hour}", 2, "0")}:#{String.pad_leading("#{dt.minute}", 2, "0")}:#{String.pad_leading("#{dt.second}", 2, "0")}.#{ms}-0"
  end

  defp format_timestamp(%NaiveDateTime{} = dt) do
    ms = div(dt.microsecond |> elem(0), 1000)

    "#{dt.month}/#{dt.day}/#{dt.year} #{String.pad_leading("#{dt.hour}", 2, "0")}:#{String.pad_leading("#{dt.minute}", 2, "0")}:#{String.pad_leading("#{dt.second}", 2, "0")}.#{ms}-0"
  end

  defp format_timestamp(nil), do: "1/1/2000 00:00:00.000-0"

  # Auto-detect reset pulls: wipes under 15 seconds are almost certainly resets.
  # Kills are never flagged — could be an old instance farm.
  @reset_threshold_ms 15_000

  defp detect_reset?(%{success: true}), do: false

  defp detect_reset?(%{fight_time_ms: ms}) when is_integer(ms) and ms < @reset_threshold_ms,
    do: true

  defp detect_reset?(_), do: false

  defp update_file_progress(%CombatLogFile{} = clf, end_byte) do
    # Get updated file stats for mtime only
    # IMPORTANT: Use end_byte as file_size, not current disk size!
    # This avoids a race condition where WoW writes more data between
    # parsing and this update, causing us to skip content.
    {:ok, %{mtime: mtime}} = File.stat(clf.file_path)

    mtime_dt =
      NaiveDateTime.from_erl!(mtime)
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.truncate(:second)

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
