defmodule WeGoNextWeb.Components.Tabs.DamageTakenTab do
  @moduledoc """
  Damage Taken tab component for encounter detail view.

  Displays damage taken analysis:
  - Top damaging abilities (non-tank)
  - Ability tracking controls
  - Per-player damage breakdown
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents

  alias WeGoNext.Analyzers.DamageTakenAnalyzer
  alias WeGoNext.Criteria.MechanicCriteria

  attr :stats, :map, required: true
  attr :encounter, :any, required: true
  attr :criteria_by_spell, :map, required: true
  attr :player_classes, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="space-y-6" id="damage-taken-tab" phx-hook="WowheadTooltips">
      <%!-- Top avoidable abilities --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Top Damaging Abilities (Non-Tank)</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Ability</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Total</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Hits</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Players</th>
                <th class="text-center text-xs font-medium text-zinc-400 px-4 py-2">Track</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={ability <- top_avoidable_abilities(@stats)} class="hover:bg-zinc-750">
                <td class="px-4 py-2">
                  <span class={[
                    if(Map.has_key?(@criteria_by_spell, ability.ability_id),
                      do: criteria_color(@criteria_by_spell, ability.ability_id),
                      else: "text-zinc-200")
                  ]}>
                    <.wowhead_link spell_id={ability.ability_id} name={ability.name} />
                  </span>
                  <span :if={criteria = get_criteria(@criteria_by_spell, ability.ability_id)} class="ml-2 text-xs">
                    ({MechanicCriteria.type_label(criteria.mechanic_type)})
                  </span>
                </td>
                <td class="px-4 py-2 text-right text-zinc-400">{format_number(ability.total)}</td>
                <td class="px-4 py-2 text-right text-zinc-500">{ability.hits}</td>
                <td class="px-4 py-2 text-right text-zinc-500">{ability.players}</td>
                <td class="px-4 py-2 text-center">
                  <%= if ability.ability_id && Map.has_key?(@criteria_by_spell, ability.ability_id) do %>
                    <button
                      phx-click="remove_criteria"
                      phx-value-spell-id={ability.ability_id}
                      class="text-xs text-red-400 hover:text-red-300"
                      title="Remove tracking"
                    >
                      ✕
                    </button>
                  <% else %>
                    <%= if ability.ability_id do %>
                      <button
                        phx-click="open_track_modal"
                        phx-value-spell-id={ability.ability_id}
                        phx-value-spell-name={ability.name}
                        class="text-xs text-wow-gold hover:text-yellow-400"
                        title="Track this ability"
                      >
                        + Track
                      </button>
                    <% else %>
                      <span class="text-xs text-zinc-600">-</span>
                    <% end %>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Player damage breakdown --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Damage Taken by Player</h3>
        <div class="grid grid-cols-2 gap-4">
          <div :for={player <- sorted_players(@stats)} class="bg-zinc-800 rounded-lg p-3">
            <div class="flex justify-between items-center mb-2">
              <span class="font-medium">
                <.player_name name={player.name} player_classes={@player_classes} />
                <span :if={player.is_tank} class="text-xs text-zinc-500 ml-1">(Tank)</span>
              </span>
              <span class="text-zinc-400">{format_number(player.total)}</span>
            </div>
            <div class="text-xs text-zinc-500">
              DTPS: {format_number(trunc(player.total / max(1, fight_seconds(@encounter))))}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp top_avoidable_abilities(stats) do
    DamageTakenAnalyzer.top_avoidable_abilities(stats, 10)
    |> Enum.map(fn {name, %{total: total, hits: hits, ability_id: ability_id, players: players}} ->
      %{name: name, total: total, hits: hits, ability_id: ability_id, players: players}
    end)
  end

  defp sorted_players(stats) do
    stats.all
    |> Enum.sort_by(& &1.total, :desc)
    |> Enum.map(fn player ->
      %{
        name: player.player_name,
        total: player.total,
        is_tank: player.role == :tank
      }
    end)
  end

  defp fight_seconds(%{fight_time_ms: ms}) when is_integer(ms), do: div(ms, 1000)
  defp fight_seconds(_), do: 1
end
