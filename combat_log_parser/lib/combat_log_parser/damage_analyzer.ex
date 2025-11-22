defmodule CombatLogParser.DamageAnalyzer do
  @moduledoc """
  Analyzes damage output from combat encounters.
  """

  alias CombatLogParser.Encounter

  @doc """
  Analyzes damage done by a specific player in an encounter.
  """
  def analyze(encounter, player_name) do
    damage_events = encounter.events
    |> Enum.reverse()  # Events are stored in reverse order
    |> Enum.filter(&damage_event?/1)
    |> Enum.filter(&is_source?(& 1, player_name))

    damage_by_ability = damage_events
    |> Enum.reduce(%{}, fn event, acc ->
      case extract_damage(event) do
        {ability_name, amount} ->
          Map.update(acc, ability_name, amount, &(&1 + amount))

        nil ->
          acc
      end
    end)

    total_damage = damage_by_ability
    |> Map.values()
    |> Enum.sum()

    fight_time_sec = Encounter.fight_time_sec(encounter)

    %{
      total_damage: total_damage,
      damage_events: length(damage_events),
      dps: if(fight_time_sec > 0, do: total_damage / fight_time_sec, else: 0),
      damage_by_ability: damage_by_ability,
      top_abilities: top_abilities(damage_by_ability, 10)
    }
  end

  # Check if event is a damage event
  defp damage_event?(%{type: type}) do
    String.contains?(type, "_DAMAGE")
  end

  # Check if the source of the event matches the player name
  defp is_source?(%{data: data}, player_name) do
    # Source GUID is at index 1, source name at index 2
    Enum.at(data, 2, "") |> String.contains?(player_name)
  end

  # Extract damage amount and ability name from event
  # With advanced combat logging enabled, damage position varies
  # We search for the damage amount in the suffix
  defp extract_damage(%{type: type, data: data}) do
    cond do
      type == "SWING_DAMAGE" ->
        # For SWING, search after position 8 (after dest raid flags)
        amount = find_damage_amount(data, 9)
        {"Auto Attack", amount}

      String.starts_with?(type, "SPELL_") or String.starts_with?(type, "RANGE_") ->
        # For SPELL, get ability name at index 10, then search for damage
        ability_name = Enum.at(data, 10, "Unknown")
        # Search after spell school (index 11) for damage amount
        amount = find_damage_amount(data, 12)
        {ability_name, amount}

      true ->
        nil
    end
  end

  # Find damage amount by looking from the END of the data array
  # The suffix format is consistent: ...amount, overkill, school, resisted, blocked, absorbed, critical...
  # With advanced logging, damage amount is typically 7-10 positions from the end
  defp find_damage_amount(data, _start_index) do
    # Get the last ~15 fields (to cover the damage suffix)
    suffix = Enum.take(data, -15)

    # Look for a numeric value that:
    # 1. Is positive and reasonable for damage (1 to 50M)
    # 2. Is followed by either another number or -1 (the pattern for damage,overkill,school)
    suffix
    |> Enum.with_index()
    |> Enum.find_value(0, fn {field, idx} ->
      value = parse_int(field)
      # Check if this could be damage (positive, reasonable range)
      # and is followed by a numeric value (overkill) or -1 (school)
      if value > 0 and value < 50_000_000 do
        next_field = Enum.at(suffix, idx + 1, "")
        # If next field is numeric or -1, this is likely damage
        if next_field == "-1" or (parse_int(next_field) >= 0 and next_field != "0x0") do
          value
        end
      end
    end)
  end

  defp parse_int(nil), do: 0
  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> 0
    end
  end

  defp top_abilities(damage_by_ability, limit) do
    damage_by_ability
    |> Enum.sort_by(fn {_ability, damage} -> damage end, :desc)
    |> Enum.take(limit)
  end
end
