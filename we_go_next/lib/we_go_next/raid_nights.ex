defmodule WeGoNext.RaidNights do
  @moduledoc """
  Resolves the public-safe raid-night identity and display name for encounters.

  Filename time is the canonical identity, so moving a log into an archive does
  not change its raid night. The editable name remains local database state and
  is copied into generated encounter documents.
  """

  import Ecto.Query

  alias WeGoNext.{CombatLogFile, Documents, Repo}
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Mirror.Outbox

  def rename(%CombatLogFile{} = log, name) when is_binary(name) do
    with {:ok, updated_log} <-
           log
           |> CombatLogFile.changeset(%{raid_night_name: String.trim(name)})
           |> Repo.update(),
         :ok <- refresh_documents(updated_log) do
      {:ok, updated_log}
    end
  end

  def for_encounter(%DimEncounter{} = encounter) do
    encounter
    |> combat_log_query()
    |> order_by([log], desc: log.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      %CombatLogFile{} = log -> for_combat_log(log, encounter.start_time)
      nil -> from_datetime(encounter.start_time, nil)
    end
  end

  def for_combat_log(%CombatLogFile{} = log, fallback_datetime \\ nil) do
    datetime = CombatLogFile.filename_datetime(log.file_path) || fallback_datetime
    from_datetime(datetime, CombatLogFile.raid_night_name(log))
  end

  defp combat_log_query(%DimEncounter{source_head_sha256: head_sha256})
       when is_binary(head_sha256) do
    where(CombatLogFile, [log], log.head_sha256 == ^head_sha256)
  end

  defp combat_log_query(%DimEncounter{source_file_path: file_path}) do
    where(CombatLogFile, [log], log.file_path == ^file_path)
  end

  defp refresh_documents(log) do
    log
    |> encounter_ids_for_log()
    |> Enum.reduce_while(:ok, fn encounter_id, :ok ->
      case Documents.generate_for_encounter(encounter_id) do
        {:ok, result} ->
          if log.publish_enabled, do: Outbox.enqueue(result.source_encounter_key)
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp encounter_ids_for_log(%CombatLogFile{head_sha256: head_sha256})
       when is_binary(head_sha256) do
    DimEncounter
    |> where([encounter], encounter.source_head_sha256 == ^head_sha256)
    |> select([encounter], encounter.id)
    |> Repo.all()
  end

  defp encounter_ids_for_log(%CombatLogFile{file_path: file_path}) do
    DimEncounter
    |> where([encounter], encounter.source_file_path == ^file_path)
    |> select([encounter], encounter.id)
    |> Repo.all()
  end

  defp from_datetime(datetime, name) do
    naive = to_naive(datetime)

    %{
      key: if(naive, do: Calendar.strftime(naive, "%Y%m%dT%H%M%S"), else: "unknown"),
      date: if(naive, do: naive |> NaiveDateTime.to_date() |> Date.to_iso8601(), else: nil),
      name: name || default_name(naive)
    }
  end

  defp default_name(%NaiveDateTime{} = datetime),
    do: "Raid Night — #{Calendar.strftime(datetime, "%b %d, %Y")}"

  defp default_name(nil), do: "Raid Night"

  defp to_naive(%DateTime{} = datetime), do: DateTime.to_naive(datetime)
  defp to_naive(%NaiveDateTime{} = datetime), do: datetime
  defp to_naive(_datetime), do: nil
end
