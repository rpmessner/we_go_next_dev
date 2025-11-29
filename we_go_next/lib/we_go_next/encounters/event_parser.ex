defmodule WeGoNext.Encounters.EventParser do
  @moduledoc """
  Parses raw combat log event data into normalized EncounterEvent attributes.

  WoW combat log events have a variable format depending on event type.
  This module handles the position-based field extraction for each event type
  and returns a normalized map suitable for insertion into the encounter_events table.

  ## Combat Log Format

  Events follow this general structure:
  - Position 0: Event type (e.g., "SPELL_DAMAGE")
  - Positions 1-8: Common prefix (source/target info)
  - Positions 9+: Event-specific data (varies by type)

  With advanced combat logging enabled (which we require), there's additional
  unit info between the prefix and suffix, shifting damage amounts to higher positions.
  """

  @doc """
  Parses a raw event map into normalized EncounterEvent attributes.

  Takes the event map from LogReader (%{timestamp, type, data}) and the
  encounter start time, returns a map of attributes for EncounterEvent.
  """
  def parse(event, encounter_start_time) do
    base = %{
      event_type: event.type,
      timestamp: to_utc_datetime(event.timestamp),
      time_into_fight: time_into_fight(encounter_start_time, event.timestamp)
    }

    case event.type do
      "SPELL_DAMAGE" -> parse_spell_damage(event.data, base)
      "SPELL_PERIODIC_DAMAGE" -> parse_spell_damage(event.data, base)
      "RANGE_DAMAGE" -> parse_spell_damage(event.data, base)
      "SWING_DAMAGE" -> parse_swing_damage(event.data, base)
      "ENVIRONMENTAL_DAMAGE" -> parse_environmental_damage(event.data, base)
      "SPELL_HEAL" -> parse_spell_heal(event.data, base)
      "SPELL_PERIODIC_HEAL" -> parse_spell_heal(event.data, base)
      "SPELL_AURA_APPLIED" -> parse_aura_event(event.data, base)
      "SPELL_AURA_REMOVED" -> parse_aura_event(event.data, base)
      "SPELL_AURA_APPLIED_DOSE" -> parse_aura_event(event.data, base)
      "SPELL_AURA_REMOVED_DOSE" -> parse_aura_event(event.data, base)
      "SPELL_INTERRUPT" -> parse_interrupt(event.data, base)
      "SPELL_CAST_START" -> parse_spell_cast(event.data, base)
      "SPELL_CAST_SUCCESS" -> parse_spell_cast(event.data, base)
      "SPELL_CAST_FAILED" -> parse_spell_cast(event.data, base)
      "UNIT_DIED" -> parse_unit_died(event.data, base)
      "COMBATANT_INFO" -> parse_combatant_info(event.data, base)
      _ -> parse_generic(event.data, base)
    end
  end

  # Common prefix extraction (positions 1-8)
  # Format: sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags
  defp extract_prefix(data) do
    %{
      source_guid: Enum.at(data, 1),
      source_name: Enum.at(data, 2),
      source_flags: parse_int(Enum.at(data, 3)),
      target_guid: Enum.at(data, 5),
      target_name: Enum.at(data, 6),
      target_flags: parse_int(Enum.at(data, 7))
    }
  end

  # Spell prefix extraction (positions 9-11)
  # Format: spellId, spellName, spellSchool
  defp extract_spell_prefix(data) do
    %{
      spell_id: parse_int(Enum.at(data, 9)),
      spell_name: Enum.at(data, 10),
      spell_school: parse_int(Enum.at(data, 11))
    }
  end

  # SPELL_DAMAGE, SPELL_PERIODIC_DAMAGE, RANGE_DAMAGE
  # With advanced logging: damage at index 31, overkill at 32
  defp parse_spell_damage(data, base) do
    prefix = extract_prefix(data)
    spell = extract_spell_prefix(data)
    {amount, overkill} = extract_damage_advanced(data, 31)

    Map.merge(base, prefix)
    |> Map.merge(spell)
    |> Map.merge(%{amount: amount, overkill: overkill})
  end

  # SWING_DAMAGE (melee)
  # No spell prefix, damage at index 28
  defp parse_swing_damage(data, base) do
    prefix = extract_prefix(data)
    {amount, overkill} = extract_damage_advanced(data, 28)

    Map.merge(base, prefix)
    |> Map.merge(%{
      spell_name: "Melee",
      spell_school: 1,  # Physical
      amount: amount,
      overkill: overkill
    })
  end

  # ENVIRONMENTAL_DAMAGE
  # Environment type at index 9, damage at index 29
  defp parse_environmental_damage(data, base) do
    prefix = extract_prefix(data)
    env_type = Enum.at(data, 9, "Environment")
    {amount, overkill} = extract_damage_advanced(data, 29)

    Map.merge(base, prefix)
    |> Map.merge(%{
      spell_name: "Environmental: #{env_type}",
      spell_school: 1,
      amount: amount,
      overkill: overkill
    })
  end

  # SPELL_HEAL, SPELL_PERIODIC_HEAL
  # Similar to damage but healing amount instead
  defp parse_spell_heal(data, base) do
    prefix = extract_prefix(data)
    spell = extract_spell_prefix(data)
    # Healing amount is at same position as damage
    amount = parse_int(Enum.at(data, 31))
    absorbed = parse_int(Enum.at(data, 34))

    Map.merge(base, prefix)
    |> Map.merge(spell)
    |> Map.merge(%{amount: amount, absorbed: absorbed})
  end

  # SPELL_AURA_APPLIED, SPELL_AURA_REMOVED, etc.
  # Aura type (BUFF/DEBUFF) is at position 12
  defp parse_aura_event(data, base) do
    prefix = extract_prefix(data)
    spell = extract_spell_prefix(data)
    aura_type = Enum.at(data, 12)  # "BUFF" or "DEBUFF"

    Map.merge(base, prefix)
    |> Map.merge(spell)
    |> Map.merge(%{extra: %{"aura_type" => aura_type}})
  end

  # SPELL_INTERRUPT
  # Spell prefix is the interrupt ability, extra spell is what was interrupted
  defp parse_interrupt(data, base) do
    prefix = extract_prefix(data)
    spell = extract_spell_prefix(data)

    # The interrupted spell is at positions 12-14
    extra = %{
      extra_spell_id: parse_int(Enum.at(data, 12)),
      extra_spell_name: Enum.at(data, 13)
    }

    Map.merge(base, prefix)
    |> Map.merge(spell)
    |> Map.merge(extra)
  end

  # SPELL_CAST_START, SPELL_CAST_SUCCESS, SPELL_CAST_FAILED
  defp parse_spell_cast(data, base) do
    prefix = extract_prefix(data)
    spell = extract_spell_prefix(data)

    Map.merge(base, prefix)
    |> Map.merge(spell)
  end

  # UNIT_DIED
  # The dead unit is in the "destination" fields
  defp parse_unit_died(data, base) do
    # For UNIT_DIED, positions 1-4 are recap info (usually nil/0)
    # The dead unit info starts at position 5
    %{
      target_guid: Enum.at(data, 5),
      target_name: Enum.at(data, 6),
      target_flags: parse_int(Enum.at(data, 7))
    }
    |> Map.merge(base)
  end

  # COMBATANT_INFO - player info at encounter start
  # Variable format with lots of data, store in extra
  defp parse_combatant_info(data, base) do
    alias WeGoNext.WowClass

    # Position 1 is the player GUID
    player_guid = Enum.at(data, 1)

    # Position 24 is the spec ID (e.g., 266 = Demonology Warlock)
    # Derive class_id from spec_id using WowClass mapping
    spec_id = parse_int(Enum.at(data, 24))
    class_id = WowClass.class_from_spec(spec_id)

    %{
      source_guid: player_guid,
      extra: %{
        "class_id" => class_id,
        "spec_id" => spec_id,
        "raw_data_length" => length(data)
      }
    }
    |> Map.merge(base)
  end

  # Generic fallback - just extract prefix
  defp parse_generic(data, base) do
    prefix = extract_prefix(data)
    Map.merge(base, prefix)
  end

  # Extract damage amount and overkill from advanced combat log format
  defp extract_damage_advanced(data, start_index) do
    amount = parse_int(Enum.at(data, start_index))
    overkill = parse_int(Enum.at(data, start_index + 1))
    # Overkill of -1 means no overkill
    overkill = if overkill == -1, do: 0, else: overkill
    {amount, overkill}
  end

  defp time_into_fight(start_time, event_time) do
    NaiveDateTime.diff(event_time, start_time, :millisecond) / 1000
  end

  defp to_utc_datetime(nil), do: nil
  defp to_utc_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp to_utc_datetime(%DateTime{} = dt), do: dt

  defp parse_int(nil), do: nil
  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> nil
    end
  end
end
