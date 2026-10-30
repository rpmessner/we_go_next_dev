defmodule WeGoNext.Analysis.Tools.WipeCause do
  @moduledoc "Deterministic wipe attribution from stamped gold rows."
  @behaviour WeGoNext.Analysis.Tool
  import Ecto.Query
  alias WeGoNext.Analysis.{PullScope, Result}
  alias WeGoNext.Gold.{DimEncounter, FactWipeCause}
  alias WeGoNext.Repo
  alias WeGoNext.Silver.DeathDerivation

  def name, do: "wipe_cause"

  def description do
    "Why did this pull wipe? First three player deaths strictly before end minus 30 seconds, " <>
      "excluding kills and resets under 10s. Reads gold, never a model. These are earliest survival " <>
      "losses, not proof of the first mistake or causation. Unknown avoidability stays null. " <>
      "Includes the most common deciding killing blow across ALL requested pulls (death count, " <>
      "not pull count; ties by spell id). Missing/stale gold or silver must be rebuilt/reimported. " <>
      "Follow next_cursor with identical arguments."
  end

  def input_schema, do: PullScope.schema("pulls")

  def run(args, session) do
    with {:ok, pulls} <- PullScope.fetch(args["pulls"], session) do
      ids = Enum.map(pulls, & &1.pull_id)
      dimensions = Repo.all(from(e in DimEncounter, where: e.id in ^ids)) |> Map.new(&{&1.id, &1})
      facts = FactWipeCause.rows(ids)
      grouped = Enum.group_by(facts, & &1.encounter_dim_id)
      common = most_common(facts)

      rows =
        Enum.flat_map(pulls, fn pull ->
          dimension = Map.fetch!(dimensions, pull.pull_id)
          status = status(dimension)
          deaths = Map.get(grouped, pull.pull_id, [])
          data = if deaths == [], do: [%{pull_id: pull.pull_id, status: status}], else: deaths

          Enum.map(data, fn row ->
            ms = row[:died_at_ms_into_fight]

            {Map.merge(row, %{pull_id: pull.pull_id, status: status}),
             PullScope.evidence(pull, "gold.fact_wipe_cause", ms)}
          end)
        end)

      Result.page(rows, args, {name(), session.id}, fn page ->
        %{
          deciding_deaths: page,
          most_common_deciding_killing_blow: common,
          model_calls: 0,
          model_cost_usd: 0
        }
      end)
    end
  end

  def most_common(rows) do
    rows
    |> Enum.reject(&is_nil(&1.killing_blow_spell_id))
    |> Enum.group_by(& &1.killing_blow_spell_id)
    |> Enum.sort_by(fn {spell, deaths} -> {-length(deaths), spell} end)
    |> case do
      [] ->
        nil

      [{spell, deaths} | _] ->
        %{spell_id: spell, count: length(deaths), spell_name: hd(deaths).killing_blow_spell_name}
    end
  end

  defp status(e) do
    cond do
      e.silver_death_derivation_version != DeathDerivation.current_version() ->
        "stale_silver_deaths"

      e.wipe_cause_derivation_version != FactWipeCause.current_version() ->
        "missing_or_stale_gold"

      e.success == true ->
        "kill"

      is_integer(e.fight_time_ms) and e.fight_time_ms < 10_000 ->
        "reset"

      true ->
        "current"
    end
  end
end
