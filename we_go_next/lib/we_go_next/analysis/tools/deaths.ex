defmodule WeGoNext.Analysis.Tools.Deaths do
  @moduledoc "Silver deaths with compact survival context and bounded, lossless recap fragments."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{PullScope, Result}
  alias WeGoNext.Gold.EncounterDetail

  def name, do: "deaths"

  def description,
    do:
      "List silver deaths in the requested gold pulls within this session log, ordered by pull then death time. Each row is one recap fragment with death_id, killing blow, recap_index (zero-based) and recap_count; concatenate damage_recap by death_id to recover the full recap. The first fragment (recap_index 0, or null without recap) also has survival: observed kit actions used in the death window (used_in_window) or active at death (died_through), with names and last-use pull-relative timestamps when recorded, plus externals received in the window. This compact summary omits cooldown/talent inference; an empty observed list is not proof that an action was available or unavailable. Survival is not repeated on later fragments. Deaths without recap still have a row. Follow next_cursor with identical arguments."

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
        [
          {Map.merge(base, %{damage_recap: [], recap_index: nil, survival: survival(death)}),
           evidence}
        ]

      recap ->
        Enum.with_index(recap, fn hit, index ->
          row = Map.merge(base, %{damage_recap: [hit], recap_index: index})
          {with_survival(row, death, index), evidence}
        end)
    end
  end

  defp with_survival(row, death, 0), do: Map.put(row, :survival, survival(death))
  defp with_survival(row, _death, _index), do: row

  defp survival(death) do
    %{
      observed:
        death.survival.kit
        |> Enum.filter(&(&1.state in [:used_in_window, :died_through]))
        |> Enum.map(&Map.take(&1, [:name, :state, :last_used_at_ms_into_fight])),
      externals_received:
        Enum.map(
          death.survival.externals_received,
          &Map.take(&1, [:spell_name, :caster_guid, :used_at_ms_into_fight])
        )
    }
  end
end
