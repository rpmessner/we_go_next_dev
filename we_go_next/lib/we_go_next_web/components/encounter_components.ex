defmodule WeGoNextWeb.EncounterComponents do
  @moduledoc """
  Shared UI components for encounter and gold-backed diagnostic views.

  These components are used across multiple tabs and pages:
  - `wowhead_link/1` - Links to Wowhead spell pages with tooltips
  - `player_name/1` - Player names with WoW class colors
  - `tab_button/1` - Tab navigation buttons

  Also provides formatting helpers for common display patterns.
  """
  use Phoenix.Component

  alias WeGoNext.WowClass

  # ============================================================================
  # Wowhead Link Component
  # ============================================================================

  @doc """
  Renders a link to a spell on Wowhead with tooltip support.

  ## Examples

      <.wowhead_link spell_id={12345} name="Fireball" />
      <.wowhead_link spell_id={12345} name="Fireball" class="text-red-400" />
  """
  attr(:spell_id, :integer, required: true)
  attr(:name, :string, required: true)
  attr(:class, :string, default: nil)
  attr(:rename, :boolean, default: true)

  def wowhead_link(assigns) do
    ~H"""
    <a
      :if={@spell_id}
      href={"https://www.wowhead.com/spell=#{@spell_id}"}
      data-wowhead={"spell=#{@spell_id}"}
      data-wh-rename-link={@rename && "true"}
      target="_blank"
      rel="noopener noreferrer"
      class={[@class || "text-inherit hover:text-blue-400 hover:underline"]}
      title={"View #{@name} on Wowhead"}
    >
      {@name}
    </a>
    <span :if={!@spell_id}>{@name}</span>
    """
  end

  # ============================================================================
  # Player Name Component
  # ============================================================================

  @doc """
  Renders a player name with their WoW class color.

  The `player_classes` map should be keyed by the short player name (without realm suffix)
  and contain the class ID as the value.

  ## Examples

      <.player_name name="Mittwoch-WyrmrestAccord" player_classes={%{"Mittwoch" => 9}} />
  """
  attr(:name, :string, required: true)
  attr(:player_classes, :map, required: true)
  attr(:class, :string, default: nil)

  def player_name(assigns) do
    # Strip realm suffix for lookup (player_classes uses short names like "Zeddigos",
    # but other analyzers use full names like "Zeddigos-WyrmrestAccord-US")
    short_name = assigns.name |> String.split("-") |> List.first()
    class_id = Map.get(assigns.player_classes, short_name)
    color = if class_id, do: WowClass.class_color(class_id), else: nil

    assigns = assign(assigns, :color, color)

    ~H"""
    <span style={@color && "color: #{@color}"} class={@class}>
      {@name}
    </span>
    """
  end

  # ============================================================================
  # Tab Button Component
  # ============================================================================

  @doc """
  Renders a tab navigation button.

  ## Examples

      <.tab_button tab={:summary} active={@active_tab} count={nil}>
        Summary
      </.tab_button>

      <.tab_button tab={:failures} active={@active_tab} count={5} highlight={true}>
        Failures
      </.tab_button>
  """
  attr(:tab, :atom, required: true)
  attr(:active, :atom, required: true)
  attr(:count, :any, default: nil)
  attr(:highlight, :boolean, default: false)
  slot(:inner_block, required: true)

  def tab_button(assigns) do
    ~H"""
    <button
      phx-click="switch_tab"
      phx-value-tab={@tab}
      class={[
        "pb-3 px-1 text-sm font-medium border-b-2 transition-colors",
        cond do
          @active == @tab -> "border-wow-gold text-wow-gold"
          @highlight -> "border-transparent text-red-400 hover:text-red-300 hover:border-red-600"
          true -> "border-transparent text-zinc-400 hover:text-zinc-200 hover:border-zinc-600"
        end
      ]}
    >
      {render_slot(@inner_block)}
      <span :if={@count} class={["ml-1", if(@highlight && @count > 0, do: "text-red-400", else: "text-zinc-500")]}>
        ({@count})
      </span>
    </button>
    """
  end

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  @doc "Format duration from an encounter struct with fight_time_ms"
  def format_duration(%{fight_time_ms: ms}) when is_integer(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  def format_duration(_), do: "0:00"

  @doc "Format seconds as mm:ss"
  def format_time(seconds) when is_number(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  def format_time(_), do: "0:00"

  @doc "Format a number with k/M suffixes"
  def format_number(num) when is_integer(num) and num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  def format_number(num) when is_integer(num) and num >= 1000 do
    "#{Float.round(num / 1000, 0) |> trunc()}k"
  end

  def format_number(num) when is_number(num), do: to_string(trunc(num))
  def format_number(_), do: "0"

  @doc "Format a death's killing blow from its damage recap"
  def format_killing_blow(%{killing_blow: %{} = killing_blow}) do
    spell_name = recap_value(killing_blow, "spell_name") || "Unknown"
    amount = recap_value(killing_blow, "amount") || 0
    overkill = recap_value(killing_blow, "overkill") || 0

    overkill_text =
      if overkill > 0 do
        " with #{format_number(overkill)} overkill"
      else
        ""
      end

    "#{spell_name} for #{format_number(amount)}#{overkill_text}"
  end

  def format_killing_blow(%{killing_blow_spell_id: spell_id}) when not is_nil(spell_id) do
    "Spell #{spell_id}"
  end

  def format_killing_blow(_death), do: "Unknown killing blow"

  @doc "Read a damage-recap event value by string or atom key"
  def recap_value(%{} = event, key),
    do: Map.get(event, key) || Map.get(event, String.to_atom(key))

  def recap_value(_event, _key), do: nil

  @doc "Format DPS with k/M suffixes"
  def format_dps(dps) when is_float(dps) do
    cond do
      dps >= 1_000_000 -> "#{Float.round(dps / 1_000_000, 1)}M"
      dps >= 1000 -> "#{Float.round(dps / 1000, 1)}k"
      true -> "#{Float.round(dps, 0) |> trunc()}"
    end
  end

  def format_dps(dps) when is_integer(dps), do: format_dps(dps / 1)
  def format_dps(_), do: "0"

  @doc "Format file size with KB/MB suffixes"
  def format_size(bytes) when bytes >= 1_000_000 do
    "#{Float.round(bytes / 1_000_000, 1)} MB"
  end

  def format_size(bytes) when bytes >= 1000 do
    "#{div(bytes, 1000)} KB"
  end

  def format_size(bytes), do: "#{bytes} B"

  @doc "Format a timestamp as mm:ss"
  def format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%M:%S")
  end

  @doc "Get severity badge color classes"
  def severity_badge_color(:critical), do: "bg-red-900 text-red-300"
  def severity_badge_color(:high), do: "bg-orange-900 text-orange-300"
  def severity_badge_color(:medium), do: "bg-yellow-900 text-yellow-300"
  def severity_badge_color(:low), do: "bg-zinc-700 text-zinc-300"
  def severity_badge_color(_), do: "bg-zinc-700 text-zinc-300"
  # --- Death-window survival strip and window table (we-qop) ---
  #
  # Shared by the operator and public death recap cards. Values come from
  # the encounter document contract, so they may be atoms fresh from
  # analysis or strings after the JSON round trip — compare via strings.

  def format_ms(ms) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)

    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  def format_ms(_ms), do: "0:00"

  def survival_strip(assigns) do
    survival = doc_field(assigns.death, :survival)

    assigns =
      assigns
      |> assign(:survival, survival)
      |> assign(:defensives, survival_group(survival, :defensives))
      |> assign(:untalented, survival_group(survival, :untalented))
      |> assign(:consumables, survival_group(survival, :consumables))
      |> assign(:externals, (survival && doc_field(survival, :externals_received)) || [])

    ~H"""
    <div
      :if={@survival == nil}
      class="mt-3 rounded border border-zinc-700 bg-zinc-900/60 px-3 py-2 text-xs text-zinc-500"
    >
      No survival analysis in this document — rebuild encounter documents to add it.
    </div>
    <div :if={@survival} class="mt-3 rounded border border-zinc-700 bg-zinc-900/60 p-3">
      <div class="flex flex-wrap gap-x-8 gap-y-3">
        <div :if={@defensives != []}>
          <div class="text-[11px] uppercase tracking-wide text-zinc-500">Defensives</div>
          <div class="mt-1 flex flex-wrap gap-1.5">
            <.survival_chip :for={entry <- @defensives} entry={entry} />
          </div>
        </div>

        <div :if={@consumables != []}>
          <div class="text-[11px] uppercase tracking-wide text-zinc-500">Rocks &amp; Pots</div>
          <div class="mt-1 flex flex-wrap gap-1.5">
            <.survival_chip :for={entry <- @consumables} entry={entry} />
          </div>
        </div>

        <div :if={@untalented != []}>
          <div class="text-[11px] uppercase tracking-wide text-zinc-500">Untalented</div>
          <div class="mt-1 max-w-xs text-xs leading-5 text-zinc-500">
            {Enum.map_join(@untalented, ", ", &(doc_field(&1, :name) || "Unknown"))}
          </div>
        </div>

        <div :if={@externals != []}>
          <div class="text-[11px] uppercase tracking-wide text-zinc-500">Externals received</div>
          <div class="mt-1 space-y-0.5 text-xs text-zinc-300">
            <div :for={external <- @externals}>
              {doc_field(external, :spell_name)}
              <span class="text-zinc-500">
                at {format_ms(doc_field(external, :used_at_ms_into_fight))}
              </span>
            </div>
          </div>
        </div>
      </div>

      <p :if={survival_consumables_only?(@survival)} class="mt-2 text-xs text-zinc-500">
        No catalog defensives for this class/spec — only rocks and pots are tracked.
      </p>
      <p :if={survival_talents_unknown?(@survival)} class="mt-2 text-xs text-zinc-500">
        No talent data in this log for this player — defensive availability is unknown.
      </p>
      <p :if={survival_any_inferred?(@survival)} class="mt-2 text-[11px] text-zinc-600">
        Cooldown and availability are inferred from observed uses; encounter-start state is unknown.
      </p>
    </div>
    """
  end

  def death_window_table(assigns) do
    heals_visible = death_heals_visible?(assigns.heal_keys, assigns.death)

    assigns =
      assigns
      |> assign(:heals_visible, heals_visible)
      |> assign(:window_rows, death_window_rows(assigns.death, heals_visible))
      |> assign(:heal_count, death_heal_count(assigns.death))

    ~H"""
    <div class="mt-4">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <p class="text-xs text-zinc-500">
          Events in the final {format_window_seconds(@death)} before death.
        </p>
        <label
          :if={@heal_count > 0}
          class="flex cursor-pointer items-center gap-1.5 text-xs text-zinc-400"
        >
          <input
            type="checkbox"
            checked={@heals_visible}
            phx-click="toggle_death_heals"
            phx-value-key={death_key(@death)}
            class="h-3.5 w-3.5 rounded border-zinc-600 bg-zinc-900"
          />
          Show {@heal_count} heal {if @heal_count == 1, do: "row", else: "rows"}
        </label>
      </div>
      <p :if={doc_field(@death, :window_truncated)} class="mt-1 text-xs text-amber-400/80">
        Burst window truncated to the events closest to death.
      </p>

      <div class="mt-2 overflow-x-auto">
        <table class="w-full">
          <thead>
            <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
              <th class="px-3 py-2">Time</th>
              <th class="px-3 py-2">Event</th>
              <th class="px-3 py-2">Source</th>
              <th class="px-3 py-2 text-right">Amount</th>
              <th class="px-3 py-2 text-right">Overkill / Overheal</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@window_rows == []} class="border-b border-zinc-700/60 last:border-0">
              <td colspan="5" class="px-3 py-3 text-sm text-zinc-400">
                No events captured in the death window.
              </td>
            </tr>
            <tr :for={event <- @window_rows} class={death_row_class(event)}>
              <td class="px-3 py-2 font-mono text-sm text-zinc-300">
                {format_ms(recap_value(event, "ms_into_fight"))}
              </td>
              <td class="px-3 py-2 text-sm text-zinc-100">
                <span
                  :if={death_row_badge(event)}
                  class={[
                    "mr-1.5 rounded px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide",
                    death_row_badge_class(event)
                  ]}
                >
                  {death_row_badge(event)}
                </span>
                <.wowhead_link
                  :if={recap_value(event, "spell_id")}
                  spell_id={recap_value(event, "spell_id")}
                  name={recap_value(event, "spell_name") || "Unknown"}
                />
                <span :if={!recap_value(event, "spell_id")}>
                  {recap_value(event, "spell_name") || "Unknown"}
                </span>
                <span :if={recap_value(event, "spell_id")} class="text-xs text-zinc-500">
                  ({recap_value(event, "spell_id")})
                </span>
              </td>
              <td class="px-3 py-2 text-sm text-zinc-300">
                {death_row_source(event, @death)}
              </td>
              <td class="px-3 py-2 text-right font-mono text-sm text-zinc-300">
                {format_optional_amount(death_row_amount(event))}
              </td>
              <td class="px-3 py-2 text-right font-mono text-sm text-zinc-300">
                {format_optional_amount(death_row_over(event))}
              </td>
            </tr>
          </tbody>
          <tfoot :if={@heals_visible and death_heal_total(@death) > 0}>
            <tr class="border-t border-zinc-700 text-xs text-zinc-400">
              <td colspan="3" class="px-3 py-2">Heals received in window</td>
              <td class="px-3 py-2 text-right font-mono">
                {format_number(death_heal_total(@death))}
              </td>
              <td class="px-3 py-2 text-right font-mono">
                {format_number(death_overheal_total(@death))}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
    """
  end

  defp survival_chip(assigns) do
    {label, chip_class} = survival_chip_style(survival_value(assigns.entry, :state))

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:chip_class, chip_class)

    ~H"""
    <span class={["rounded border px-1.5 py-0.5 text-xs", @chip_class]}>
      {doc_field(@entry, :name)} <span class="opacity-80">· {@label}</span>
    </span>
    """
  end

  defp survival_chip_style("died_through"),
    do: {"died through", "border-red-500/60 bg-red-500/10 font-semibold text-red-300"}

  defp survival_chip_style("used_in_window"),
    do: {"used", "border-emerald-500/50 bg-emerald-500/10 text-emerald-300"}

  defp survival_chip_style("on_cooldown"),
    do: {"on cooldown (inferred)", "border-amber-500/40 bg-amber-500/10 text-amber-300"}

  defp survival_chip_style("available_unused"),
    do: {"available, unused", "border-orange-500/40 bg-orange-500/10 text-orange-300"}

  defp survival_chip_style("not_talented"),
    do: {"untalented", "border-zinc-600 bg-zinc-800 text-zinc-400"}

  defp survival_chip_style(_state),
    do: {"unknown", "border-zinc-600 bg-zinc-800 text-zinc-500"}

  defp survival_group(nil, _group), do: []

  defp survival_group(survival, group) do
    kit = doc_field(survival, :kit) || []

    case group do
      :consumables ->
        Enum.filter(kit, &(survival_value(&1, :category) == "consumable"))

      :untalented ->
        Enum.filter(
          kit,
          &(survival_value(&1, :category) != "consumable" and
              survival_value(&1, :availability) == "not_talented")
        )

      :defensives ->
        Enum.filter(
          kit,
          &(survival_value(&1, :category) != "consumable" and
              survival_value(&1, :availability) != "not_talented")
        )
    end
  end

  defp survival_value(entry, key) do
    case doc_field(entry, key) do
      nil -> nil
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end
  end

  defp survival_talents_unknown?(survival) do
    defensives =
      (doc_field(survival, :kit) || [])
      |> Enum.reject(&(survival_value(&1, :category) == "consumable"))

    defensives != [] and Enum.all?(defensives, &(survival_value(&1, :availability) == "unknown"))
  end

  defp survival_consumables_only?(survival) do
    kit = doc_field(survival, :kit) || []
    kit != [] and Enum.all?(kit, &(survival_value(&1, :category) == "consumable"))
  end

  defp survival_any_inferred?(survival) do
    Enum.any?(doc_field(survival, :kit) || [], &(survival_value(&1, :basis) == "inferred"))
  end

  defp death_key(death) do
    "#{doc_field(death, :target_guid)}:#{doc_field(death, :died_at_ms_into_fight)}"
  end

  defp death_heals_visible?(heal_keys, death) do
    MapSet.member?(heal_keys, death_key(death))
  end

  # Old documents predate window_events; fall back to the damage recap so
  # version-1 documents keep rendering (oldest-first to match window order).
  defp death_window_rows(death, heals_visible) do
    rows =
      case doc_field(death, :window_events) do
        events when is_list(events) and events != [] ->
          events

        _missing ->
          (doc_field(death, :damage_recap) || [])
          |> Enum.reverse()
          |> Enum.map(&Map.put(&1, "kind", "damage"))
      end

    if heals_visible do
      rows
    else
      Enum.reject(rows, &(recap_value(&1, "kind") == "heal"))
    end
  end

  defp death_heal_rows(death) do
    death
    |> doc_field(:window_events)
    |> List.wrap()
    |> Enum.filter(&(recap_value(&1, "kind") == "heal"))
  end

  defp death_heal_count(death), do: length(death_heal_rows(death))

  defp death_heal_total(death) do
    death |> death_heal_rows() |> Enum.map(&(recap_value(&1, "amount") || 0)) |> Enum.sum()
  end

  defp death_overheal_total(death) do
    death |> death_heal_rows() |> Enum.map(&(recap_value(&1, "overheal") || 0)) |> Enum.sum()
  end

  defp format_window_seconds(death) do
    case doc_field(death, :window_ms) do
      window_ms when is_integer(window_ms) and window_ms > 0 -> "#{div(window_ms, 1000)}s"
      _window_ms -> "10s"
    end
  end

  defp death_row_class(event) do
    base = "border-b border-zinc-700/60 last:border-0"

    case recap_value(event, "kind") do
      "survival_action" -> [base, "border-l-2 border-l-emerald-500/70 bg-emerald-500/5"]
      "heal" -> [base, "text-teal-300/90"]
      _kind -> base
    end
  end

  defp death_row_badge(event) do
    case recap_value(event, "kind") do
      "survival_action" -> "used"
      "heal" -> "heal"
      _kind -> nil
    end
  end

  defp death_row_badge_class(event) do
    case recap_value(event, "kind") do
      "survival_action" -> "bg-emerald-500/15 text-emerald-300"
      _kind -> "bg-teal-500/15 text-teal-300"
    end
  end

  defp death_row_source(event, death) do
    case recap_value(event, "kind") do
      "survival_action" ->
        caster_guid = recap_value(event, "caster_guid")
        if caster_guid == doc_field(death, :target_guid), do: "self", else: caster_guid

      _kind ->
        recap_value(event, "source_name") || recap_value(event, "source_guid") || "Unknown"
    end
  end

  defp death_row_amount(event) do
    case recap_value(event, "kind") do
      "survival_action" -> recap_value(event, "heal_amount")
      _kind -> recap_value(event, "amount")
    end
  end

  defp death_row_over(event) do
    case recap_value(event, "kind") do
      "survival_action" -> recap_value(event, "overheal_amount")
      "heal" -> recap_value(event, "overheal")
      _kind -> recap_value(event, "overkill")
    end
  end

  defp format_optional_amount(amount) when is_integer(amount), do: format_number(amount)
  defp format_optional_amount(_amount), do: "—"

  defp doc_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp doc_field(_map, _key), do: nil
end
