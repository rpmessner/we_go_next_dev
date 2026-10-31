defmodule WeGoNextWeb.EncounterLive.DetailState do
  @moduledoc "Pure encounter detail transitions; tab and control values are orthogonal data."
  use WeGoNext.StateTable

  alias WeGoNext.Freshness

  @states ~w(missing stale empty fresh)a
  @events ~w(document params switch_tab toggle_untagged_mechanics toggle_player_debuffs toggle_death_heals select_personal_player)a
  @guards ~w(always missing stale empty)a
  @effects ~w(load_document set_tab patch_tab toggle_untagged toggle_debuffs toggle_heals select_player)a
  @tabs ~w(overview mechanics damage failures deaths interrupts personal)a
  @controls [
    {:params, [:set_tab]},
    {:switch_tab, [:set_tab, :patch_tab]},
    {:toggle_untagged_mechanics, [:toggle_untagged]},
    {:toggle_player_debuffs, [:toggle_debuffs]},
    {:toggle_death_heals, [:toggle_heals]},
    {:select_personal_player, [:select_player]}
  ]
  @rows Enum.flat_map(@states, fn state ->
          [
            {state, :document, :missing, :missing, [:load_document]},
            {state, :document, :stale, :stale, [:load_document]},
            {state, :document, :empty, :empty, [:load_document]},
            {state, :document, :always, :fresh, [:load_document]}
          ] ++
            Enum.map(@controls, fn {event, effects} ->
              {state, event, :always, state, effects}
            end)
        end)

  def initial do
    %{
      active_tab: :overview,
      show_untagged_mechanics: false,
      show_player_debuffs: false,
      death_heal_keys: MapSet.new(),
      selected_personal_player_guid: nil,
      selected_personal_player: nil,
      players: []
    }
  end

  def step(state, {event, input}, ctx) do
    case WeGoNext.StateTable.step(
           @rows,
           state,
           event,
           Map.put(ctx, :input, input),
           &guard/2,
           &reduce/2
         ) do
      {:ok, next, data, effects} -> {:ok, next, Map.delete(data, :input), effects}
      :invalid -> :invalid
    end
  end

  def step(state, event, ctx), do: step(state, {event, nil}, ctx)

  defp guard(:always, _ctx), do: true
  defp guard(:missing, ctx), do: is_nil(ctx.input)

  defp guard(:stale, ctx) do
    ctx.input
    |> Freshness.classify()
    |> Map.values()
    |> Enum.any?(&(&1 != :current))
  end

  defp guard(:empty, %{input: document}) do
    document.roster == [] and document.deaths == [] and
      document.failure_preview.mechanics == [] and
      document.pull_review.damage_done == [] and
      document.pull_review.damage_taken_spells == [] and
      document.pull_review.debuffs.all == [] and
      document.interrupt_coverage.spell_coverage == [] and
      document.observed_mechanics.mechanics == []
  end

  defp reduce(:load_document, %{input: nil} = ctx), do: ctx

  defp reduce(:load_document, %{input: document} = ctx) do
    summary = document.personal_pull_summary

    %{
      ctx
      | players: summary.players,
        selected_personal_player_guid: summary.selected_player_guid,
        selected_personal_player:
          Enum.find(summary.players, &(&1.player_guid == summary.selected_player_guid))
    }
  end

  defp reduce(:set_tab, ctx) do
    tab = Enum.find(@tabs, :overview, &(Atom.to_string(&1) == ctx.input))
    %{ctx | active_tab: tab}
  end

  defp reduce(:patch_tab, ctx), do: ctx

  defp reduce(:toggle_untagged, ctx),
    do: %{ctx | show_untagged_mechanics: not ctx.show_untagged_mechanics}

  defp reduce(:toggle_debuffs, ctx), do: %{ctx | show_player_debuffs: not ctx.show_player_debuffs}

  defp reduce(:toggle_heals, ctx) do
    keys = ctx.death_heal_keys

    keys =
      if MapSet.member?(keys, ctx.input),
        do: MapSet.delete(keys, ctx.input),
        else: MapSet.put(keys, ctx.input)

    %{ctx | death_heal_keys: keys}
  end

  defp reduce(:select_player, ctx) do
    %{
      ctx
      | selected_personal_player_guid: ctx.input,
        selected_personal_player: Enum.find(ctx.players, &(&1.player_guid == ctx.input))
    }
  end
end
