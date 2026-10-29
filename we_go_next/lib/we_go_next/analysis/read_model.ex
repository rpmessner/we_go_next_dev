defmodule WeGoNext.Analysis.ReadModel do
  @moduledoc "Log-scoped reads; never resolves the mutable current FileWatcher log."
  import Ecto.Query
  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.{DimEncounter, EncounterIdentity, FactFailure}
  alias WeGoNext.Gold.FactFailure.Derivation
  alias WeGoNext.Silver.PlayerInfo

  def log(context), do: Repo.get!(CombatLogFile, context.combat_log_file_id)

  def pulls(context) do
    log = log(context)

    Encounter
    |> where([p], p.combat_log_file_id == ^log.id)
    |> order_by([p], asc: p.start_time, asc: p.id)
    |> Repo.all()
    |> EncounterIdentity.attach_dim_encounter_ids(log)
    |> Enum.map_reduce(%{}, fn pull, counts ->
      number = Map.get(counts, pull.wow_encounter_id, 0) + 1

      row = %{
        pull_id: pull.dim_encounter_id,
        public_encounter_id: pull.id,
        boss: pull.name,
        boss_id: pull.wow_encounter_id,
        number: number,
        outcome: outcome(pull.success),
        duration_ms: pull.fight_time_ms,
        start_time: pull.start_time
      }

      {row, Map.put(counts, pull.wow_encounter_id, number)}
    end)
    |> elem(0)
  end

  def roster(pulls) do
    ids = Enum.map(pulls, & &1.pull_id) |> Enum.reject(&is_nil/1)

    Repo.all(
      from(p in PlayerInfo,
        join: d in DimEncounter,
        on: d.id == p.encounter_dim_id,
        where: p.encounter_dim_id in ^ids,
        distinct: p.player_guid,
        order_by: [asc: p.player_guid, desc: d.start_time, desc: p.encounter_dim_id],
        select: %{
          name: p.player_name,
          guid: p.player_guid,
          class_id: p.class_id,
          spec_id: p.spec_id,
          role: p.detected_role,
          pull_id: p.encounter_dim_id,
          timestamp: d.start_time
        }
      )
    )
  end

  def freshness(pulls, log) do
    ids = Enum.map(pulls, & &1.pull_id) |> Enum.reject(&is_nil/1)

    stale =
      Repo.all(
        from(f in FactFailure,
          where:
            f.encounter_dim_id in ^ids and
              fragment(
                "? IS DISTINCT FROM ?",
                f.derivation_version,
                ^Derivation.current_version()
              ),
          distinct: true,
          order_by: f.encounter_dim_id,
          select: f.encounter_dim_id
        )
      )

    %{
      current_failure_derivation: Derivation.current_version(),
      stale_failure_pull_ids: stale,
      unimported_pull_ids: for(p <- pulls, is_nil(p.pull_id), do: p.public_encounter_id),
      unparsed_bytes: max((log.file_size || 0) - (log.last_parsed_byte || 0), 0),
      caveat:
        "Missing gold ids are catalogued pulls without medallion import. Unparsed bytes may include trash or an unfinished pull. No failure rows does not prove freshness."
    }
  end

  def evidence(pull),
    do: %{
      pull_id: pull.pull_id,
      source: "public.encounters + gold.dim_encounter",
      timestamp: pull.start_time
    }

  defp outcome(true), do: "kill"
  defp outcome(false), do: "wipe"
  defp outcome(nil), do: "unknown"
end
