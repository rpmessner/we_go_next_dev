defmodule WeGoNextWeb.Components.EncounterList do
  @moduledoc """
  Component for displaying the list of encounters from a combat log.

  Groups encounters by instance (dungeon/raid) with headers showing
  instance name, difficulty, date, and kill/wipe summary.
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents, only: [format_duration: 1]

  alias WeGoNext.GameData.{Instances, Raids}

  attr(:encounter_records, :list, required: true)
  attr(:show_resets, :boolean, required: true)
  attr(:open_menu_id, :any, default: nil)
  attr(:is_admin, :boolean, required: true)
  attr(:log_files, :list, default: [])
  attr(:loading, :boolean, default: false)

  def render(assigns) do
    groups = group_encounters(assigns.encounter_records, assigns.show_resets)
    assigns = assign(assigns, :groups, groups)

    ~H"""
    <div :if={@encounter_records != []}>
      <div class="flex items-center justify-between mb-3">
        <h2 class="section-header mb-0">Encounters ({visible_count(@encounter_records, @show_resets)})</h2>
        <div :if={has_resets?(@encounter_records)} class="flex items-center gap-2">
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
      <div class="space-y-6">
        <%= for group <- @groups do %>
          <.instance_group group={group} is_admin={@is_admin} open_menu_id={@open_menu_id} />
        <% end %>
      </div>
    </div>

    <.empty_state :if={@encounter_records == [] && !@loading && @log_files != []} />
    """
  end

  # ── Instance Group ──

  attr(:group, :map, required: true)
  attr(:is_admin, :boolean, required: true)
  attr(:open_menu_id, :any, default: nil)

  defp instance_group(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-3 mb-2">
        <h3 class="text-sm font-semibold text-zinc-300">
          {@group.instance_name}
        </h3>
        <span class="text-xs text-zinc-500">{@group.difficulty}</span>
        <span class="text-xs text-zinc-600">&bull;</span>
        <span class="text-xs text-zinc-500">{@group.date_str}</span>
        <div class="flex-1 border-t border-zinc-700/50 ml-2"></div>
        <.group_summary group={@group} />
      </div>
      <div class="space-y-1.5 ml-0">
        <%= for {encounter, idx} <- @group.encounters do %>
          <.encounter_card
            encounter={encounter}
            idx={idx}
            is_admin={@is_admin}
            open_menu_id={@open_menu_id}
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp group_summary(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-xs">
      <span :if={@group.kills > 0} class="text-green-400">{@group.kills} kill{if @group.kills != 1, do: "s"}</span>
      <span :if={@group.wipes > 0} class="text-red-400">{@group.wipes} wipe{if @group.wipes != 1, do: "s"}</span>
    </div>
    """
  end

  # ── Encounter Card ──

  attr(:encounter, :map, required: true)
  attr(:idx, :integer, required: true)
  attr(:is_admin, :boolean, required: true)
  attr(:open_menu_id, :any, default: nil)

  defp encounter_card(assigns) do
    ~H"""
    <div class={[
      "encounter-card relative",
      if(@encounter.source_encounter_key, do: "group cursor-pointer", else: "cursor-default"),
      if(@encounter.is_reset, do: "opacity-50", else: "")
    ]}>
      <.link
        :if={@encounter.source_encounter_key}
        navigate={"/encounters/#{@encounter.source_encounter_key}"}
        class="absolute inset-0 rounded-lg focus:outline-none focus:ring-2 focus:ring-wow-gold focus:ring-offset-2 focus:ring-offset-zinc-900"
        aria-label={"Open #{@encounter.name}"}
      >
        <span class="sr-only">Open {@encounter.name}</span>
      </.link>

      <div class="pointer-events-none relative flex items-center justify-between">
        <div class="flex-1 flex items-center gap-3">
          <span class="text-zinc-500 font-mono text-sm w-6">{@idx}.</span>
          <div>
            <span class="font-semibold text-zinc-100 group-hover:text-wow-gold">
              {@encounter.name}
            </span>
            <span :if={@encounter.is_reset} class="ml-2 text-xs text-yellow-500">(Reset)</span>
          </div>
        </div>
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
          <div :if={@is_admin} class="pointer-events-auto relative z-10">
            <.gear_menu encounter={@encounter} open_menu_id={@open_menu_id} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Gear Menu ──

  attr(:encounter, :map, required: true)
  attr(:open_menu_id, :any, default: nil)

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

  # ============================================================================
  # Grouping Logic
  # ============================================================================

  defp group_encounters(records, show_resets) do
    records
    |> maybe_filter_resets(show_resets)
    |> Enum.chunk_by(&instance_group_key/1)
    |> Enum.map(fn chunk ->
      first = hd(chunk)

      instance_name =
        raid_instance_name(chunk) || Instances.name(first.instance_id) ||
          infer_instance_name(chunk)

      indexed = Enum.with_index(chunk, 1)
      kills = Enum.count(chunk, & &1.success)
      wipes = Enum.count(chunk, &(&1.success != true))

      %{
        instance_id: first.instance_id,
        instance_name: instance_name,
        difficulty: first.difficulty_name,
        date_str: format_date(first.start_time),
        encounters: indexed,
        kills: kills,
        wipes: wipes
      }
    end)
  end

  defp instance_group_key(encounter) do
    case raid_module(encounter) do
      nil -> {:instance, encounter.instance_id}
      raid_module -> {:raid, raid_module.info().slug}
    end
  end

  defp raid_instance_name(encounters) do
    encounters
    |> Enum.find_value(&raid_module/1)
    |> case do
      nil -> nil
      raid_module -> raid_module.info().name
    end
  end

  defp raid_module(encounter) do
    Raids.by_boss_encounter_id(encounter.wow_encounter_id)
  end

  # If we don't have a name mapping, infer from boss names
  defp infer_instance_name(encounters) do
    boss_names = encounters |> Enum.map(& &1.name) |> Enum.uniq()

    case boss_names do
      [single] ->
        single

      multiple ->
        Enum.join(Enum.take(multiple, 2), ", ") <> if(length(multiple) > 2, do: "...", else: "")
    end
  end

  defp format_date(nil), do: ""

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %I:%M %p")
  end

  defp format_date(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %I:%M %p")
  end

  defp maybe_filter_resets(records, true), do: records

  defp maybe_filter_resets(records, false) do
    Enum.reject(records, & &1.is_reset)
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
