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
  attr(:sort_direction, :atom, default: :asc, values: [:asc, :desc])
  attr(:show_sort_control, :boolean, default: false)
  attr(:log_files, :list, default: [])
  attr(:loading, :boolean, default: false)
  attr(:base_path, :string, default: "")

  def render(assigns) do
    records = sort_records(assigns.encounter_records, assigns.sort_direction)
    groups = group_encounters(records)
    assigns = assign(assigns, :groups, groups)

    ~H"""
    <div :if={@encounter_records != []}>
      <div class="flex items-center justify-between mb-3">
        <h2 class="section-header mb-0">Encounters ({length(@encounter_records)})</h2>
        <div class="flex items-center gap-3">
          <button
            :if={@show_sort_control}
            id="encounter-sort-direction"
            type="button"
            phx-click="toggle_sort_direction"
            class="inline-flex items-center gap-1.5 rounded border border-zinc-600 bg-zinc-800 px-2.5 py-1.5 text-sm text-zinc-300 hover:border-zinc-500 hover:bg-zinc-700 hover:text-zinc-100"
            title={if @sort_direction == :asc, do: "Sort newest first", else: "Sort oldest first"}
          >
            <span aria-hidden="true">{if @sort_direction == :asc, do: "↑", else: "↓"}</span>
            {if @sort_direction == :asc, do: "Oldest first", else: "Newest first"}
          </button>
        </div>
      </div>
      <div class="space-y-6">
        <%= for group <- @groups do %>
          <.instance_group group={group} base_path={@base_path} />
        <% end %>
      </div>
    </div>

    <.empty_state :if={@encounter_records == [] && !@loading && @log_files != []} />
    """
  end

  # ── Instance Group ──

  attr(:group, :map, required: true)
  attr(:base_path, :string, default: "")

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
          <.encounter_card encounter={encounter} idx={idx} base_path={@base_path} />
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
  attr(:base_path, :string, default: "")

  defp encounter_card(assigns) do
    ~H"""
    <div class={[
      "encounter-card relative",
      if(@encounter.source_encounter_key, do: "group cursor-pointer", else: "cursor-default")
    ]}>
      <.link
        :if={@encounter.source_encounter_key}
        navigate={"#{@base_path}/encounters/#{@encounter.source_encounter_key}"}
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
        </div>
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

  defp group_encounters(records) do
    records
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

  defp sort_records(records, :asc), do: records
  defp sort_records(records, :desc), do: Enum.reverse(records)
end
