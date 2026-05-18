defmodule WeGoNext.Analyzers.DeathAnalyzer do
  @moduledoc """
  Analyzes deaths in combat encounters.

  Tracks damage taken by each player and builds a "death recap" showing
  the last several damage events before death, including the killing blow.
  """

  alias WeGoNext.Encounter

  # Number of damage events to keep per player
  @recap_window_size 10

  defmodule Death do
    @moduledoc "Represents a player death with context"
    defstruct [
      :player_name,
      :player_guid,
      :timestamp,
      # seconds into encounter
      :time_into_fight,
      # %{ability: "", source: "", amount: 0, overkill: 0}
      :killing_blow,
      # list of recent damage events
      :recap
    ]
  end

  defmodule DamageEvent do
    @moduledoc "A single damage event for death recap"
    defstruct [
      :timestamp,
      :ability_name,
      :ability_id,
      :source_name,
      :amount,
      :overkill,
      :school
    ]
  end

  @doc """
  Analyzes an encounter and returns all player deaths with recaps.

  Returns a list of %Death{} structs.
  """
  def analyze(%Encounter{} = encounter) do
    # Events are now loaded from DB in chronological order
    events = encounter.events

    # Process events, tracking damage per player and collecting deaths
    {deaths, _damage_windows} =
      Enum.reduce(events, {[], %{}}, fn event, {deaths, damage_windows} ->
        process_event(event, deaths, damage_windows)
      end)

    # Return deaths in chronological order
    Enum.reverse(deaths)
  end

  # Process a single event - now using normalized event fields
  defp process_event(%{type: "UNIT_DIED"} = event, deaths, damage_windows) do
    player_guid = event.target_guid
    player_name = event.target_name

    if player_guid?(player_guid) do
      # Get the damage window for this player
      recap = Map.get(damage_windows, player_guid, [])

      # Build the death record
      death = %Death{
        player_name: player_name,
        player_guid: player_guid,
        timestamp: event.timestamp,
        time_into_fight: event.time_into_fight,
        killing_blow: find_killing_blow(recap),
        recap: Enum.take(recap, @recap_window_size)
      }

      # Clear this player's damage window (they're dead)
      {[death | deaths], Map.delete(damage_windows, player_guid)}
    else
      {deaths, damage_windows}
    end
  end

  defp process_event(%{type: type} = event, deaths, damage_windows)
       when type in [
              "SPELL_DAMAGE",
              "SPELL_PERIODIC_DAMAGE",
              "SWING_DAMAGE",
              "RANGE_DAMAGE",
              "ENVIRONMENTAL_DAMAGE"
            ] do
    target_guid = event.target_guid

    if player_guid?(target_guid) do
      # Create damage event from normalized fields
      damage_event = %DamageEvent{
        timestamp: event.timestamp,
        ability_name: event.spell_name || "Melee",
        ability_id: event.spell_id,
        source_name: event.source_name,
        amount: event.amount || 0,
        overkill: normalize_overkill(event.overkill),
        school: event.spell_school || 1
      }

      # Add to this player's damage window
      updated_windows =
        Map.update(damage_windows, target_guid, [damage_event], fn existing ->
          [damage_event | existing] |> Enum.take(@recap_window_size)
        end)

      {deaths, updated_windows}
    else
      {deaths, damage_windows}
    end
  end

  defp process_event(_event, deaths, damage_windows) do
    {deaths, damage_windows}
  end

  # Normalize overkill value (-1 means no overkill)
  defp normalize_overkill(nil), do: 0
  defp normalize_overkill(-1), do: 0
  defp normalize_overkill(val), do: val

  # Check if GUID is a player (starts with "Player-")
  defp player_guid?(guid) when is_binary(guid) do
    String.starts_with?(guid, "Player-")
  end

  defp player_guid?(_), do: false

  # Find the killing blow (most recent damage event with overkill > 0, or just most recent)
  defp find_killing_blow([]), do: nil

  defp find_killing_blow(recap) do
    # The killing blow is typically the most recent damage event
    # If it has overkill > 0, that confirms it
    case List.first(recap) do
      %DamageEvent{} = event ->
        %{
          ability: event.ability_name,
          ability_id: event.ability_id,
          source: event.source_name,
          amount: event.amount,
          overkill: event.overkill
        }

      _ ->
        nil
    end
  end

  @doc """
  Formats deaths for display.
  """
  def format_deaths(deaths) do
    if Enum.empty?(deaths) do
      "  No deaths"
    else
      deaths
      |> Enum.map(&format_death/1)
      |> Enum.join("\n")
    end
  end

  defp format_death(%Death{} = death) do
    time = format_time(death.time_into_fight)
    killing_blow = format_killing_blow(death.killing_blow)
    recap = format_recap(death.recap)

    """
      #{time} - #{death.player_name} #{killing_blow}
    #{recap}
    """
    |> String.trim_trailing()
  end

  defp format_time(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_killing_blow(nil), do: "died (unknown cause)"

  defp format_killing_blow(%{
         ability: ability,
         source: source,
         amount: _amount,
         overkill: overkill
       }) do
    overkill_str = if overkill > 0, do: " (#{format_number(overkill)} overkill)", else: ""
    "died to [#{ability}] from #{source}#{overkill_str}"
  end

  defp format_recap([]), do: "         No damage recap available"

  defp format_recap(recap) do
    lines =
      recap
      |> Enum.take(5)
      |> Enum.map_join("\n", fn %DamageEvent{
                                  ability_name: ability,
                                  amount: amount,
                                  source_name: source
                                } ->
        "           #{ability} (#{format_number(amount)}) - #{source}"
      end)

    "         Recap:\n" <> lines
  end

  defp format_number(num) when is_integer(num) and num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  defp format_number(num) when is_integer(num) and num >= 1000 do
    "#{Float.round(num / 1000, 0) |> trunc()}k"
  end

  defp format_number(num), do: to_string(num)
end
