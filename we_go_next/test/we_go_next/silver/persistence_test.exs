defmodule WeGoNext.Silver.PersistenceTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Accounts.User
  alias WeGoNext.CombatLogFile
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord
  alias WeGoNext.Fixtures.CombatLogEventFixtures
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

    dir =
      Path.join(System.tmp_dir!(), "wgn-silver-persistence-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    user =
      Repo.insert!(%User{
        name: "user-#{System.unique_integer([:positive])}",
        wow_logs_path: dir
      })

    combat_log_file = insert_combat_log_file!(dir, user)
    encounter = insert_encounter!(combat_log_file)

    on_exit(fn -> File.rm_rf!(dir) end)

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
               encounter_id: encounter.id,
               target_guid: "Player-Victim",
               source_guid: "Creature-Boss",
               spell_id: 123
             )

    assert %PlayerInfo{player_name: "Tank", detected_role: "tank"} =
             Repo.get_by!(PlayerInfo, encounter_id: encounter.id, player_guid: "Player-Tank")
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

  defp insert_combat_log_file!(dir, user) do
    file_path = Path.join(dir, "WoWCombatLog-test.txt")
    File.write!(file_path, "COMBAT_LOG_VERSION,22\n")

    %CombatLogFile{}
    |> CombatLogFile.changeset(%{
      file_path: file_path,
      file_size: 22,
      file_mtime: DateTime.utc_now() |> DateTime.truncate(:second),
      source: :live,
      user_id: user.id,
      last_parsed_byte: 0
    })
    |> Repo.insert!()
  end

  defp insert_encounter!(combat_log_file) do
    now = DateTime.utc_now()

    %EncounterRecord{}
    |> EncounterRecord.changeset(%{
      wow_encounter_id: "test-boss",
      name: "Test Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance",
      start_time: now,
      end_time: DateTime.add(now, 120, :second),
      success: false,
      fight_time_ms: 120_000,
      start_byte: 0,
      end_byte: 1_000,
      combat_log_file_id: combat_log_file.id,
      analysis: %{}
    })
    |> Repo.insert!()
  end
end
