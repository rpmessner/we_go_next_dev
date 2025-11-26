defmodule CombatLogParser.Analyzers.DeathAnalyzer do
  @moduledoc """
  Analyzes deaths in combat encounters.

  Tracks damage taken by each player and builds a "death recap" showing
  the last several damage events before death, including the killing blow.
  """

  alias CombatLogParser.Encounter

  @recap_window_size 10  # Number of damage events to keep per player

  defmodule Death do
    @moduledoc "Represents a player death with context"
    defstruct [
      :player_name,
      :player_guid,
      :timestamp,
      :time_into_fight,     # seconds into encounter
      :killing_blow,        # %{ability: "", source: "", amount: 0, overkill: 0}
      :recap                # list of recent damage events
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
    # Events are stored in reverse order, so reverse them for chronological processing
    events = Enum.reverse(encounter.events)

    # Process events, tracking damage per player and collecting deaths
    {deaths, _damage_windows} =
      Enum.reduce(events, {[], %{}}, fn event, {deaths, damage_windows} ->
        process_event(event, encounter, deaths, damage_windows)
      end)

    # Return deaths in chronological order
    Enum.reverse(deaths)
  end

  # Process a single event
  defp process_event(%{type: "UNIT_DIED"} = event, encounter, deaths, damage_windows) do
    case parse_unit_died(event) do
      {:ok, player_name, player_guid} ->
        if is_player_guid?(player_guid) do
          # Get the damage window for this player
          recap = Map.get(damage_windows, player_guid, [])

          # Build the death record
          death = %Death{
            player_name: player_name,
            player_guid: player_guid,
            timestamp: event.timestamp,
            time_into_fight: time_into_fight(encounter.start_time, event.timestamp),
            killing_blow: find_killing_blow(recap),
            recap: Enum.take(recap, @recap_window_size)
          }

          # Clear this player's damage window (they're dead)
          {[death | deaths], Map.delete(damage_windows, player_guid)}
        else
          {deaths, damage_windows}
        end

      _ ->
        {deaths, damage_windows}
    end
  end

  defp process_event(%{type: type} = event, _encounter, deaths, damage_windows)
       when type in ["SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE", "SWING_DAMAGE", "RANGE_DAMAGE", "ENVIRONMENTAL_DAMAGE"] do
    case parse_damage_event(event) do
      {:ok, damage_event, target_guid} ->
        if is_player_guid?(target_guid) do
          # Add to this player's damage window
          updated_windows = Map.update(damage_windows, target_guid, [damage_event], fn existing ->
            [damage_event | existing] |> Enum.take(@recap_window_size)
          end)

          {deaths, updated_windows}
        else
          {deaths, damage_windows}
        end

      _ ->
        {deaths, damage_windows}
    end
  end

  defp process_event(_event, _encounter, deaths, damage_windows) do
    {deaths, damage_windows}
  end

  # Parse UNIT_DIED event
  # Format: UNIT_DIED,recapID,nil,recapFlags,recapRaidFlags,destGUID,destName,destFlags,destRaidFlags,unconsciousOnDeath
  # The destination (dead unit) info starts at index 5
  defp parse_unit_died(%{data: data}) do
    # data[0] is "UNIT_DIED"
    # data[1-4] is recap info (zeroes/nil)
    # data[5] is destGUID, data[6] is destName
    dest_guid = Enum.at(data, 5)
    dest_name = Enum.at(data, 6)

    if dest_guid && dest_name do
      {:ok, dest_name, dest_guid}
    else
      :error
    end
  end

  # Parse damage events
  # Prefix (all damage): sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags
  # SPELL_ suffix: spellId, spellName, spellSchool, amount, overkill, school, ...
  # SWING_DAMAGE suffix: amount, overkill, school, ...
  defp parse_damage_event(%{type: "SWING_DAMAGE", timestamp: timestamp, data: data}) do
    # Swing damage has no spell info
    source_name = Enum.at(data, 2)
    target_guid = Enum.at(data, 5)
    _target_name = Enum.at(data, 6)

    # With advanced combat logging, damage is after unit info
    # SWING_DAMAGE has no spell prefix (3 fields), so damage is at index 28
    {amount, overkill} = extract_damage_suffix_advanced(data, 28)

    damage_event = %DamageEvent{
      timestamp: timestamp,
      ability_name: "Melee",
      ability_id: nil,
      source_name: source_name,
      amount: amount,
      overkill: overkill,
      school: 1  # Physical
    }

    {:ok, damage_event, target_guid}
  end

  defp parse_damage_event(%{type: type, timestamp: timestamp, data: data})
       when type in ["SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE", "RANGE_DAMAGE"] do
    source_name = Enum.at(data, 2)
    target_guid = Enum.at(data, 5)
    _target_name = Enum.at(data, 6)

    # Spell info after prefix (indices 9, 10, 11 for id, name, school)
    spell_id = Enum.at(data, 9) |> parse_int()
    spell_name = Enum.at(data, 10, "Unknown")
    spell_school = Enum.at(data, 11) |> parse_int()

    # With advanced combat logging, there's unit info between spell and damage
    # Damage starts at index 31 (0-indexed: amount at 31, overkill at 32)
    # Without advanced logging, damage would be at index 12
    {amount, overkill} = extract_damage_suffix_advanced(data)

    damage_event = %DamageEvent{
      timestamp: timestamp,
      ability_name: spell_name,
      ability_id: spell_id,
      source_name: source_name,
      amount: amount,
      overkill: overkill,
      school: spell_school
    }

    {:ok, damage_event, target_guid}
  end

  defp parse_damage_event(%{type: "ENVIRONMENTAL_DAMAGE", timestamp: timestamp, data: data}) do
    target_guid = Enum.at(data, 5)
    env_type = Enum.at(data, 9, "Environment")

    # With advanced logging, damage is after unit info (index 29 for env damage)
    {amount, overkill} = extract_damage_suffix_advanced(data, 29)

    damage_event = %DamageEvent{
      timestamp: timestamp,
      ability_name: "Environmental: #{env_type}",
      ability_id: nil,
      source_name: "Environment",
      amount: amount,
      overkill: overkill,
      school: 1
    }

    {:ok, damage_event, target_guid}
  end

  defp parse_damage_event(_), do: :error

  # Extract damage amount and overkill with advanced combat logging
  # For SPELL_DAMAGE: damage at index 31, overkill at 32
  # For SWING_DAMAGE: damage at index 28, overkill at 29
  defp extract_damage_suffix_advanced(data, start_index \\ 31) do
    amount = Enum.at(data, start_index) |> parse_int()
    overkill = Enum.at(data, start_index + 1) |> parse_int()

    # Overkill of -1 means no overkill
    overkill = if overkill == -1, do: 0, else: overkill

    {amount, overkill}
  end

  # Check if GUID is a player (starts with "Player-")
  defp is_player_guid?(guid) when is_binary(guid) do
    String.starts_with?(guid, "Player-")
  end
  defp is_player_guid?(_), do: false

  # Calculate time into fight in seconds
  defp time_into_fight(start_time, event_time) do
    NaiveDateTime.diff(event_time, start_time, :millisecond) / 1000
  end

  # Find the killing blow (most recent damage event with overkill > 0, or just most recent)
  defp find_killing_blow([]), do: nil
  defp find_killing_blow(recap) do
    # The killing blow is typically the most recent damage event
    # If it has overkill > 0, that confirms it
    case List.first(recap) do
      %DamageEvent{} = event ->
        %{
          ability: event.ability_name,
          source: event.source_name,
          amount: event.amount,
          overkill: event.overkill
        }
      _ ->
        nil
    end
  end

  defp parse_int(nil), do: 0
  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> 0
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
  defp format_killing_blow(%{ability: ability, source: source, amount: _amount, overkill: overkill}) do
    overkill_str = if overkill > 0, do: " (#{format_number(overkill)} overkill)", else: ""
    "died to [#{ability}] from #{source}#{overkill_str}"
  end

  defp format_recap([]), do: "         No damage recap available"
  defp format_recap(recap) do
    recap
    |> Enum.take(5)
    |> Enum.map(fn %DamageEvent{ability_name: ability, amount: amount, source_name: source} ->
      "           #{ability} (#{format_number(amount)}) - #{source}"
    end)
    |> Enum.join("\n")
    |> then(&("         Recap:\n" <> &1))
  end

  defp format_number(num) when is_integer(num) and num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end
  defp format_number(num) when is_integer(num) and num >= 1000 do
    "#{Float.round(num / 1000, 0) |> trunc()}k"
  end
  defp format_number(num), do: to_string(num)
end
