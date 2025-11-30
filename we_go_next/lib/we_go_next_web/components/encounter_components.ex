defmodule WeGoNextWeb.EncounterComponents do
  @moduledoc """
  Shared UI components for encounter analysis views.

  These components are used across multiple tabs and pages:
  - `wowhead_link/1` - Links to Wowhead spell pages with tooltips
  - `player_name/1` - Player names with WoW class colors
  - `tab_button/1` - Tab navigation buttons
  - `criteria_modal/1` - Modal for tracking mechanics

  Also provides formatting helpers for common display patterns.
  """
  use Phoenix.Component

  alias WeGoNext.WowClass
  alias WeGoNext.Criteria.MechanicCriteria

  # ============================================================================
  # Wowhead Link Component
  # ============================================================================

  @doc """
  Renders a link to a spell on Wowhead with tooltip support.

  ## Examples

      <.wowhead_link spell_id={12345} name="Fireball" />
      <.wowhead_link spell_id={12345} name="Fireball" class="text-red-400" />
  """
  attr :spell_id, :integer, required: true
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def wowhead_link(assigns) do
    ~H"""
    <a
      :if={@spell_id}
      href={"https://www.wowhead.com/spell=#{@spell_id}"}
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
  attr :name, :string, required: true
  attr :player_classes, :map, required: true
  attr :class, :string, default: nil

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
  attr :tab, :atom, required: true
  attr :active, :atom, required: true
  attr :count, :any, default: nil
  attr :highlight, :boolean, default: false
  slot :inner_block, required: true

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
  # Criteria Modal Component
  # ============================================================================

  @doc """
  Renders a modal for selecting mechanic criteria type.

  Used when marking a spell as "avoidable", "must interrupt", etc.
  """
  attr :spell_name, :string, required: true
  attr :spell_id, :integer, required: true

  def criteria_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center" phx-click="close_modal">
      <div class="bg-zinc-800 rounded-lg p-6 max-w-md w-full mx-4 border border-zinc-600" phx-click-away="close_modal">
        <h3 class="text-lg font-semibold text-wow-gold mb-2">Track Mechanic</h3>
        <p class="text-zinc-400 mb-4">
          Mark <span class="text-zinc-200 font-medium">{@spell_name}</span> as:
        </p>

        <div class="space-y-2">
          <button
            phx-click="create_criteria"
            phx-value-mechanic_type="avoidable"
            class="w-full text-left px-4 py-3 rounded bg-zinc-700 hover:bg-zinc-600 transition-colors"
          >
            <span class="text-red-400 font-medium">Avoidable Damage</span>
            <p class="text-sm text-zinc-400">Damage players should avoid (standing in fire)</p>
          </button>

          <button
            phx-click="create_criteria"
            phx-value-mechanic_type="interrupt"
            class="w-full text-left px-4 py-3 rounded bg-zinc-700 hover:bg-zinc-600 transition-colors"
          >
            <span class="text-yellow-400 font-medium">Must Interrupt</span>
            <p class="text-sm text-zinc-400">Casts that must be kicked</p>
          </button>

          <button
            phx-click="create_criteria"
            phx-value-mechanic_type="soak"
            class="w-full text-left px-4 py-3 rounded bg-zinc-700 hover:bg-zinc-600 transition-colors"
          >
            <span class="text-blue-400 font-medium">Soak Mechanic</span>
            <p class="text-sm text-zinc-400">Damage that needs to be shared</p>
          </button>

          <button
            phx-click="create_criteria"
            phx-value-mechanic_type="spread"
            class="w-full text-left px-4 py-3 rounded bg-zinc-700 hover:bg-zinc-600 transition-colors"
          >
            <span class="text-purple-400 font-medium">Spread Out</span>
            <p class="text-sm text-zinc-400">Players need to spread apart</p>
          </button>
        </div>

        <button
          phx-click="close_modal"
          class="mt-4 w-full px-4 py-2 text-zinc-400 hover:text-zinc-200 transition-colors"
        >
          Cancel
        </button>
      </div>
    </div>
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

  # ============================================================================
  # Criteria Helpers
  # ============================================================================

  @doc "Get mechanic type color class"
  def mechanic_type_color("avoidable"), do: "text-red-400"
  def mechanic_type_color("interrupt"), do: "text-yellow-400"
  def mechanic_type_color("soak"), do: "text-blue-400"
  def mechanic_type_color("spread"), do: "text-purple-400"
  def mechanic_type_color(_), do: "text-zinc-200"

  @doc "Get severity badge color classes"
  def severity_badge_color(:critical), do: "bg-red-900 text-red-300"
  def severity_badge_color(:high), do: "bg-orange-900 text-orange-300"
  def severity_badge_color(:medium), do: "bg-yellow-900 text-yellow-300"
  def severity_badge_color(:low), do: "bg-zinc-700 text-zinc-300"
  def severity_badge_color(_), do: "bg-zinc-700 text-zinc-300"

  @doc "Get a criteria from the spell lookup map"
  def get_criteria(criteria_by_spell, spell_id) when is_integer(spell_id) do
    case Map.get(criteria_by_spell, spell_id) do
      [criteria | _] -> criteria
      _ -> nil
    end
  end

  def get_criteria(_, _), do: nil

  @doc "Get the color class for a tracked criteria"
  def criteria_color(criteria_by_spell, spell_id) when is_integer(spell_id) do
    case get_criteria(criteria_by_spell, spell_id) do
      nil -> "text-zinc-200"
      criteria -> MechanicCriteria.type_color(criteria.mechanic_type)
    end
  end

  def criteria_color(_, _), do: "text-zinc-200"
end
