defmodule WeGoNext.Analysis.Tools.DamageTaken do
  @moduledoc "Silver damage taken at player × spell × pull grain, summed across sources."
  @behaviour WeGoNext.Analysis.Tool
  import Ecto.Query
  alias WeGoNext.Analysis.Result
  alias WeGoNext.Analysis.Tools.SilverPulls
  alias WeGoNext.Repo
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo}

  def name, do: "damage_taken"

  def description,
    do:
      "Silver player × spell hit counts and damage amounts for gold pull ids in the session log. Optional spell is an integer spell id (0 includes melee); player is an exact character name or GUID. Totals include all sources, not just avoidable damage. Evidence timestamps identify pull start, not individual hits. Follow next_cursor with identical filters."

  def input_schema,
    do:
      SilverPulls.schema(%{
        "spell" => %{"type" => "integer", "minimum" => 0},
        "player" => %{"type" => "string", "minLength" => 1}
      })

  def run(args, context) do
    with {:ok, pulls} <- SilverPulls.select(args, context) do
      ids = Enum.map(pulls, & &1.pull_id)
      starts = Map.new(pulls, &{&1.pull_id, &1.start_time})

      rows =
        from(d in DamageTaken,
          left_join: p in PlayerInfo,
          on: p.encounter_dim_id == d.encounter_dim_id and p.player_guid == d.target_guid,
          where: d.encounter_dim_id in ^ids,
          group_by: [d.encounter_dim_id, d.target_guid, p.player_name, d.spell_id],
          order_by: [d.encounter_dim_id, d.target_guid, d.spell_id],
          select: %{
            pull_id: d.encounter_dim_id,
            player_guid: d.target_guid,
            player_name: p.player_name,
            spell_id: d.spell_id,
            hit_count: type(sum(d.hit_count), :integer),
            total_amount: type(sum(d.total_amount), :integer)
          }
        )
        |> filter_spell(args["spell"])
        |> filter_player(args["player"])
        |> Repo.all()
        |> Enum.map(fn row ->
          {row,
           %{pull_id: row.pull_id, source: "silver.damage_taken", timestamp: starts[row.pull_id]}}
        end)

      Result.page(rows, args, {name(), context.id})
    end
  end

  defp filter_spell(query, nil), do: query
  defp filter_spell(query, spell), do: where(query, [d], d.spell_id == ^spell)
  defp filter_player(query, nil), do: query

  defp filter_player(query, player),
    do: where(query, [d, p], d.target_guid == ^player or p.player_name == ^player)
end
