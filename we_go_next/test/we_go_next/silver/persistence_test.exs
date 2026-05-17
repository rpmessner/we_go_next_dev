defmodule WeGoNext.Silver.PersistenceTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Fixtures.CombatLogEventFixtures
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Repo
  alias WeGoNext.Silver

  alias WeGoNext.Silver.{
    DamageDone,
    DamageTaken,
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
             damage_done: 1,
             death: 1,
             interrupt_opportunity: 2,
             debuff_application: 2,
             player_info: 3
           }

    assert Repo.aggregate(DamageTaken, :count) == 2
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

    assert %PlayerInfo{player_name: "Tank", detected_role: "tank"} =
             Repo.get_by!(PlayerInfo,
               encounter_dim_id: encounter.id,
               player_guid: "Player-Tank"
             )
  end

  test "project_and_persist is idempotent across natural keys", %{encounter: encounter} do
    events = CombatLogEventFixtures.canonical_projection_events()

    assert {:ok, _result} = Silver.project_and_persist(encounter, events: events)
    assert {:ok, _result} = Silver.project_and_persist(encounter, events: events)

    assert Repo.aggregate(DamageTaken, :count) == 2
    assert Repo.aggregate(DamageDone, :count) == 1
    assert Repo.aggregate(Death, :count) == 1
    assert Repo.aggregate(InterruptOpportunity, :count) == 2
    assert Repo.aggregate(DebuffApplication, :count) == 2
    assert Repo.aggregate(PlayerInfo, :count) == 3
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
end
