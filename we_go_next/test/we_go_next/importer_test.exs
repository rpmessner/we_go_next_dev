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
    source_path = Path.expand("../fixtures/WoWCombatLog-112725_120000.txt", __DIR__)
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
        start_time: ~U[2025-11-27 12:00:01.000000Z],
        analysis: %{"source" => "existing"}
      })

    assert {:ok, %{new_encounters: 0}} = Importer.sync_log(combat_log_file)

    assert Repo.aggregate(EncounterRecord, :count) == 1
    assert Repo.aggregate(DimEncounter, :count) == 0
    assert Repo.aggregate(DamageTaken, :count) == 0
    assert Repo.aggregate(FactFailure, :count) == 0

    persisted = Repo.get!(EncounterRecord, existing.id)
    assert persisted.analysis == %{"source" => "existing"}
    assert persisted.end_byte == existing.end_byte
  end

  test "import_log runs silver and gold medallion path for newly inserted encounters", %{
    dir: dir,
    user: user
  } do
    source_path = Path.expand("../fixtures/WoWCombatLog-112725_120000.txt", __DIR__)
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
             Importer.import_log(log_path, user.id, compute_legacy_analysis: false)

    assert %{damage_taken: 2, damage_done: 1, death: 1, interrupt_opportunity: 1} =
             medallion_result.silver_counts

    assert %{inserted: 1} = medallion_result.fact_failure

    dim_encounter = Repo.get!(DimEncounter, medallion_result.dim_encounter_id)
    assert dim_encounter.wow_encounter_id == "2887"
    assert dim_encounter.source_file_path == log_path

    assert Repo.aggregate(DimEncounter, :count) == 1
    assert Repo.aggregate(DamageTaken, :count) == 2
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
             Importer.import_log(log_path, user.id, compute_legacy_analysis: false)

    assert Repo.aggregate(DimEncounter, :count) == 1
    assert Repo.aggregate(DamageTaken, :count) == 2
    assert Repo.aggregate(FactFailure, :count) == 1
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
          is_reset: false,
          analysis: %{}
        },
        attrs
      )

    %EncounterRecord{}
    |> EncounterRecord.changeset(attrs)
    |> Repo.insert!()
  end
end
