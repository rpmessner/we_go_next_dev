defmodule WeGoNext.ImporterTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Accounts.User
  alias WeGoNext.{CombatLogFile, Importer, Repo}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord
  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, FactFailure}
  alias WeGoNext.Rules

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

    dir = Path.join(System.tmp_dir!(), "wgn-importer-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    user =
      Repo.insert!(%User{
        name: "user-#{System.unique_integer([:positive])}",
        wow_logs_path: dir
      })

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir, user: user}
  end

  test "sync_log fetches existing duplicate encounters without counting them as new", %{
    dir: dir,
    user: user
  } do
    source_path = fixture_path("combat_log_base.txt")
    log_path = Path.join(dir, "WoWCombatLog-112725_120000.txt")
    File.cp!(source_path, log_path)

    combat_log_file =
      insert_combat_log_file!(%{
        file_path: log_path,
        file_size: 0,
        user_id: user.id
      })

    existing =
      insert_encounter!(%{
        combat_log_file_id: combat_log_file.id,
        start_time: ~U[2025-11-27 12:00:01.000000Z]
      })

    assert {:ok, %{new_encounters: 0}} = Importer.sync_log(combat_log_file)

    assert Repo.aggregate(EncounterRecord, :count) == 1
    assert Repo.aggregate(DimEncounter, :count) == 0
    assert Repo.aggregate(DamageTaken, :count) == 0
    assert Repo.aggregate(FactFailure, :count) == 0

    persisted = Repo.get!(EncounterRecord, existing.id)
    assert persisted.end_byte == existing.end_byte
  end

  test "import_log runs silver and gold medallion path for newly inserted encounters", %{
    dir: dir,
    user: user
  } do
    source_path = fixture_path("combat_log_base.txt")
    log_path = Path.join(dir, "WoWCombatLog-112725_120000.txt")
    File.cp!(source_path, log_path)

    {:ok, ruleset} = Rules.create_ruleset(%{name: "Importer Active Rules", status: "active"})

    {:ok, rule} =
      Rules.create_mechanic_criterion(%{
        ruleset_id: ruleset.id,
        spell_id: 888_888,
        spell_name: "Crushing Blow",
        mechanic_type: "avoidable",
        boss_encounter_id: "2887",
        difficulty_id: 15,
        threshold: %{"max_hits" => 0}
      })

    {:ok, %{criteria: [criterion]}} = Rules.promote_ruleset_to_gold(ruleset)
    assert criterion.source_rule_id == rule.id

    assert {:ok, %{new_encounters: 1, medallion_results: [{:ok, medallion_result}]}} =
             Importer.import_log(log_path, user.id)

    assert %{
             damage_taken: 2,
             damage_taken_event: 2,
             damage_done: 1,
             death: 1,
             interrupt_opportunity: 1
           } =
             medallion_result.silver_counts

    assert %{inserted: 1} = medallion_result.fact_failure
    assert %{fact_failure: %{inserted: 1}} = medallion_result.gold

    dim_encounter = Repo.get!(DimEncounter, medallion_result.dim_encounter_id)
    assert dim_encounter.wow_encounter_id == "2887"
    assert dim_encounter.source_file_path == log_path

    assert Repo.aggregate(DimEncounter, :count) == 1
    assert Repo.aggregate(DamageTaken, :count) == 2
    assert Repo.aggregate(DamageTakenEvent, :count) == 2
    assert Repo.aggregate(DamageDone, :count) == 1
    assert Repo.aggregate(Death, :count) == 1
    assert Repo.aggregate(InterruptOpportunity, :count) == 1
    assert Repo.aggregate(DebuffApplication, :count) == 1
    assert Repo.aggregate(PlayerInfo, :count) == 3

    assert Repo.get_by!(DimMechanicCriterion, source_rule_id: rule.id).ruleset_id == ruleset.id

    assert %FactFailure{failure_count: 1, total_damage: 200_000} =
             Repo.get_by!(FactFailure,
               encounter_dim_id: dim_encounter.id,
               criterion_dim_id: criterion.id
             )

    assert {:ok, %{new_encounters: 0, medallion_results: []}} =
             Importer.import_log(log_path, user.id)

    assert Repo.aggregate(DimEncounter, :count) == 1
    assert Repo.aggregate(DamageTaken, :count) == 2
    assert Repo.aggregate(DamageTakenEvent, :count) == 2
    assert Repo.aggregate(FactFailure, :count) == 1
  end

  test "importer delegates gold rebuilds through the gold encounter boundary" do
    importer_source = File.read!("lib/we_go_next/importer.ex")

    refute importer_source =~ "FactFailure.rebuild_for_encounter"
    assert importer_source =~ "RebuildEncounter.rebuild"
  end

  test "import_log reconciles live log moved to archive and continues from preserved byte", %{
    dir: dir,
    user: user
  } do
    live_content = File.read!(fixture_path("combat_log_base.txt"))
    continuation_content = File.read!(fixture_path("second_encounter.txt"))

    archive_dir = Path.join(dir, "warcraftlogsarchive")
    File.mkdir_p!(archive_dir)

    live_path = Path.join(dir, "WoWCombatLog-112725_120000.txt")
    archive_path = Path.join(archive_dir, "Archive-WoWCombatLog-112725_120000.txt")

    File.write!(live_path, live_content)

    assert {:ok, %{file: live_file, new_encounters: 1}} =
             Importer.import_log(live_path, user.id)

    first_encounter = Repo.get_by!(EncounterRecord, combat_log_file_id: live_file.id)
    live_last_parsed_byte = live_file.last_parsed_byte

    assert live_file.source == :live
    assert live_file.file_path == live_path
    assert live_last_parsed_byte == byte_size(live_content)
    assert Repo.aggregate(CombatLogFile, :count) == 1
    assert Repo.aggregate(EncounterRecord, :count) == 1

    File.rm!(live_path)
    File.write!(archive_path, live_content)

    assert {:ok, %{file: archived_file, new_encounters: 0}} =
             Importer.import_log(archive_path, user.id)

    assert archived_file.id == live_file.id
    assert archived_file.source == :warcraftlogs_archive
    assert archived_file.file_path == archive_path
    assert archived_file.last_parsed_byte == live_last_parsed_byte
    assert Repo.aggregate(CombatLogFile, :count) == 1
    assert Repo.aggregate(EncounterRecord, :count) == 1

    topic = "importer-move-continuation-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(WeGoNext.PubSub, topic)

    File.write!(archive_path, live_content <> "\n" <> continuation_content)

    assert {:ok, %{file: continued_file, new_encounters: 1}} =
             Importer.import_log(archive_path, user.id, progress_topic: topic)

    assert_receive {:import_progress,
                    %{
                      encounters_found: 1,
                      bytes_read: bytes_read,
                      total_bytes: total_bytes
                    }}

    refute_receive {:import_progress, %{encounters_found: 2}}, 50

    assert bytes_read == continued_file.last_parsed_byte
    assert total_bytes == continued_file.last_parsed_byte
    assert bytes_read > live_last_parsed_byte

    assert continued_file.id == live_file.id
    assert continued_file.file_path == archive_path
    assert continued_file.source == :warcraftlogs_archive
    assert Repo.aggregate(CombatLogFile, :count) == 1
    assert Repo.aggregate(EncounterRecord, :count) == 2

    assert Repo.get!(EncounterRecord, first_encounter.id).combat_log_file_id == live_file.id

    assert %EncounterRecord{wow_encounter_id: "2888"} =
             Repo.get_by!(EncounterRecord,
               combat_log_file_id: live_file.id,
               start_time: ~U[2025-11-27 12:05:00.000000Z]
             )
  end

  defp insert_combat_log_file!(attrs) do
    attrs =
      Map.merge(
        %{
          file_size: 0,
          file_mtime: DateTime.utc_now() |> DateTime.truncate(:second),
          last_parsed_byte: 0,
          source: :live
        },
        attrs
      )

    %CombatLogFile{}
    |> CombatLogFile.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_encounter!(attrs) do
    attrs =
      Map.merge(
        %{
          wow_encounter_id: "2887",
          name: "Test Boss",
          difficulty_id: 15,
          difficulty_name: "Heroic",
          group_size: 20,
          instance_id: "2652",
          end_time: ~U[2025-11-27 12:00:45.000000Z],
          success: false,
          fight_time_ms: 44_000,
          start_byte: 240,
          end_byte: 2_569,
          is_reset: false
        },
        attrs
      )

    %EncounterRecord{}
    |> EncounterRecord.changeset(attrs)
    |> Repo.insert!()
  end

  defp fixture_path(name) do
    Path.expand("../fixtures/#{name}", __DIR__)
  end
end
