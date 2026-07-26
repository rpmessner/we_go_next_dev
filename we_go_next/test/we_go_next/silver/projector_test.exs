defmodule WeGoNext.Silver.ProjectorTest do
  use ExUnit.Case, async: true

  alias WeGoNext.Fixtures.CombatLogEventFixtures
  alias WeGoNext.Silver.{Projection, Projector}

  @encounter_dim_id 42

  test "projects normalized events into canonical silver row grains" do
    projection =
      Projector.project(@encounter_dim_id, CombatLogEventFixtures.canonical_projection_events())

    assert %Projection{} = projection

    assert [
             %{
               encounter_dim_id: @encounter_dim_id,
               target_guid: "Player-Tank",
               source_guid: "Creature-Boss",
               spell_id: 0,
               total_amount: 9_000,
               hit_count: 2,
               max_hit: 5_000,
               overkill_total: 0,
               source_is_npc: true
             },
             %{
               encounter_dim_id: @encounter_dim_id,
               target_guid: "Player-Victim",
               source_guid: "Creature-Boss",
               spell_id: 123,
               total_amount: 700,
               hit_count: 2,
               max_hit: 400,
               overkill_total: 50,
               source_is_npc: true
             }
           ] = projection.damage_taken

    assert [
             %{
               encounter_dim_id: @encounter_dim_id,
               combat_log_event_index: 1,
               event_type: "SWING_DAMAGE",
               occurred_at_ms_into_fight: 1_000,
               target_guid: "Player-Tank",
               target_name: "Tank",
               source_guid: "Creature-Boss",
               source_name: "Boss",
               source_is_npc: true,
               spell_id: 0,
               spell_name: "Melee",
               spell_school: 1,
               amount: 5_000,
               overkill: 0
             },
             %{
               combat_log_event_index: 2,
               event_type: "SWING_DAMAGE",
               occurred_at_ms_into_fight: 1_500,
               target_guid: "Player-Tank",
               source_guid: "Creature-Boss",
               spell_id: 0,
               amount: 4_000
             },
             %{
               combat_log_event_index: 3,
               event_type: "SPELL_DAMAGE",
               occurred_at_ms_into_fight: 2_000,
               target_guid: "Player-Victim",
               source_guid: "Creature-Boss",
               spell_id: 123,
               spell_name: "Bad",
               amount: 300,
               overkill: 0
             },
             %{
               combat_log_event_index: 4,
               event_type: "SPELL_DAMAGE",
               occurred_at_ms_into_fight: 2_500,
               target_guid: "Player-Victim",
               source_guid: "Creature-Boss",
               spell_id: 123,
               amount: 400,
               overkill: 50
             }
           ] = projection.damage_taken_event

    assert [
             %{
               encounter_dim_id: @encounter_dim_id,
               source_guid: "Player-Dps",
               target_guid: "Creature-Boss",
               spell_id: 456,
               total_amount: 2_500,
               hit_count: 2,
               max_hit: 1_500
             },
             %{
               encounter_dim_id: @encounter_dim_id,
               source_guid: "Player-Dps",
               target_guid: "Vehicle-Boss",
               spell_id: 789,
               total_amount: 10_000,
               hit_count: 1,
               max_hit: 10_000
             }
           ] = projection.damage_done

    assert [
             %{
               encounter_dim_id: @encounter_dim_id,
               target_guid: "Player-Victim",
               died_at_ms_into_fight: 3_000,
               killing_blow_spell_id: 123,
               killing_blow_source_guid: "Creature-Boss",
               damage_recap: [
                 %{
                   "ms_into_fight" => 2_500,
                   "spell_id" => 123,
                   "spell_name" => "Bad",
                   "source_guid" => "Creature-Boss",
                   "amount" => 400,
                   "overkill" => 50
                 },
                 %{
                   "ms_into_fight" => 2_000,
                   "spell_id" => 123,
                   "spell_name" => "Bad",
                   "source_guid" => "Creature-Boss",
                   "amount" => 300,
                   "overkill" => 0
                 }
               ]
             }
           ] = projection.death

    assert [
             %{
               encounter_dim_id: @encounter_dim_id,
               target_npc_guid: "Creature-Caster",
               interrupted_spell_id: 1_249_017,
               opportunity_ms_into_fight: 4_000,
               success: true,
               interrupter_guid: "Player-Dps",
               interrupting_spell_id: 1766
             },
             %{
               encounter_dim_id: @encounter_dim_id,
               target_npc_guid: "Creature-Caster",
               interrupted_spell_id: 1_249_017,
               opportunity_ms_into_fight: 5_000,
               success: false,
               interrupter_guid: nil,
               interrupting_spell_id: nil
             }
           ] = projection.interrupt_opportunity

    assert [
             %{
               encounter_dim_id: @encounter_dim_id,
               target_guid: "Player-Dps",
               source_guid: "Creature-Boss",
               spell_id: 999,
               applied_at_ms_into_fight: 6_000,
               duration_ms: 2_500,
               stack_count: 1
             },
             %{
               encounter_dim_id: @encounter_dim_id,
               target_guid: "Player-Victim",
               source_guid: "Creature-Boss",
               spell_id: 111,
               applied_at_ms_into_fight: 9_000,
               duration_ms: nil,
               stack_count: 1
             }
           ] = projection.debuff_application

    assert [
             %{
               encounter_dim_id: @encounter_dim_id,
               target_guid: "Player-Victim",
               source_guid: "Player-Victim",
               spell_id: 104_773,
               spell_name: "Unending Resolve",
               category: "personal",
               started_at_ms_into_fight: 1_800,
               ended_at_ms_into_fight: 4_200,
               duration_ms: 2_400
             }
           ] = projection.defensive_buff_window

    assert projection.survival_action == []

    assert [
             %{
               encounter_dim_id: @encounter_dim_id,
               player_guid: "Player-Dps",
               player_name: "Dps",
               class_id: 1,
               spec_id: 71,
               item_level: nil,
               detected_role: "dps"
             },
             %{
               encounter_dim_id: @encounter_dim_id,
               player_guid: "Player-Tank",
               player_name: "Tank",
               class_id: nil,
               spec_id: nil,
               item_level: nil,
               detected_role: "tank"
             },
             %{
               encounter_dim_id: @encounter_dim_id,
               player_guid: "Player-Victim",
               player_name: "Victim",
               class_id: nil,
               spec_id: nil,
               item_level: nil,
               detected_role: "unknown"
             }
           ] = projection.player_info
  end

  test "missed interrupt rows require a known interruptible cast window" do
    projection =
      Projector.project(@encounter_dim_id, [
        CombatLogEventFixtures.spell_cast_success_event(
          type: "SPELL_CAST_START",
          time_into_fight: 1.0,
          source_guid: "Creature-Caster",
          spell_id: 1_249_017,
          spell_name: "Fearsome Cry"
        ),
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 2.0,
          source_guid: "Creature-Caster",
          spell_id: 1_249_017,
          spell_name: "Fearsome Cry"
        ),
        CombatLogEventFixtures.spell_cast_success_event(
          type: "SPELL_CAST_START",
          time_into_fight: 3.0,
          source_guid: "Creature-Caster",
          spell_id: 9_999_999,
          spell_name: "Ambient Boss Cast"
        ),
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 4.0,
          source_guid: "Creature-Caster",
          spell_id: 9_999_999,
          spell_name: "Ambient Boss Cast"
        ),
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 5.0,
          source_guid: "Creature-Caster",
          spell_id: 1_249_017,
          spell_name: "Fearsome Cry"
        )
      ])

    assert [
             %{
               interrupted_spell_id: 1_249_017,
               opportunity_ms_into_fight: 2_000,
               success: false
             }
           ] = projection.interrupt_opportunity
  end

  test "missed interrupt rows ignore player-controlled creature casts" do
    projection =
      Projector.project(@encounter_dim_id, [
        CombatLogEventFixtures.spell_cast_success_event(
          type: "SPELL_CAST_START",
          time_into_fight: 1.0,
          source_guid: "Creature-WildImp",
          source_flags: 0x2114,
          spell_id: 1_249_017,
          spell_name: "Fearsome Cry"
        ),
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 2.0,
          source_guid: "Creature-WildImp",
          source_flags: 0x2114,
          spell_id: 1_249_017,
          spell_name: "Fearsome Cry"
        )
      ])

    assert projection.interrupt_opportunity == []
  end

  test "projects catalog survival casts target-aware with consumable heal joins" do
    projection =
      Projector.project(@encounter_dim_id, [
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 1.0,
          source_guid: "Player-Warlock",
          source_name: "Warlock-Realm",
          target_guid: "0000000000000000",
          target_name: nil,
          spell_id: 104_773,
          spell_name: "Unending Resolve"
        ),
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 2.0,
          source_guid: "Player-Priest",
          source_name: "Priest-Realm",
          target_guid: "Player-Warlock",
          target_name: "Warlock-Realm",
          spell_id: 33_206,
          spell_name: "Pain Suppression"
        ),
        # Real 12.0 logs can stamp the consumable heal 1ms before its cast.
        CombatLogEventFixtures.spell_heal_event(
          time_into_fight: 5.0,
          source_guid: "Player-Warlock",
          source_name: "Warlock-Realm",
          target_guid: "Player-Warlock",
          spell_id: 6262,
          spell_name: "Healthstone",
          amount: 118_155,
          overhealing: 0
        ),
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 5.001,
          source_guid: "Player-Warlock",
          source_name: "Warlock-Realm",
          target_guid: "0000000000000000",
          target_name: nil,
          spell_id: 6262,
          spell_name: "Healthstone"
        ),
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 8.0,
          source_guid: "Player-Mage",
          source_name: "Mage-Realm",
          target_guid: "0000000000000000",
          target_name: nil,
          spell_id: 1_234_768,
          spell_name: "Silvermoon Health Potion"
        ),
        CombatLogEventFixtures.spell_heal_event(
          time_into_fight: 8.2,
          source_guid: "Player-Mage",
          source_name: "Mage-Realm",
          target_guid: "Player-Mage",
          spell_id: 1_234_768,
          spell_name: "Silvermoon Health Potion",
          amount: 316_404,
          overhealing: 242_443
        )
      ])

    assert [
             %{
               encounter_dim_id: @encounter_dim_id,
               caster_guid: "Player-Warlock",
               target_guid: "Player-Warlock",
               spell_id: 104_773,
               spell_name: "Unending Resolve",
               kind: "defensive",
               category: "personal",
               used_at_ms_into_fight: 1_000,
               heal_amount: nil,
               overheal_amount: nil
             },
             %{
               caster_guid: "Player-Priest",
               target_guid: "Player-Warlock",
               spell_id: 33_206,
               spell_name: "Pain Suppression",
               kind: "defensive",
               category: "external",
               used_at_ms_into_fight: 2_000,
               heal_amount: nil
             },
             %{
               caster_guid: "Player-Warlock",
               target_guid: "Player-Warlock",
               spell_id: 6262,
               kind: "healthstone",
               category: "consumable",
               used_at_ms_into_fight: 5_001,
               heal_amount: 118_155,
               overheal_amount: 0
             },
             %{
               caster_guid: "Player-Mage",
               target_guid: "Player-Mage",
               spell_id: 1_234_768,
               kind: "health_potion",
               category: "consumable",
               used_at_ms_into_fight: 8_000,
               heal_amount: 316_404,
               overheal_amount: 242_443
             }
           ] = projection.survival_action
  end

  test "survival actions stay catalog-gated and heal joins stay bounded" do
    projection =
      Projector.project(@encounter_dim_id, [
        # Non-catalog player cast is not a survival action.
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 1.0,
          source_guid: "Player-Mage",
          source_name: "Mage-Realm",
          target_guid: "Creature-Boss",
          target_name: "Boss",
          spell_id: 30_455,
          spell_name: "Ice Lance"
        ),
        # Catalog spell id cast by an NPC is not a player survival action.
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 2.0,
          source_guid: "Creature-Boss",
          source_name: "Boss",
          target_guid: "Creature-Boss",
          target_name: "Boss",
          spell_id: 6262,
          spell_name: "Healthstone"
        ),
        # Consumable heal with no matching cast emits no usage row.
        CombatLogEventFixtures.spell_heal_event(
          time_into_fight: 3.0,
          source_guid: "Player-Orphan",
          source_name: "Orphan-Realm",
          target_guid: "Player-Orphan",
          spell_id: 1_234_768,
          spell_name: "Silvermoon Health Potion",
          amount: 100_000,
          overhealing: 0
        ),
        # Heal outside the join window stays detached from the cast row.
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 10.0,
          source_guid: "Player-Rogue",
          source_name: "Rogue-Realm",
          target_guid: "0000000000000000",
          target_name: nil,
          spell_id: 6262,
          spell_name: "Healthstone"
        ),
        CombatLogEventFixtures.spell_heal_event(
          time_into_fight: 13.0,
          source_guid: "Player-Rogue",
          source_name: "Rogue-Realm",
          target_guid: "Player-Rogue",
          spell_id: 6262,
          spell_name: "Healthstone",
          amount: 90_000,
          overhealing: 0
        ),
        # Non-consumable catalog heals never join usage rows.
        CombatLogEventFixtures.spell_cast_success_event(
          time_into_fight: 20.0,
          source_guid: "Player-Rogue",
          source_name: "Rogue-Realm",
          target_guid: "0000000000000000",
          target_name: nil,
          spell_id: 185_311,
          spell_name: "Crimson Vial"
        ),
        CombatLogEventFixtures.spell_heal_event(
          time_into_fight: 20.1,
          source_guid: "Player-Rogue",
          source_name: "Rogue-Realm",
          target_guid: "Player-Rogue",
          spell_id: 185_311,
          spell_name: "Crimson Vial",
          amount: 50_000,
          overhealing: 0
        )
      ])

    assert [
             %{
               spell_id: 6262,
               kind: "healthstone",
               used_at_ms_into_fight: 10_000,
               heal_amount: nil,
               overheal_amount: nil
             },
             %{
               spell_id: 185_311,
               spell_name: "Crimson Vial",
               kind: "defensive",
               category: "personal",
               used_at_ms_into_fight: 20_000,
               heal_amount: nil,
               overheal_amount: nil
             }
           ] = projection.survival_action
  end

  test "death windows interleave damage, heals, and survival usages in a configurable window" do
    projection =
      Projector.project(
        @encounter_dim_id,
        [
          # Outside the 5s window: dropped from capture entirely.
          CombatLogEventFixtures.spell_cast_success_event(
            time_into_fight: 0.2,
            source_guid: "Player-Victim",
            source_name: "Victim-Realm",
            target_guid: "0000000000000000",
            target_name: nil,
            spell_id: 1_234_768,
            spell_name: "Silvermoon Health Potion"
          ),
          CombatLogEventFixtures.spell_damage_event(
            time_into_fight: 0.5,
            source_guid: "Creature-Boss",
            source_name: "Boss",
            target_guid: "Player-Victim",
            target_name: "Victim-Realm",
            spell_id: 111,
            spell_name: "Early Hit",
            amount: 100
          ),
          CombatLogEventFixtures.spell_damage_event(
            time_into_fight: 1.5,
            source_guid: "Creature-Boss",
            source_name: "Boss",
            target_guid: "Player-Victim",
            target_name: "Victim-Realm",
            spell_id: 123,
            spell_name: "Bad",
            amount: 40_000
          ),
          CombatLogEventFixtures.spell_heal_event(
            time_into_fight: 2.5,
            source_guid: "Player-Healer",
            source_name: "Healer-Realm",
            target_guid: "Player-Victim",
            target_name: "Victim-Realm",
            spell_id: 139,
            spell_name: "Renew",
            amount: 12_000,
            overhealing: 2_000
          ),
          CombatLogEventFixtures.spell_cast_success_event(
            time_into_fight: 3.0,
            source_guid: "Player-Victim",
            source_name: "Victim-Realm",
            target_guid: "0000000000000000",
            target_name: nil,
            spell_id: 6262,
            spell_name: "Healthstone"
          ),
          CombatLogEventFixtures.spell_heal_event(
            time_into_fight: 3.1,
            source_guid: "Player-Victim",
            source_name: "Victim-Realm",
            target_guid: "Player-Victim",
            target_name: "Victim-Realm",
            spell_id: 6262,
            spell_name: "Healthstone",
            amount: 118_000,
            overhealing: 0
          ),
          CombatLogEventFixtures.spell_heal_event(
            time_into_fight: 4.0,
            source_guid: "Player-Healer",
            source_name: "Healer-Realm",
            target_guid: "Player-Victim",
            target_name: "Victim-Realm",
            spell_id: 139,
            spell_name: "Renew",
            amount: 3_000,
            overhealing: 0
          ),
          # Same millisecond as the heal above: usage rows sort after
          # combat events on ms ties.
          CombatLogEventFixtures.spell_cast_success_event(
            time_into_fight: 4.0,
            source_guid: "Player-Priest",
            source_name: "Priest-Realm",
            target_guid: "Player-Victim",
            target_name: "Victim-Realm",
            spell_id: 33_206,
            spell_name: "Pain Suppression"
          ),
          CombatLogEventFixtures.spell_damage_event(
            time_into_fight: 5.5,
            source_guid: "Creature-Boss",
            source_name: "Boss",
            target_guid: "Player-Victim",
            target_name: "Victim-Realm",
            spell_id: 456,
            spell_name: "Killer",
            amount: 900_000,
            overkill: 350_000
          ),
          CombatLogEventFixtures.unit_died_event(
            time_into_fight: 6.0,
            target_guid: "Player-Victim",
            target_name: "Victim-Realm"
          )
        ],
        death_window_ms: 5_000
      )

    assert [death] = projection.death
    assert death.window_ms == 5_000
    assert death.window_truncated == false

    assert [
             %{"kind" => "damage", "ms_into_fight" => 1_500, "spell_id" => 123},
             %{
               "kind" => "heal",
               "ms_into_fight" => 2_500,
               "amount" => 12_000,
               "overheal" => 2_000
             },
             %{
               "kind" => "survival_action",
               "ms_into_fight" => 3_000,
               "spell_id" => 6262,
               "action_kind" => "healthstone",
               "caster_guid" => "Player-Victim",
               "heal_amount" => 118_000,
               "overheal_amount" => 0
             },
             %{"kind" => "heal", "ms_into_fight" => 3_100, "spell_id" => 6262},
             %{"kind" => "heal", "ms_into_fight" => 4_000, "amount" => 3_000},
             %{
               "kind" => "survival_action",
               "ms_into_fight" => 4_000,
               "spell_id" => 33_206,
               "action_kind" => "defensive",
               "category" => "external",
               "caster_guid" => "Player-Priest"
             },
             %{"kind" => "damage", "ms_into_fight" => 5_500, "spell_id" => 456}
           ] = death.window_events

    assert Enum.map(death.damage_recap, & &1["spell_id"]) == [456, 123]
    refute Enum.any?(death.damage_recap, &Map.has_key?(&1, "kind"))
    assert death.killing_blow_spell_id == 456
  end

  test "death windows cap burst events, keep the newest, and flag truncation" do
    burst =
      for i <- 0..104 do
        CombatLogEventFixtures.spell_damage_event(
          time_into_fight: 1.0 + i * 0.01,
          source_guid: "Creature-Boss",
          source_name: "Boss",
          target_guid: "Player-Victim",
          target_name: "Victim-Realm",
          spell_id: 123,
          spell_name: "Bad",
          amount: 1_000
        )
      end

    death_event =
      CombatLogEventFixtures.unit_died_event(
        time_into_fight: 3.0,
        target_guid: "Player-Victim",
        target_name: "Victim-Realm"
      )

    projection = Projector.project(@encounter_dim_id, burst ++ [death_event])

    assert [death] = projection.death
    assert death.window_truncated == true
    assert length(death.window_events) == 100
    assert hd(death.window_events)["ms_into_fight"] == 1_050
    assert length(death.damage_recap) == 100
  end

  test "a second death only sees events after the first death cleared the buffer" do
    projection =
      Projector.project(@encounter_dim_id, [
        CombatLogEventFixtures.spell_damage_event(
          time_into_fight: 1.0,
          source_guid: "Creature-Boss",
          source_name: "Boss",
          target_guid: "Player-Victim",
          target_name: "Victim-Realm",
          spell_id: 111,
          spell_name: "First Killer",
          amount: 100
        ),
        CombatLogEventFixtures.unit_died_event(
          time_into_fight: 2.0,
          target_guid: "Player-Victim",
          target_name: "Victim-Realm"
        ),
        CombatLogEventFixtures.spell_damage_event(
          time_into_fight: 3.0,
          source_guid: "Creature-Boss",
          source_name: "Boss",
          target_guid: "Player-Victim",
          target_name: "Victim-Realm",
          spell_id: 222,
          spell_name: "Second Killer",
          amount: 200
        ),
        CombatLogEventFixtures.unit_died_event(
          time_into_fight: 4.0,
          target_guid: "Player-Victim",
          target_name: "Victim-Realm"
        )
      ])

    assert [first_death, second_death] = projection.death
    assert Enum.map(first_death.window_events, & &1["spell_id"]) == [111]
    assert Enum.map(second_death.window_events, & &1["spell_id"]) == [222]
    assert second_death.killing_blow_spell_id == 222
  end

  test "captures combatant info talent payload on player info rows" do
    projection =
      Projector.project(@encounter_dim_id, [
        CombatLogEventFixtures.combatant_info_event(
          source_guid: "Player-Guardian",
          time_into_fight: 0.1,
          extra: %{spec_id: 104, talents: [[82_129, 103_193, 1], [82_130, 103_298, 2]]}
        ),
        CombatLogEventFixtures.combatant_info_event(
          source_guid: "Player-NoTalents",
          time_into_fight: 0.2,
          extra: %{spec_id: 266}
        )
      ])

    assert [
             %{
               player_guid: "Player-Guardian",
               spec_id: 104,
               talents: [
                 %{"node_id" => 82_129, "entry_id" => 103_193, "rank" => 1},
                 %{"node_id" => 82_130, "entry_id" => 103_298, "rank" => 2}
               ]
             },
             %{player_guid: "Player-NoTalents", spec_id: 266, talents: nil}
           ] = projection.player_info
  end

  test "normalizes nil-like natural-key values for required silver fields" do
    projection =
      Projector.project(@encounter_dim_id, [
        CombatLogEventFixtures.spell_damage_event(
          time_into_fight: 1.0,
          source_guid: nil,
          source_name: nil,
          target_guid: "Player-Victim",
          target_name: "Victim-Realm",
          spell_id: nil,
          spell_name: nil,
          amount: nil,
          overkill: nil
        )
      ])

    assert [
             %{
               target_guid: "Player-Victim",
               source_guid: "__UNKNOWN_SOURCE_GUID__",
               spell_id: 0,
               total_amount: 0,
               hit_count: 1,
               max_hit: 0,
               overkill_total: 0
             }
           ] = projection.damage_taken
  end
end
