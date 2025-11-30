defmodule WeGoNextWeb.Components.EncounterList do
  @moduledoc """
  Component for displaying the list of encounters from a combat log.

  Shows each encounter as a card with:
  - Boss name and difficulty
  - Kill/Wipe indicator
  - Fight duration
  - Death count
  - Admin gear menu for marking resets
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents, only: [format_duration: 1]

  attr :encounter_records, :list, required: true
  attr :show_resets, :boolean, required: true
  attr :open_menu_id, :any, default: nil
  attr :is_admin, :boolean, required: true
  attr :log_files, :list, default: []
  attr :loading, :boolean, default: false

  def render(assigns) do
    ~H"""
    <div :if={@encounter_records != []}>
      <div class="flex items-center justify-between mb-3">
        <h2 class="section-header mb-0">Encounters ({visible_count(@encounter_records, @show_resets)})</h2>
        <div :if={@is_admin && has_resets?(@encounter_records)} class="flex items-center gap-2">
          <label class="flex items-center gap-2 cursor-pointer text-sm text-zinc-400">
            <input
              type="checkbox"
              checked={@show_resets}
              phx-click="toggle_show_resets"
              class="rounded border-zinc-600 bg-zinc-700 text-blue-500 focus:ring-blue-500 focus:ring-offset-zinc-800"
            />
            Show resets ({reset_count(@encounter_records)})
          </label>
        </div>
      </div>
      <div class="space-y-2">
        <%= for {encounter, idx} <- filtered_encounters(@encounter_records, @show_resets) do %>
          <.encounter_card
            encounter={encounter}
            idx={idx}
            is_admin={@is_admin}
            open_menu_id={@open_menu_id}
          />
        <% end %>
      </div>
    </div>

    <.empty_state :if={@encounter_records == [] && !@loading && @log_files != []} />
    """
  end

  attr :encounter, :map, required: true
  attr :idx, :integer, required: true
  attr :is_admin, :boolean, required: true
  attr :open_menu_id, :any, default: nil

  defp encounter_card(assigns) do
    ~H"""
    <div class={["encounter-card", if(@encounter.is_reset, do: "opacity-50", else: "")]}>
      <div class="flex items-center justify-between">
        <.link href={"/encounters/#{@encounter.id}"} class="flex-1 flex items-center gap-3">
          <span class="text-zinc-500 font-mono text-sm w-6">{@idx}.</span>
          <div>
            <span class="font-semibold text-zinc-100">{@encounter.name}</span>
            <span class="text-zinc-500 ml-2">({@encounter.difficulty_name})</span>
            <span :if={@encounter.is_reset} class="ml-2 text-xs text-yellow-500">(Reset)</span>
          </div>
        </.link>
        <div class="flex items-center gap-4">
          <span class={[
            "inline-flex items-center px-2 py-1 rounded text-xs font-medium",
            if(@encounter.success,
              do: "bg-green-900 text-green-300",
              else: "bg-red-900 text-red-300"
            )
          ]}>
            {if @encounter.success, do: "KILL", else: "WIPE"}
          </span>
          <span class="text-zinc-400 font-mono text-sm">
            {format_duration(@encounter)}
          </span>
          <span class="text-zinc-500 text-sm">
            {death_count_from_record(@encounter)} deaths
          </span>
          <.gear_menu :if={@is_admin} encounter={@encounter} open_menu_id={@open_menu_id} />
        </div>
      </div>
    </div>
    """
  end

  attr :encounter, :map, required: true
  attr :open_menu_id, :any, default: nil

  defp gear_menu(assigns) do
    ~H"""
    <div class="relative">
      <button
        phx-click="toggle_menu"
        phx-value-id={@encounter.id}
        class="p-1.5 rounded text-zinc-500 hover:text-zinc-300 hover:bg-zinc-700 transition-colors"
        title="Options"
      >
        <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
        </svg>
      </button>
      <div
        :if={@open_menu_id == @encounter.id}
        class="absolute right-0 top-full mt-1 w-36 bg-zinc-800 border border-zinc-600 rounded-lg shadow-lg z-10"
        phx-click-away="close_menu"
      >
        <button
          phx-click="toggle_reset"
          phx-value-id={@encounter.id}
          class="w-full text-left px-3 py-2 text-sm text-zinc-300 hover:bg-zinc-700 rounded-lg transition-colors"
        >
          {if @encounter.is_reset, do: "Unmark as reset", else: "Mark as reset"}
        </button>
      </div>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="text-center py-12 text-zinc-500">
      <p class="text-lg">No encounters loaded</p>
      <p class="text-sm mt-2">Select a combat log file above to import</p>
    </div>
    """
  end

  # Helper functions

  defp death_count_from_record(record) do
    case record.analysis do
      %{"deaths" => deaths} when is_list(deaths) -> length(deaths)
      _ -> 0
    end
  end

  defp filtered_encounters(records, show_resets) do
    records
    |> Enum.with_index(1)
    |> Enum.reject(fn {record, _idx} ->
      not show_resets and record.is_reset
    end)
  end

  defp visible_count(records, show_resets) do
    if show_resets do
      length(records)
    else
      Enum.count(records, &(not &1.is_reset))
    end
  end

  defp reset_count(records) do
    Enum.count(records, & &1.is_reset)
  end

  defp has_resets?(records) do
    Enum.any?(records, & &1.is_reset)
  end
end
