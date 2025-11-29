defmodule WeGoNextWeb.Components.Tabs.DamageDoneTab do
  @moduledoc """
  Damage Done tab component for encounter detail view.

  Displays DPS analysis:
  - Underperformer alerts
  - DPS/Healer breakdown
  - Tank damage breakdown
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents

  attr :stats, :map, required: true
  attr :player_classes, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Underperformers alert --%>
      <div :if={@stats.underperformers != []} class="bg-yellow-900/30 border border-yellow-800 rounded-lg p-4">
        <h3 class="text-yellow-400 font-medium mb-2">Low DPS (Not Due to Death)</h3>
        <p class="text-zinc-400 text-sm mb-3">
          These players have significantly lower DPS than the group median and didn't die.
        </p>
        <div class="space-y-2">
          <div :for={u <- @stats.underperformers} class="flex items-center gap-4 text-sm">
            <span class="font-medium">
              <.player_name name={u.player_name} player_classes={@player_classes} />
            </span>
            <span class="text-zinc-500">
              {format_dps(u.dps)} DPS
              <span class="text-yellow-500">({Float.round(u.percent_of_median, 0)}% of median)</span>
            </span>
          </div>
        </div>
      </div>

      <%!-- DPS/Healers section --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">DPS/Healers</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Player</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">DPS</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Total</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={player <- @stats.dps_healers} class={["hover:bg-zinc-750", Map.get(player, :death_time) && "opacity-60"]}>
                <td class="px-4 py-2">
                  <.player_name name={player.player_name} player_classes={@player_classes} />
                </td>
                <td class="px-4 py-2 text-right text-wow-gold font-medium">{format_dps(player.dps)}</td>
                <td class="px-4 py-2 text-right text-zinc-400">{format_damage_total(player.total)}</td>
                <td class="px-4 py-2 text-right">
                  <%= if Map.get(player, :death_time) do %>
                    <span class="text-red-400 text-sm">Died at {format_time(Map.get(player, :death_time))}</span>
                  <% else %>
                    <span class="text-green-400 text-sm">Survived</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Tanks section --%>
      <div :if={@stats.tanks != []}>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Tanks</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Player</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">DPS</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Total</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={player <- @stats.tanks} class={["hover:bg-zinc-750", Map.get(player, :death_time) && "opacity-60"]}>
                <td class="px-4 py-2">
                  <.player_name name={player.player_name} player_classes={@player_classes} />
                </td>
                <td class="px-4 py-2 text-right text-wow-gold font-medium">{format_dps(player.dps)}</td>
                <td class="px-4 py-2 text-right text-zinc-400">{format_damage_total(player.total)}</td>
                <td class="px-4 py-2 text-right">
                  <%= if Map.get(player, :death_time) do %>
                    <span class="text-red-400 text-sm">Died at {format_time(Map.get(player, :death_time))}</span>
                  <% else %>
                    <span class="text-green-400 text-sm">Survived</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Fight info --%>
      <div class="text-xs text-zinc-500">
        Fight duration: {format_time(@stats.fight_duration)}
      </div>
    </div>
    """
  end

  # Helper function for damage totals
  defp format_damage_total(num) when is_integer(num) and num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  defp format_damage_total(num) when is_integer(num) and num >= 1000 do
    "#{Float.round(num / 1000, 0) |> trunc()}k"
  end

  defp format_damage_total(num) when is_number(num), do: to_string(trunc(num))
  defp format_damage_total(_), do: "0"
end
