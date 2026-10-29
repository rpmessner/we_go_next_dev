defmodule WeGoNext.Analysis.Tools.Interrupts do
  @moduledoc "Today's silver interrupt observations, with explicit actionability limitations."
  @behaviour WeGoNext.Analysis.Tool
  import Ecto.Query
  alias WeGoNext.Analysis.Result
  alias WeGoNext.Analysis.Tools.SilverPulls
  alias WeGoNext.Repo
  alias WeGoNext.Silver.{InterruptOpportunity, PlayerInfo}

  @caveat "Interrupt silver currently overcounts opportunities and misses (we-23): these are overbroad NPC cast observations, not proven actionable kick assignments. Verify opportunity and miss counts with log_events; no assignment or kick-availability evidence is provided."

  def name, do: "interrupts"

  def description,
    do:
      "Read silver kickable casts, kicks and misses for gold pull ids in the session log. Counts cover the current page only. Follow next_cursor with identical filters. " <>
        @caveat

  def input_schema, do: SilverPulls.schema()

  def run(args, context) do
    with {:ok, pulls} <- SilverPulls.select(args, context) do
      ids = Enum.map(pulls, & &1.pull_id)
      starts = Map.new(pulls, &{&1.pull_id, &1.start_time})

      rows =
        Repo.all(
          from(i in InterruptOpportunity,
            left_join: p in PlayerInfo,
            on: p.encounter_dim_id == i.encounter_dim_id and p.player_guid == i.interrupter_guid,
            where: i.encounter_dim_id in ^ids,
            order_by: [
              i.encounter_dim_id,
              i.opportunity_ms_into_fight,
              i.target_npc_guid,
              i.interrupted_spell_id,
              i.id
            ],
            select: %{
              pull_id: i.encounter_dim_id,
              target_npc_guid: i.target_npc_guid,
              interrupted_spell_id: i.interrupted_spell_id,
              opportunity_ms_into_fight: i.opportunity_ms_into_fight,
              success: i.success,
              interrupter_guid: i.interrupter_guid,
              interrupter_name: p.player_name,
              interrupting_spell_id: i.interrupting_spell_id
            }
          )
        )
        |> Enum.map(fn row ->
          data = Map.put(row, :outcome, if(row.success, do: "kick", else: "miss"))

          evidence = %{
            pull_id: row.pull_id,
            source: "silver.interrupt_opportunity",
            timestamp: timestamp(starts[row.pull_id], row.opportunity_ms_into_fight),
            ms_into_fight: row.opportunity_ms_into_fight
          }

          {data, evidence}
        end)

      Result.page(rows, args, {name(), context.id}, &render/1)
    end
  end

  defp render(casts) do
    kicks = Enum.count(casts, & &1.success)

    %{
      casts: casts,
      counts_scope: "current_page",
      counts: %{kickable_casts: length(casts), kicks: kicks, misses: length(casts) - kicks},
      caveat: @caveat
    }
  end

  defp timestamp(nil, _ms), do: nil
  defp timestamp(start, ms), do: DateTime.add(start, ms, :millisecond)
end
