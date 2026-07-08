defmodule WeGoNext.RulesTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Repo
  alias WeGoNext.Rules
  alias WeGoNext.SourceData
  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Rules.{MechanicCriterion, Ruleset}
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo}
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    original_documents_root = Application.fetch_env!(:we_go_next, :documents_root)

    documents_root =
      Path.join(System.tmp_dir!(), "wgn-documents-#{System.unique_integer([:positive])}")

    Application.put_env(:we_go_next, :documents_root, documents_root)

    on_exit(fn ->
      Application.put_env(:we_go_next, :documents_root, original_documents_root)
      File.rm_rf(documents_root)
    end)

    :ok
  end

  test "rules schemas live in the rules prefix" do
    assert Ruleset.__schema__(:prefix) == "rules"
    assert Ruleset.__schema__(:source) == "ruleset"

    assert MechanicCriterion.__schema__(:prefix) == "rules"
    assert MechanicCriterion.__schema__(:source) == "mechanic_criterion"
    assert MechanicCriterion.__schema__(:association, :ruleset).related == Ruleset
  end

  test "activating a ruleset archives the previously active ruleset" do
    {:ok, first} = Rules.create_ruleset(%{name: "Season 1", version: 1})
    {:ok, second} = Rules.create_ruleset(%{name: "Season 1 Patch 2", version: 2})

    assert {:ok, active_first} = Rules.activate_ruleset(first)
    assert active_first.status == "active"
    assert active_first.activated_at
    assert active_first.archived_at == nil

    assert {:ok, active_second} = Rules.activate_ruleset(second)
    assert active_second.status == "active"
    assert active_second.activated_at
    assert active_second.archived_at == nil

    archived_first = Rules.get_ruleset!(first.id)
    assert archived_first.status == "archived"
    assert archived_first.archived_at

    assert Rules.get_active_ruleset().id == second.id
  end

  test "database allows only one active ruleset" do
    {:ok, first} = Rules.create_ruleset(%{name: "Active One", status: "active", version: 1})
    assert first.status == "active"

    assert {:error, changeset} =
             Rules.create_ruleset(%{name: "Active Two", status: "active", version: 1})

    assert {"has already been taken", _} = changeset.errors[:status]
  end

  test "creates mechanic criteria as authored rules scoped to a ruleset" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})

    assert ruleset.product == "wow"
    assert ruleset.channel == "retail"

    assert {:ok, criterion} =
             Rules.create_mechanic_criterion(%{
               ruleset_id: ruleset.id,
               spell_id: 123,
               spell_name: "Avoid This",
               mechanic_type: "avoidable",
               threshold: %{"max_hits" => 0}
             })

    assert criterion.ruleset_id == ruleset.id
    assert criterion.active == true
    assert Rules.list_mechanic_criteria(ruleset) == [criterion]
  end

  test "mechanic criterion uniqueness treats null boss and difficulty as scoped values" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})

    attrs = %{
      ruleset_id: ruleset.id,
      spell_id: 123,
      spell_name: "Avoid This",
      mechanic_type: "avoidable",
      threshold: %{"max_hits" => 0}
    }

    assert {:ok, _criterion} = Rules.create_mechanic_criterion(attrs)

    assert {:error, changeset} = Rules.create_mechanic_criterion(attrs)

    assert {"has already been taken", _} =
             changeset.errors[:ruleset_id]

    assert {:ok, _boss_specific} =
             attrs
             |> Map.merge(%{
               boss_encounter_id: "boss-one",
               boss_name: "Boss One"
             })
             |> Rules.create_mechanic_criterion()

    assert {:ok, _difficulty_specific} =
             attrs
             |> Map.merge(%{
               boss_encounter_id: "boss-one",
               boss_name: "Boss One",
               difficulty_id: 16
             })
             |> Rules.create_mechanic_criterion()
  end

  test "avoidable thresholds require max_hits as a non-negative integer" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})
    attrs = criterion_attrs(ruleset, %{mechanic_type: "avoidable"})

    assert {:error, changeset} = Rules.create_mechanic_criterion(attrs)

    assert {"must contain only max_hits as a non-negative integer", _} =
             changeset.errors[:threshold]

    assert {:error, changeset} =
             attrs
             |> Map.put(:threshold, %{"max_hits" => -1})
             |> Rules.create_mechanic_criterion()

    assert {"must contain only max_hits as a non-negative integer", _} =
             changeset.errors[:threshold]

    assert {:error, changeset} =
             attrs
             |> Map.put(:threshold, %{"max_hits" => "0"})
             |> Rules.create_mechanic_criterion()

    assert {"must contain only max_hits as a non-negative integer", _} =
             changeset.errors[:threshold]

    assert {:ok, criterion} =
             attrs
             |> Map.put(:threshold, %{"max_hits" => 0})
             |> Rules.create_mechanic_criterion()

    assert criterion.threshold == %{"max_hits" => 0}
  end

  test "interrupt thresholds default must_interrupt to true and require a boolean" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})

    assert {:ok, criterion} =
             ruleset
             |> criterion_attrs(%{mechanic_type: "interrupt", spell_id: 321})
             |> Rules.create_mechanic_criterion()

    assert criterion.threshold == %{"must_interrupt" => true}

    assert {:error, changeset} =
             ruleset
             |> criterion_attrs(%{
               mechanic_type: "interrupt",
               spell_id: 322,
               threshold: %{"must_interrupt" => "true"}
             })
             |> Rules.create_mechanic_criterion()

    assert {"must contain only must_interrupt as a boolean", _} = changeset.errors[:threshold]
  end

  test "targeted cone thresholds define assignment and impact evidence" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})

    threshold = %{
      "target_marker_spell_id" => 1_255_612,
      "impact_spell_ids" => [1_244_225],
      "hit_debuff_spell_ids" => [1_255_979],
      "max_safe_hit_count" => 2,
      "target_role_policy" => "any",
      "allowed_collateral_roles" => ["tank"],
      "position_evidence" => "optional"
    }

    assert {:ok, criterion} =
             ruleset
             |> criterion_attrs(%{
               spell_id: 1_244_221,
               spell_name: "Dread Breath",
               mechanic_type: "targeted_cone",
               threshold: threshold
             })
             |> Rules.create_mechanic_criterion()

    assert criterion.threshold == threshold

    assert {:error, changeset} =
             ruleset
             |> criterion_attrs(%{
               spell_id: 1_244_222,
               mechanic_type: "targeted_cone",
               threshold: %{"impact_spell_ids" => [1_244_225]}
             })
             |> Rules.create_mechanic_criterion()

    assert {
             "must define target marker, impact spells, safe hit count, role policy, allowed collateral roles, and position evidence",
             _
           } = changeset.errors[:threshold]
  end

  test "mechanic types without fact semantics require an empty threshold" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Draft Rules"})

    assert {:ok, criterion} =
             ruleset
             |> criterion_attrs(%{mechanic_type: "soak", spell_id: 456})
             |> Rules.create_mechanic_criterion()

    assert criterion.threshold == %{}

    assert {:error, changeset} =
             ruleset
             |> criterion_attrs(%{
               mechanic_type: "soak",
               spell_id: 457,
               threshold: %{"players" => 3}
             })
             |> Rules.create_mechanic_criterion()

    assert {"must be empty until this mechanic type has fact semantics", _} =
             changeset.errors[:threshold]
  end

  test "seed_rules_from_file idempotently creates and updates rules from static JSON" do
    path = Path.join(System.tmp_dir!(), "wgn-rules-#{System.unique_integer([:positive])}.json")

    payload = %{
      "ruleset" => %{
        "name" => "Seeded Rules",
        "version" => 1,
        "status" => "draft"
      },
      "criteria" => [
        %{
          "spell_id" => 111,
          "spell_name" => "Seeded Avoid",
          "mechanic_type" => "avoidable",
          "threshold" => %{"max_hits" => 0}
        },
        %{
          "spell_id" => 222,
          "spell_name" => "Seeded Interrupt",
          "mechanic_type" => "interrupt"
        }
      ]
    }

    File.write!(path, Jason.encode!(payload))

    on_exit(fn -> File.rm(path) end)

    assert {:ok, %{ruleset: first_ruleset, criteria: first_criteria}} =
             Rules.seed_rules_from_file(path)

    assert length(first_criteria) == 2

    assert Enum.find(first_criteria, &(&1.spell_id == 222)).threshold == %{
             "must_interrupt" => true
           }

    assert {:ok, %{ruleset: second_ruleset, criteria: second_criteria}} =
             Rules.seed_rules_from_file(path)

    assert second_ruleset.id == first_ruleset.id

    assert Enum.map(second_criteria, & &1.id) |> Enum.sort() ==
             Enum.map(first_criteria, & &1.id) |> Enum.sort()

    ruleset_count =
      Ruleset
      |> where([r], r.name == "Seeded Rules" and r.version == 1)
      |> Repo.aggregate(:count)

    criterion_count =
      MechanicCriterion
      |> where([c], c.ruleset_id == ^second_ruleset.id)
      |> Repo.aggregate(:count)

    assert ruleset_count == 1
    assert criterion_count == 2
  end

  test "sync_raid_mechanics creates editable rules from code-defined raid catalog" do
    assert {:ok, %{ruleset: ruleset, criteria: criteria, promoted: nil, rebuild: nil}} =
             Rules.sync_raid_mechanics("midnight_season_1")

    assert ruleset.name == "Midnight Season 1 Mechanics"
    assert ruleset.status == "draft"
    assert length(criteria) == 30

    assert %MechanicCriterion{
             spell_id: 1_248_652,
             spell_name: "Divine Toll",
             mechanic_type: "avoidable",
             boss_encounter_id: "3180",
             boss_name: "Lightblinded Vanguard",
             threshold: %{"max_hits" => 0},
             active: true
           } = Enum.find(criteria, &(&1.spell_id == 1_248_652))

    refute Enum.any?(criteria, &(&1.spell_id == 1_249_017))
    refute Enum.any?(criteria, &(&1.mechanic_type == "soak"))

    assert Enum.any?(
             criteria,
             &(&1.spell_id == 1_244_221 and &1.mechanic_type == "targeted_cone")
           )

    assert {:ok, %{ruleset: second_ruleset, criteria: second_criteria}} =
             Rules.sync_raid_mechanics("midnight_season_1")

    assert second_ruleset.id == ruleset.id

    assert Enum.map(second_criteria, & &1.id) |> Enum.sort() ==
             Enum.map(criteria, & &1.id) |> Enum.sort()
  end

  test "sync_raid_mechanics can activate and promote code-defined raid rules" do
    assert {:ok, %{ruleset: ruleset, criteria: criteria, promoted: promoted}} =
             Rules.sync_raid_mechanics("midnight_season_1", activate: true, promote: true)

    assert ruleset.status == "active"
    assert length(promoted.criteria) == length(criteria)
    assert Enum.all?(promoted.criteria, &(&1.ruleset_id == ruleset.id))
  end

  test "sync_raid_mechanics rebuild path activates, promotes, and builds current-tier facts" do
    encounter = insert_dim_encounter!("3180", "Lightblinded Vanguard", 16)

    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", "Creature-A", 1_248_652, 10_000, 1)

    assert {:ok, %{ruleset: ruleset, criteria: criteria, promoted: promoted, rebuild: rebuild}} =
             Rules.sync_raid_mechanics("midnight_season_1", rebuild: true)

    assert ruleset.status == "active"
    assert length(criteria) == 30
    assert length(promoted.criteria) == 30
    assert %{encounters: 1, inserted: 1} = rebuild

    criterion = Enum.find(promoted.criteria, &(&1.spell_id == 1_248_652))
    player = Repo.get_by!(DimPlayer, player_guid: "Player-One")

    assert %FactFailure{failure_count: 1, total_damage: 10_000} =
             Repo.get_by!(FactFailure,
               encounter_dim_id: encounter.id,
               player_dim_id: player.id,
               criterion_dim_id: criterion.id
             )
  end

  test "promotes ruleset criteria to idempotent gold snapshots" do
    {:ok, ruleset} =
      Rules.create_ruleset(%{
        name: "Promoted Rules",
        version: 3,
        product: "wow",
        channel: "ptr",
        build_version: "11.2.5.12345",
        build_key: "11.2.5"
      })

    {:ok, avoidable_rule} =
      Rules.create_mechanic_criterion(%{
        ruleset_id: ruleset.id,
        spell_id: 1_214_081,
        spell_name: "Arcane Expulsion",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0},
        notes: "Local evidence"
      })

    {:ok, interrupt_rule} =
      Rules.create_mechanic_criterion(%{
        ruleset_id: ruleset.id,
        spell_id: 999,
        spell_name: "Kick This",
        mechanic_type: "interrupt"
      })

    assert {:ok, %{criteria: first_snapshots}} = Rules.promote_ruleset_to_gold(ruleset)

    assert Enum.map(first_snapshots, & &1.source_rule_id) == [
             avoidable_rule.id,
             interrupt_rule.id
           ]

    assert Enum.all?(first_snapshots, &(&1.ruleset_id == ruleset.id))
    assert Enum.all?(first_snapshots, &(&1.ruleset_version == 3))
    assert Enum.all?(first_snapshots, &(&1.product == "wow"))
    assert Enum.all?(first_snapshots, &(&1.channel == "ptr"))
    assert Enum.all?(first_snapshots, &(&1.build_version == "11.2.5.12345"))
    assert Enum.all?(first_snapshots, &(&1.build_key == "11.2.5"))

    avoidable_snapshot = Enum.find(first_snapshots, &(&1.source_rule_id == avoidable_rule.id))
    assert avoidable_snapshot.spell_id == 1_214_081
    assert avoidable_snapshot.spell_name == "Arcane Expulsion"
    assert avoidable_snapshot.mechanic_type == "avoidable"
    assert avoidable_snapshot.threshold == %{"max_hits" => 0}
    assert avoidable_snapshot.notes == "Local evidence"
    assert avoidable_snapshot.active == true

    {:ok, updated_rule} =
      Rules.update_mechanic_criterion(avoidable_rule, %{
        notes: "Updated local evidence",
        active: false
      })

    assert {:ok, %{criteria: second_snapshots}} = Rules.promote_ruleset_to_gold(ruleset)

    assert Enum.map(second_snapshots, & &1.id) |> Enum.sort() ==
             Enum.map(first_snapshots, & &1.id) |> Enum.sort()

    updated_snapshot = Repo.get_by!(DimMechanicCriterion, source_rule_id: updated_rule.id)
    assert updated_snapshot.notes == "Updated local evidence"
    assert updated_snapshot.active == false

    assert Repo.aggregate(DimMechanicCriterion, :count) == 2
  end

  test "promotion uses rules criteria" do
    {:ok, ruleset} = Rules.create_ruleset(%{name: "Active Rules", status: "active"})

    {:ok, rule_criterion} =
      Rules.create_mechanic_criterion(%{
        ruleset_id: ruleset.id,
        spell_id: 888,
        spell_name: "Rules Rule",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0}
      })

    assert {:ok, %{criteria: [snapshot]}} = Rules.promote_active_ruleset_to_gold()

    assert snapshot.source_rule_id == rule_criterion.id
    assert snapshot.spell_id == 888
  end

  test "current_tier_mechanics_status summarizes synced and failure-ready mechanics" do
    Repo.delete_all(DimMechanicCriterion)
    Repo.delete_all(MechanicCriterion)
    Repo.delete_all(Ruleset)

    {:ok, ruleset} = Rules.create_ruleset(%{name: "Operator Rules", status: "active"})

    {:ok, rule} =
      Rules.create_mechanic_criterion(%{
        ruleset_id: ruleset.id,
        spell_id: 777,
        spell_name: "Operator Spell",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0}
      })

    assert %{
             mechanics_synced?: true,
             synced_mechanics_count: 1,
             failure_ready_mechanics_count: 0,
             active_ruleset: ^ruleset,
             authored_rules_count: 1,
             promoted_snapshots_count: 0,
             active_authored_rules_count: 1,
             active_promoted_snapshots_count: 0
           } = Rules.current_tier_mechanics_status()

    assert {:ok, %{criteria: [snapshot]}} = Rules.promote_active_ruleset_to_gold()
    assert snapshot.source_rule_id == rule.id

    assert %{
             mechanics_synced?: true,
             synced_mechanics_count: 1,
             failure_ready_mechanics_count: 1,
             authored_rules_count: 1,
             promoted_snapshots_count: 1,
             active_authored_rules_count: 1,
             active_promoted_snapshots_count: 1
           } = Rules.current_tier_mechanics_status()
  end

  test "promotion can resolve spell and encounter names from source references" do
    {:ok, ruleset} =
      Rules.create_ruleset(%{
        name: "Reference Rules",
        version: 1,
        product: "wow",
        channel: "retail",
        build_key: "11.2.0"
      })

    assert {:ok, _reference} =
             SourceData.upsert_spell_reference(%{
               spell_id: 555,
               current_name: "Referenced Spell",
               localized_names: %{"enUS" => "Referenced Spell"},
               product: "wow",
               channel: "retail",
               build_key: "11.2.0",
               locale: "enUS",
               source_system: "game_data",
               source_priority: 10
             })

    assert {:ok, _reference} =
             SourceData.upsert_encounter_reference(%{
               encounter_id: 3180,
               current_name: "Referenced Boss",
               localized_names: %{"enUS" => "Referenced Boss"},
               zone_id: 2912,
               zone_name: "The Voidspire",
               instance_id: 1307,
               instance_name: "The Voidspire",
               product: "wow",
               channel: "retail",
               build_key: "11.2.0",
               locale: "enUS",
               source_system: "game_data",
               source_priority: 10
             })

    {:ok, rule_criterion} =
      Rules.create_mechanic_criterion(%{
        ruleset_id: ruleset.id,
        spell_id: 555,
        spell_name: "Static Spell",
        mechanic_type: "avoidable",
        boss_encounter_id: "3180",
        boss_name: "Static Boss",
        threshold: %{"max_hits" => 0}
      })

    assert {:ok, %{criteria: [snapshot]}} = Rules.promote_ruleset_to_gold(ruleset)

    assert snapshot.source_rule_id == rule_criterion.id
    assert snapshot.spell_name == "Referenced Spell"
    assert snapshot.boss_name == "Referenced Boss"
    assert snapshot.build_key == "11.2.0"
  end

  defp criterion_attrs(%Ruleset{} = ruleset, overrides) do
    Map.merge(
      %{
        ruleset_id: ruleset.id,
        spell_id: 123,
        spell_name: "Rule Spell",
        mechanic_type: "avoidable",
        threshold: %{}
      },
      overrides
    )
  end

  defp insert_dim_encounter!(wow_encounter_id, name, difficulty_id) do
    source_start_byte = System.unique_integer([:positive])

    %DimEncounter{}
    |> DimEncounter.changeset(%{
      source_head_sha256: String.duplicate("f", 64),
      wow_encounter_id: wow_encounter_id,
      name: name,
      difficulty_id: difficulty_id,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance",
      start_time: ~U[2026-06-28 20:00:00Z],
      end_time: ~U[2026-06-28 20:05:00Z],
      success: false,
      fight_time_ms: 300_000,
      start_byte: source_start_byte,
      end_byte: source_start_byte + 1000
    })
    |> Repo.insert!()
  end

  defp insert_player_info!(encounter, player_guid, player_name) do
    %PlayerInfo{}
    |> PlayerInfo.changeset(%{
      encounter_dim_id: encounter.id,
      player_guid: player_guid,
      player_name: player_name,
      class_id: 1,
      spec_id: 71,
      detected_role: "unknown"
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken!(
         encounter,
         target_guid,
         source_guid,
         spell_id,
         total_amount,
         hit_count
       ) do
    %DamageTaken{}
    |> DamageTaken.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: target_guid,
      source_guid: source_guid,
      spell_id: spell_id,
      total_amount: total_amount,
      hit_count: hit_count,
      max_hit: total_amount,
      overkill_total: 0,
      source_is_npc: true
    })
    |> Repo.insert!()
  end
end
