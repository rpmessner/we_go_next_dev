defmodule WeGoNextWeb.Components.Tabs.DeathsTab do
  @moduledoc """
  Deaths tab component for encounter detail view.

  Displays all deaths that occurred during the encounter:
  - Death timeline with timestamps
  - Killing blow information
  - Damage recap for each death
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents

  attr :deaths, :list, required: true
  attr :player_classes, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div :if={@deaths == []} class="text-zinc-500 text-center py-8">
        No deaths in this encounter
      </div>
      <div :for={death <- @deaths} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <div class="flex items-center justify-between mb-2">
          <div class="flex items-center gap-3">
            <span class="text-wow-death font-mono">{format_time(death.time_into_fight)}</span>
            <span class="font-semibold">
              <.player_name name={death.player_name} player_classes={@player_classes} />
            </span>
          </div>
          <span :if={death.killing_blow} class="text-sm text-zinc-400">
            <.wowhead_link spell_id={death.killing_blow[:ability_id]} name={death.killing_blow.ability} />
            ({format_number(death.killing_blow.amount)})
          </span>
        </div>
        <div :if={death.killing_blow} class="text-sm text-zinc-400 mb-2">
          Killed by <span class="text-zinc-300">{death.killing_blow.source}</span>
          <span :if={death.killing_blow.overkill > 0} class="text-red-400 ml-2">
            ({format_number(death.killing_blow.overkill)} overkill)
          </span>
        </div>
        <div :if={death.recap != []} class="mt-3 pt-3 border-t border-zinc-700">
          <div class="text-xs text-zinc-500 mb-2">Last damage taken:</div>
          <div class="space-y-1">
            <div :for={event <- Enum.take(death.recap, 5)} class="text-sm flex justify-between">
              <span class="text-zinc-400">
                <.wowhead_link spell_id={event.ability_id} name={event.ability_name} />
              </span>
              <span class="text-zinc-500">
                {format_number(event.amount)} from {event.source_name}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
