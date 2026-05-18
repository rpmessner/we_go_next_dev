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
               interrupted_spell_id: 777,
               opportunity_ms_into_fight: 4_000,
               success: true,
               interrupter_guid: "Player-Dps",
               interrupting_spell_id: 1766
             },
             %{
               encounter_dim_id: @encounter_dim_id,
               target_npc_guid: "Creature-Caster",
               interrupted_spell_id: 888,
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
               player_guid: "Player-Dps",
               player_name: "Dps",
               class_id: 1,
               spec_id: 71,
               item_level: nil,
               detected_role: "unknown"
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
