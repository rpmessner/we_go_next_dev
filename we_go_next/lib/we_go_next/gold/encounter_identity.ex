defmodule WeGoNext.Gold.EncounterIdentity do
  @moduledoc """
  Explicit bridge from transitional public encounter records to gold encounter identity.

  New medallion UI routes and read models must use `gold.dim_encounter.id`.
  `public.encounters.id` remains an import/catalog identifier only. The bridge is
  intentionally small and uses the same source identity fields as the importer:
  source head fingerprint when available, otherwise source file path, plus the
  encounter start byte.
  """

  import Ecto.Query

  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord
  alias WeGoNext.Gold.DimEncounter

  @doc """
  Attaches `dim_encounter_id` to public encounter records for medallion navigation.
  """
  @spec attach_dim_encounter_ids([EncounterRecord.t()], CombatLogFile.t() | nil) :: [
          EncounterRecord.t()
        ]
  def attach_dim_encounter_ids(records, %CombatLogFile{} = combat_log_file)
      when is_list(records) do
    start_bytes = records |> Enum.map(& &1.start_byte) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    id_by_start_byte = dim_encounter_ids_by_start_byte(combat_log_file, start_bytes)

    Enum.map(records, fn %EncounterRecord{} = record ->
      %{record | dim_encounter_id: Map.get(id_by_start_byte, record.start_byte)}
    end)
  end

  def attach_dim_encounter_ids(records, _combat_log_file) when is_list(records), do: records

  @doc """
  Fetches the gold encounter dimension row for a transitional public encounter.
  """
  @spec fetch_for_public_encounter(EncounterRecord.t(), CombatLogFile.t()) ::
          DimEncounter.t() | nil
  def fetch_for_public_encounter(%EncounterRecord{} = record, %CombatLogFile{} = combat_log_file) do
    combat_log_file
    |> source_identity_query([record.start_byte])
    |> Repo.one()
  end

  defp dim_encounter_ids_by_start_byte(_combat_log_file, []), do: %{}

  defp dim_encounter_ids_by_start_byte(%CombatLogFile{} = combat_log_file, start_bytes) do
    combat_log_file
    |> source_identity_query(start_bytes)
    |> select([dim], {dim.start_byte, dim.id})
    |> Repo.all()
    |> Map.new()
  end

  defp source_identity_query(%CombatLogFile{} = combat_log_file, start_bytes) do
    DimEncounter
    |> where([dim], dim.start_byte in ^start_bytes)
    |> then(fn query ->
      if is_binary(combat_log_file.head_sha256) do
        where(query, [dim], dim.source_head_sha256 == ^combat_log_file.head_sha256)
      else
        where(query, [dim], dim.source_file_path == ^combat_log_file.file_path)
      end
    end)
  end
end
