defmodule WeGoNext.Importer do
  @moduledoc """
  Imports combat log files into the database with incremental parsing support.

  Tracks byte offsets so subsequent imports only parse new content.
  """

  alias WeGoNext.{Repo, CombatLogFile, LogReader}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord
  import Ecto.Query

  @doc """
  Imports a combat log file, creating or updating the CombatLogFile record.
  Returns {:ok, %{file: combat_log_file, new_encounters: count}} on success.
  """
  def import_log(file_path, user_id) do
    case get_or_create_combat_log_file(file_path, user_id) do
      {:ok, clf} ->
        do_import(clf)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Syncs a combat log file, parsing only new content since last import.
  Accepts either a CombatLogFile struct or a file path string.
  """
  def sync_log(file_or_path)

  def sync_log(%CombatLogFile{} = clf) do
    if CombatLogFile.has_new_content?(clf) do
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
  def list_encounters(%CombatLogFile{id: id}) do
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

  defp do_import(%CombatLogFile{} = clf) do
    start_byte = clf.last_parsed_byte || 0

    case parse_from_byte(clf.file_path, start_byte) do
      {:ok, encounters_with_bytes, end_byte} ->
        # Insert encounters into database
        {inserted_count, _} = insert_encounters(encounters_with_bytes, clf.id)

        # Update file tracking
        {:ok, updated_clf} = update_file_progress(clf, end_byte)

        {:ok, %{file: updated_clf, new_encounters: inserted_count}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_from_byte(file_path, start_byte) do
    try do
      {encounters, end_byte} = LogReader.parse_file_with_bytes(file_path, start_byte)
      {:ok, encounters, end_byte}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp insert_encounters(encounters_with_bytes, combat_log_file_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    records =
      Enum.map(encounters_with_bytes, fn {encounter, raw_lines, start_byte, end_byte} ->
        EncounterRecord.from_parsed(encounter, raw_lines, combat_log_file_id, start_byte, end_byte)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(EncounterRecord, records)
  end

  defp update_file_progress(%CombatLogFile{} = clf, end_byte) do
    # Get updated file stats
    {:ok, %{size: file_size, mtime: mtime}} = File.stat(clf.file_path)
    mtime_dt = NaiveDateTime.from_erl!(mtime) |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)

    clf
    |> Ecto.Changeset.change(%{
      last_parsed_byte: end_byte,
      last_parsed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      file_size: file_size,
      file_mtime: mtime_dt
    })
    |> Repo.update()
  end
end
