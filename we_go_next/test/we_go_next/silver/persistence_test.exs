defmodule WeGoNext.Silver.PersistenceTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias WeGoNext.Fixtures.CombatLogEventFixtures
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Repo
  alias WeGoNext.Silver

  alias WeGoNext.Silver.{
    DamageDone,
    DamageTaken,
    DamageTakenEvent,
    Death,
    DebuffApplication,
    InterruptOpportunity,
    PlayerInfo
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    encounter = insert_dim_encounter!()

    {:ok, encounter: encounter}
  end

  test "project_and_persist inserts all silver row groups transactionally", %{
    encounter: encounter
  } do
    events = CombatLogEventFixtures.canonical_projection_events()

    assert {:ok, %{counts: counts}} = Silver.project_and_persist(encounter, events: events)

    assert counts == %{
             damage_taken: 2,
             damage_taken_event: 4,
             damage_done: 1,
             death: 1,
             interrupt_opportunity: 2,
             debuff_application: 2,
             player_info: 3
           }

    assert Repo.aggregate(DamageTaken, :count) == 2
    assert Repo.aggregate(DamageTakenEvent, :count) == 4
    assert Repo.aggregate(DamageDone, :count) == 1
    assert Repo.aggregate(Death, :count) == 1
    assert Repo.aggregate(InterruptOpportunity, :count) == 2
    assert Repo.aggregate(DebuffApplication, :count) == 2
    assert Repo.aggregate(PlayerInfo, :count) == 3

    assert %DamageTaken{total_amount: 700, hit_count: 2, max_hit: 400, overkill_total: 50} =
             Repo.get_by!(DamageTaken,
               encounter_dim_id: encounter.id,
               target_guid: "Player-Victim",
               source_guid: "Creature-Boss",
               spell_id: 123
             )

    assert %DamageTakenEvent{
             occurred_at_ms_into_fight: 2500,
             target_guid: "Player-Victim",
             target_name: "Victim",
             source_guid: "Creature-Boss",
             source_name: "Boss",
             spell_id: 123,
             spell_name: "Bad",
             amount: 400,
             overkill: 50
           } =
             Repo.get_by!(DamageTakenEvent,
               encounter_dim_id: encounter.id,
               combat_log_event_index: 4
             )

    assert %PlayerInfo{player_name: "Tank", detected_role: "tank"} =
             Repo.get_by!(PlayerInfo,
               encounter_dim_id: encounter.id,
               player_guid: "Player-Tank"
             )
  end

  test "project_and_persist is idempotent across natural keys", %{encounter: encounter} do
    events = CombatLogEventFixtures.canonical_projection_events()

    assert {:ok, _result} = Silver.project_and_persist(encounter, events: events)
    before_second_projection = persisted_projection_snapshot()

    assert {:ok, _result} = Silver.project_and_persist(encounter, events: events)

    assert Repo.aggregate(DamageTaken, :count) == 2
    assert Repo.aggregate(DamageTakenEvent, :count) == 4
    assert Repo.aggregate(DamageDone, :count) == 1
    assert Repo.aggregate(Death, :count) == 1
    assert Repo.aggregate(InterruptOpportunity, :count) == 2
    assert Repo.aggregate(DebuffApplication, :count) == 2
    assert Repo.aggregate(PlayerInfo, :count) == 3

    assert persisted_projection_snapshot() == before_second_projection
  end

  test "project_and_persist keeps normalized sentinel keys idempotent", %{encounter: encounter} do
    events = [
      CombatLogEventFixtures.swing_damage_event(
        time_into_fight: 1.0,
        source_guid: nil,
        source_name: nil,
        target_guid: "Player-MeleeVictim",
        target_name: "MeleeVictim-Realm",
        spell_id: nil,
        amount: 111
      ),
      CombatLogEventFixtures.swing_damage_event(
        time_into_fight: 1.5,
        source_guid: nil,
        source_name: nil,
        target_guid: "Player-MeleeVictim",
        target_name: "MeleeVictim-Realm",
        spell_id: nil,
        amount: 222
      ),
      CombatLogEventFixtures.swing_damage_event(
        time_into_fight: 2.0,
        source_guid: "Player-MeleeDps",
        source_name: "MeleeDps-Realm",
        target_guid: "Creature-Boss",
        target_name: "Boss",
        spell_id: nil,
        amount: 333
      ),
      CombatLogEventFixtures.debuff_applied_event(
        time_into_fight: 3.0,
        source_guid: nil,
        source_name: nil,
        target_guid: "Player-MeleeVictim",
        target_name: "MeleeVictim-Realm",
        spell_id: nil,
        spell_name: nil
      ),
      CombatLogEventFixtures.spell_interrupt_event(
        time_into_fight: 4.0,
        source_guid: "Player-MeleeDps",
        source_name: "MeleeDps-Realm",
        target_guid: nil,
        target_name: nil,
        extra_spell_id: nil,
        spell_id: nil
      )
    ]

    assert {:ok, _result} = Silver.project_and_persist(encounter, events: events)
    before_second_projection = persisted_projection_snapshot()

    assert {:ok, _result} = Silver.project_and_persist(encounter, events: events)

    assert persisted_projection_snapshot() == before_second_projection

    assert %DamageTaken{
             source_guid: "__UNKNOWN_SOURCE_GUID__",
             spell_id: 0,
             total_amount: 333,
             hit_count: 2,
             max_hit: 222
           } = Repo.one!(DamageTaken)

    assert [
             %DamageTakenEvent{
               combat_log_event_index: 0,
               source_guid: "__UNKNOWN_SOURCE_GUID__",
               spell_id: 0,
               amount: 111
             },
             %DamageTakenEvent{
               combat_log_event_index: 1,
               source_guid: "__UNKNOWN_SOURCE_GUID__",
               spell_id: 0,
               amount: 222
             }
           ] = Repo.all(from(event in DamageTakenEvent, order_by: event.combat_log_event_index))

    assert %DamageDone{spell_id: 0, total_amount: 333, hit_count: 1} = Repo.one!(DamageDone)

    assert %DebuffApplication{
             source_guid: "__UNKNOWN_SOURCE_GUID__",
             spell_id: 0,
             applied_at_ms_into_fight: 3000
           } = Repo.one!(DebuffApplication)

    assert %InterruptOpportunity{
             target_npc_guid: "__UNKNOWN_TARGET_GUID__",
             interrupted_spell_id: 0,
             interrupting_spell_id: 0
           } = Repo.one!(InterruptOpportunity)
  end

  test "project_and_persist deduplicates rows that share a natural key in one batch", %{
    encounter: encounter
  } do
    duplicate_cast =
      CombatLogEventFixtures.spell_cast_success_event(
        time_into_fight: 4.0,
        source_guid: "Creature-Caster",
        source_name: "Caster",
        target_guid: "Player-Dps",
        target_name: "Dps-Realm",
        spell_id: 777,
        spell_name: "Duplicate Cast"
      )

    events = [
      duplicate_cast,
      duplicate_cast,
      CombatLogEventFixtures.unit_died_event(
        time_into_fight: 5.0,
        target_guid: "Player-Dps",
        target_name: "Dps-Realm"
      ),
      CombatLogEventFixtures.unit_died_event(
        time_into_fight: 5.0,
        target_guid: "Player-Dps",
        target_name: "Dps-Realm"
      )
    ]

    assert {:ok, %{counts: counts}} = Silver.project_and_persist(encounter, events: events)

    assert counts.interrupt_opportunity == 1
    assert counts.death == 1
    assert Repo.aggregate(InterruptOpportunity, :count) == 1
    assert Repo.aggregate(Death, :count) == 1

    assert %InterruptOpportunity{
             target_npc_guid: "Creature-Caster",
             interrupted_spell_id: 777,
             opportunity_ms_into_fight: 4000,
             success: false
           } = Repo.one!(InterruptOpportunity)
  end

  test "project_and_persist chunks large silver inserts below PostgreSQL parameter limit", %{
    encounter: encounter
  } do
    events =
      Enum.map(1..5_000, fn index ->
        CombatLogEventFixtures.spell_damage_event(
          time_into_fight: index / 10,
          source_guid: "Creature-Boss",
          source_name: "Boss",
          target_guid: "Player-Chunked",
          target_name: "Chunked-Realm",
          spell_id: 900_000 + index,
          spell_name: "Chunked Hit #{index}",
          amount: index
        )
      end)

    assert {:ok, %{counts: counts}} = Silver.project_and_persist(encounter, events: events)

    assert counts.damage_taken_event == 5_000
    assert Repo.aggregate(DamageTakenEvent, :count) == 5_000
  end

  defp insert_dim_encounter! do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      wow_encounter_id: "test-boss",
      name: "Test Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance"
    })
    |> Repo.insert!()
  end

  defp persisted_projection_snapshot do
    %{
      damage_taken:
        DamageTaken
        |> Repo.all()
        |> Enum.map(
          &Map.take(&1, [
            :target_guid,
            :source_guid,
            :spell_id,
            :total_amount,
            :hit_count,
            :max_hit,
            :overkill_total,
            :source_is_npc
          ])
        )
        |> Enum.sort(),
      damage_taken_event:
        DamageTakenEvent
        |> Repo.all()
        |> Enum.map(
          &Map.take(&1, [
            :combat_log_event_index,
            :event_type,
            :occurred_at_ms_into_fight,
            :timestamp,
            :target_guid,
            :target_name,
            :source_guid,
            :source_name,
            :source_is_npc,
            :spell_id,
            :spell_name,
            :spell_school,
            :amount,
            :overkill
          ])
        )
        |> Enum.sort(),
      damage_done:
        DamageDone
        |> Repo.all()
        |> Enum.map(
          &Map.take(&1, [
            :source_guid,
            :target_guid,
            :spell_id,
            :total_amount,
            :hit_count,
            :max_hit
          ])
        )
        |> Enum.sort(),
      death:
        Death
        |> Repo.all()
        |> Enum.map(
          &Map.take(&1, [
            :target_guid,
            :died_at_ms_into_fight,
            :killing_blow_spell_id,
            :killing_blow_source_guid,
            :damage_recap
          ])
        )
        |> Enum.sort(),
      interrupt_opportunity:
        InterruptOpportunity
        |> Repo.all()
        |> Enum.map(
          &Map.take(&1, [
            :target_npc_guid,
            :interrupted_spell_id,
            :opportunity_ms_into_fight,
            :success,
            :interrupter_guid,
            :interrupting_spell_id
          ])
        )
        |> Enum.sort(),
      debuff_application:
        DebuffApplication
        |> Repo.all()
        |> Enum.map(
          &Map.take(&1, [
            :target_guid,
            :source_guid,
            :spell_id,
            :applied_at_ms_into_fight,
            :duration_ms,
            :stack_count
          ])
        )
        |> Enum.sort(),
      player_info:
        PlayerInfo
        |> Repo.all()
        |> Enum.map(
          &Map.take(&1, [
            :player_guid,
            :player_name,
            :class_id,
            :spec_id,
            :item_level,
            :detected_role
          ])
        )
        |> Enum.sort()
    }
  end
end
