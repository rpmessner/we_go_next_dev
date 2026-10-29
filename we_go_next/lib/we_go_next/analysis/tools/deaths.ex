defmodule WeGoNext.Analysis.Tools.Deaths do
  @moduledoc "Silver deaths with bounded, lossless recap fragments."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{PullScope, Result}
  alias WeGoNext.Gold.EncounterDetail

  def name, do: "deaths"

  def description,
    do:
      "List silver deaths in the requested gold pulls within this session log, ordered by pull then death time. Each row is one recap fragment with death_id, killing blow, recap_index (zero-based) and recap_count; concatenate damage_recap by death_id to recover the full recap. Deaths without recap still have a row. Follow next_cursor with identical arguments."

  def input_schema, do: PullScope.schema("pulls")

  def run(args, session) do
    with {:ok, pulls} <- PullScope.fetch(args["pulls"], session) do
      rows =
        Enum.flat_map(pulls, fn pull ->
          pull.pull_id
          |> EncounterDetail.deaths()
          |> Enum.flat_map(&fragments(&1, pull))
        end)

      Result.page(rows, args, {name(), session.id})
    end
  end

  defp fragments(death, pull) do
    base =
      death
      |> Map.take([
        :target_guid,
        :player_name,
        :class_id,
        :spec_id,
        :detected_role,
        :died_at_ms_into_fight,
        :killing_blow_spell_id,
        :killing_blow_source_guid,
        :killing_blow,
        :window_ms,
        :window_truncated
      ])
      |> Map.merge(%{
        death_id: death.id,
        pull_id: pull.pull_id,
        recap_count: length(death.damage_recap)
      })

    evidence = PullScope.evidence(pull, "silver.death", death.died_at_ms_into_fight)

    case death.damage_recap do
      [] ->
        [{Map.merge(base, %{damage_recap: [], recap_index: nil}), evidence}]

      recap ->
        Enum.with_index(recap, fn hit, index ->
          {Map.merge(base, %{damage_recap: [hit], recap_index: index}), evidence}
        end)
    end
  end
end
