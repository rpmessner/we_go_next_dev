defmodule WeGoNextWeb.Components.Tabs.InterruptsTab do
  @moduledoc """
  Interrupts tab component for encounter detail view.

  Displays interrupt analysis:
  - Interrupts by player
  - Missed interrupt casts
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents

  attr :stats, :map, required: true
  attr :criteria_by_spell, :map, required: true
  attr :player_classes, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- By player --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Interrupts by Player</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Player</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Total</th>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Spells Interrupted</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={{_guid, data} <- sorted_interrupters(@stats)} class="hover:bg-zinc-750">
                <td class="px-4 py-2">
                  <.player_name name={data.player_name} player_classes={@player_classes} />
                </td>
                <td class="px-4 py-2 text-right text-green-400 font-medium">{data.total_interrupts}</td>
                <td class="px-4 py-2 text-zinc-400 text-sm">
                  {data.by_spell |> Map.keys() |> Enum.join(", ")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Missed interrupts --%>
      <div :if={@stats.missed_casts != []}>
        <h3 class="text-sm font-medium text-red-400 mb-3">
          Missed Interrupts ({length(@stats.missed_casts)})
        </h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Time</th>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Spell</th>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Caster</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={cast <- Enum.take(@stats.missed_casts, 20)} class="hover:bg-zinc-750">
                <td class="px-4 py-2 text-zinc-500 font-mono text-sm">
                  {format_timestamp(cast.timestamp)}
                </td>
                <td class="px-4 py-2 text-red-400">
                  <.wowhead_link spell_id={cast.spell_id} name={cast.spell_name} />
                </td>
                <td class="px-4 py-2 text-zinc-400">{cast.caster_name}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp sorted_interrupters(stats) do
    stats.by_player
    |> Enum.sort_by(fn {_, data} -> data.total_interrupts end, :desc)
  end
end
