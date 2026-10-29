defmodule WeGoNext.Analysis.Tools.Failures do
  @moduledoc "Per-pull, per-player mechanic failure facts from gold."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{PullScope, Result}
  alias WeGoNext.Gold.EncounterDetail

  def name, do: "failures"

  def description,
    do:
      "List gold mechanic failure facts across gold pulls in this session log. Optional player matches exact character name or GUID; mechanic matches exact spell name or spell id as a string. Each row is an aggregate for a pull/player/criterion, not an individual hit: evidence timestamp is pull start, not failure time. No rows does not prove a clean or fresh pull. Follow next_cursor with identical arguments."

  def input_schema,
    do:
      PullScope.schema("pulls", %{
        "player" => %{"type" => "string"},
        "mechanic" => %{"type" => "string"}
      })

  def run(args, session) do
    with {:ok, pulls} <- PullScope.fetch(args["pulls"], session) do
      rows =
        Enum.flat_map(pulls, fn pull ->
          pull.pull_id
          |> EncounterDetail.failure_preview()
          |> Map.fetch!(:mechanics)
          |> Enum.flat_map(&player_facts(&1, pull.pull_id))
          |> Enum.filter(&matches?(&1, args))
          |> Enum.sort_by(&{&1.criterion_dim_id, &1.player_guid})
          |> Enum.map(&{&1, PullScope.evidence(pull, "gold.fact_failure")})
        end)

      Result.page(rows, args, {name(), session.id})
    end
  end

  defp player_facts(mechanic, pull_id) do
    fields =
      Map.take(mechanic, [:criterion_dim_id, :spell_id, :spell_name, :mechanic_type, :boss_name])

    Enum.map(mechanic.players, fn player ->
      fields |> Map.merge(player) |> Map.put(:pull_id, pull_id)
    end)
  end

  defp matches?(row, args) do
    (is_nil(args["player"]) or args["player"] in [row.player_name, row.player_guid]) and
      (is_nil(args["mechanic"]) or args["mechanic"] in [row.spell_name, to_string(row.spell_id)])
  end
end
