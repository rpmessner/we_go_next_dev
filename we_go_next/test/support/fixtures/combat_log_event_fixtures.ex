defmodule WeGoNext.Fixtures.CombatLogEventFixtures do
  @moduledoc """
  Builders for normalized combat-log event maps used by silver/gold tests.
  """

  def canonical_projection_events do
    [
      combatant_info_event(
        source_guid: "Player-Dps",
        time_into_fight: 0.1,
        extra: %{spec_id: 71}
      ),
      swing_damage_event(
        time_into_fight: 1.0,
        source_guid: "Creature-Boss",
        source_name: "Boss",
        target_guid: "Player-Tank",
        target_name: "Tank-Realm",
        amount: 5_000
      ),
      swing_damage_event(
        time_into_fight: 1.5,
        source_guid: "Creature-Boss",
        source_name: "Boss",
        target_guid: "Player-Tank",
        target_name: "Tank-Realm",
        amount: 4_000
      ),
      spell_damage_event(
        time_into_fight: 2.0,
        source_guid: "Creature-Boss",
        source_name: "Boss",
        target_guid: "Player-Victim",
        target_name: "Victim-Realm",
        spell_id: 123,
        spell_name: "Bad",
        amount: 300
      ),
      spell_damage_event(
        time_into_fight: 2.5,
        source_guid: "Creature-Boss",
        source_name: "Boss",
        target_guid: "Player-Victim",
        target_name: "Victim-Realm",
        spell_id: 123,
        spell_name: "Bad",
        amount: 400,
        overkill: 50
      ),
      unit_died_event(
        time_into_fight: 3.0,
        target_guid: "Player-Victim",
        target_name: "Victim-Realm"
      ),
      spell_damage_event(
        time_into_fight: 3.5,
        source_guid: "Player-Dps",
        source_name: "Dps-Realm",
        target_guid: "Creature-Boss",
        target_name: "Boss",
        spell_id: 456,
        spell_name: "Nuke",
        amount: 1_000
      ),
      spell_damage_event(
        time_into_fight: 3.7,
        source_guid: "Player-Dps",
        source_name: "Dps-Realm",
        target_guid: "Creature-Boss",
        target_name: "Boss",
        spell_id: 456,
        spell_name: "Nuke",
        amount: 1_500
      ),
      spell_interrupt_event(
        time_into_fight: 4.0,
        source_guid: "Player-Dps",
        source_name: "Dps-Realm",
        target_guid: "Creature-Caster",
        target_name: "Caster",
        spell_id: 1766,
        spell_name: "Kick",
        extra_spell_id: 1_249_017,
        extra_spell_name: "Fearsome Cry"
      ),
      spell_cast_success_event(
        type: "SPELL_CAST_START",
        time_into_fight: 4.5,
        source_guid: "Creature-Caster",
        source_name: "Caster",
        target_guid: "Player-Dps",
        target_name: "Dps-Realm",
        spell_id: 1_249_017,
        spell_name: "Fearsome Cry"
      ),
      spell_cast_success_event(
        time_into_fight: 5.0,
        source_guid: "Creature-Caster",
        source_name: "Caster",
        target_guid: "Player-Dps",
        target_name: "Dps-Realm",
        spell_id: 1_249_017,
        spell_name: "Fearsome Cry"
      ),
      debuff_applied_event(
        time_into_fight: 6.0,
        source_guid: "Creature-Boss",
        source_name: "Boss",
        target_guid: "Player-Dps",
        target_name: "Dps-Realm",
        spell_id: 999,
        spell_name: "Debuff"
      ),
      debuff_removed_event(
        time_into_fight: 8.5,
        source_guid: "Creature-Boss",
        source_name: "Boss",
        target_guid: "Player-Dps",
        target_name: "Dps-Realm",
        spell_id: 999,
        spell_name: "Debuff"
      ),
      debuff_applied_event(
        time_into_fight: 9.0,
        source_guid: "Creature-Boss",
        source_name: "Boss",
        target_guid: "Player-Victim",
        target_name: "Victim-Realm",
        spell_id: 111,
        spell_name: "Lingering Debuff"
      ),
      buff_applied_event(
        time_into_fight: 1.8,
        source_guid: "Player-Victim",
        source_name: "Victim-Realm",
        target_guid: "Player-Victim",
        target_name: "Victim-Realm",
        spell_id: 104_773,
        spell_name: "Unending Resolve"
      ),
      buff_removed_event(
        time_into_fight: 4.2,
        source_guid: "Player-Victim",
        source_name: "Victim-Realm",
        target_guid: "Player-Victim",
        target_name: "Victim-Realm",
        spell_id: 104_773,
        spell_name: "Unending Resolve"
      )
    ]
  end

  def combatant_info_event(attrs \\ []) do
    build_event(
      %{
        type: "COMBATANT_INFO",
        time_into_fight: 0.0,
        source_guid: "Player-1",
        extra: %{}
      },
      attrs
    )
  end

  def swing_damage_event(attrs \\ []) do
    build_event(
      %{
        type: "SWING_DAMAGE",
        timestamp: timestamp(attrs[:time_into_fight] || 0.0),
        time_into_fight: 0.0,
        source_guid: "Creature-1",
        source_name: "Creature",
        target_guid: "Player-1",
        target_name: "Player-Realm",
        spell_id: 0,
        spell_name: "Melee",
        spell_school: 1,
        amount: 0,
        overkill: 0
      },
      attrs
    )
  end

  def spell_damage_event(attrs \\ []) do
    build_event(
      %{
        type: "SPELL_DAMAGE",
        timestamp: timestamp(attrs[:time_into_fight] || 0.0),
        time_into_fight: 0.0,
        source_guid: "Creature-1",
        source_name: "Creature",
        target_guid: "Player-1",
        target_name: "Player-Realm",
        spell_id: 1,
        spell_name: "Spell",
        spell_school: 1,
        amount: 0,
        overkill: 0
      },
      attrs
    )
  end

  def unit_died_event(attrs \\ []) do
    build_event(
      %{
        type: "UNIT_DIED",
        timestamp: timestamp(attrs[:time_into_fight] || 0.0),
        time_into_fight: 0.0,
        source_guid: "0000000000000000",
        source_name: nil,
        target_guid: "Player-1",
        target_name: "Player-Realm"
      },
      attrs
    )
  end

  def spell_interrupt_event(attrs \\ []) do
    build_event(
      %{
        type: "SPELL_INTERRUPT",
        timestamp: timestamp(attrs[:time_into_fight] || 0.0),
        time_into_fight: 0.0,
        source_guid: "Player-1",
        source_name: "Player-Realm",
        target_guid: "Creature-1",
        target_name: "Creature",
        spell_id: 1766,
        spell_name: "Interrupt",
        extra_spell_id: 1,
        extra_spell_name: "Interrupted Spell"
      },
      attrs
    )
  end

  def spell_cast_success_event(attrs \\ []) do
    build_event(
      %{
        type: "SPELL_CAST_SUCCESS",
        timestamp: timestamp(attrs[:time_into_fight] || 0.0),
        time_into_fight: 0.0,
        source_guid: "Creature-1",
        source_name: "Creature",
        target_guid: "Player-1",
        target_name: "Player-Realm",
        spell_id: 1,
        spell_name: "Completed Cast"
      },
      attrs
    )
  end

  def debuff_applied_event(attrs \\ []) do
    build_event(
      %{
        type: "SPELL_AURA_APPLIED",
        timestamp: timestamp(attrs[:time_into_fight] || 0.0),
        time_into_fight: 0.0,
        source_guid: "Creature-1",
        source_name: "Creature",
        target_guid: "Player-1",
        target_name: "Player-Realm",
        spell_id: 1,
        spell_name: "Debuff",
        extra: %{aura_type: "DEBUFF"}
      },
      attrs
    )
  end

  def debuff_removed_event(attrs \\ []) do
    build_event(
      %{
        type: "SPELL_AURA_REMOVED",
        timestamp: timestamp(attrs[:time_into_fight] || 0.0),
        time_into_fight: 0.0,
        source_guid: "Creature-1",
        source_name: "Creature",
        target_guid: "Player-1",
        target_name: "Player-Realm",
        spell_id: 1,
        spell_name: "Debuff",
        extra: %{aura_type: "DEBUFF"}
      },
      attrs
    )
  end

  def buff_applied_event(attrs \\ []) do
    build_event(
      %{
        type: "SPELL_AURA_APPLIED",
        timestamp: timestamp(attrs[:time_into_fight] || 0.0),
        time_into_fight: 0.0,
        source_guid: "Player-1",
        source_name: "Player-Realm",
        target_guid: "Player-1",
        target_name: "Player-Realm",
        spell_id: 104_773,
        spell_name: "Unending Resolve",
        extra: %{aura_type: "BUFF"}
      },
      attrs
    )
  end

  def buff_removed_event(attrs \\ []) do
    build_event(
      %{
        type: "SPELL_AURA_REMOVED",
        timestamp: timestamp(attrs[:time_into_fight] || 0.0),
        time_into_fight: 0.0,
        source_guid: "Player-1",
        source_name: "Player-Realm",
        target_guid: "Player-1",
        target_name: "Player-Realm",
        spell_id: 104_773,
        spell_name: "Unending Resolve",
        extra: %{aura_type: "BUFF"}
      },
      attrs
    )
  end

  defp build_event(defaults, attrs) do
    attrs = Map.new(attrs)

    defaults
    |> Map.merge(attrs)
    |> maybe_refresh_timestamp(attrs)
  end

  defp maybe_refresh_timestamp(event, %{timestamp: _timestamp}), do: event

  defp maybe_refresh_timestamp(%{time_into_fight: seconds} = event, _attrs),
    do: Map.put(event, :timestamp, timestamp(seconds))

  defp maybe_refresh_timestamp(event, _attrs), do: event

  defp timestamp(seconds) when is_number(seconds) do
    milliseconds = seconds |> Kernel.*(1000) |> round()
    whole_seconds = div(milliseconds, 1000)
    ms = rem(milliseconds, 1000)

    "1/1/2026 00:00:#{String.pad_leading(to_string(whole_seconds), 2, "0")}.#{String.pad_leading(to_string(ms), 3, "0")}-0"
  end
end
