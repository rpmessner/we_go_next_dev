defmodule WeGoNext.Gold.FactFailureTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Gold.FactFailure.Derivation
  alias WeGoNext.Repo
  alias WeGoNext.Rules
  alias WeGoNext.Rules.Ruleset

  alias WeGoNext.Silver.{
    DamageTaken,
    DamageTakenEvent,
    DebuffApplication,
    InterruptOpportunity,
    PlayerInfo
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    ruleset = insert_ruleset!("Active Ruleset", "active")
    encounter = insert_dim_encounter!("boss-one", 16)
    other_encounter = insert_dim_encounter!("boss-two", 16)

    {:ok, ruleset: ruleset, encounter: encounter, other_encounter: other_encounter}
  end

  test "rebuild_for_encounter builds avoidable facts from aggregated silver damage", %{
    ruleset: ruleset,
    encounter: encounter
  } do
    criterion =
      insert_criteria!(ruleset, %{
        spell_id: 101,
        spell_name: "Swirl",
        mechanic_type: "avoidable",
        boss_encounter_id: encounter.wow_encounter_id,
        difficulty_id: 16,
        threshold: %{"max_hits" => 2}
      })

    insert_player_info!(encounter, "Player-One", "One")

    insert_damage_taken!(encounter, "Player-One", "Creature-A", 101, 300, 1)
    insert_damage_taken!(encounter, "Player-One", "Creature-B", 101, 700, 2)
    insert_damage_taken!(encounter, "Player-One", "Creature-C", 202, 900, 9)

    assert {:ok, %{deleted: 0, inserted: 1}} = FactFailure.rebuild_for_encounter(encounter.id)

    player = Repo.get_by!(DimPlayer, player_guid: "Player-One")

    assert %FactFailure{failure_count: 3, total_damage: 1_000} =
             Repo.get_by!(FactFailure,
               encounter_dim_id: encounter.id,
               player_dim_id: player.id,
               criterion_dim_id: criterion.id
             )
  end

  test "rebuild_for_encounter snapshots ruleset and build context on facts", %{
    ruleset: ruleset,
    encounter: encounter
  } do
    criterion =
      insert_criteria!(ruleset, %{
        spell_id: 111,
        spell_name: "Build Scoped Swirl",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0}
      })

    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", "Creature-A", 111, 100, 1)

    assert {:ok, %{inserted: 1}} = FactFailure.rebuild_for_encounter(encounter.id)

    assert %FactFailure{
             ruleset_id: ruleset_id,
             ruleset_version: ruleset_version,
             product: "wow",
             channel: "retail",
             build_version: "11.2.0.99999",
             build_key: "11.2.0",
             derivation_version: derivation_version,
             rebuilt_at: %DateTime{} = rebuilt_at
           } =
             Repo.get_by!(FactFailure,
               encounter_dim_id: encounter.id,
               criterion_dim_id: criterion.id
             )

    assert ruleset_id == ruleset.id
    assert ruleset_version == ruleset.version
    assert derivation_version == Derivation.current_version()
    assert DateTime.compare(rebuilt_at, DateTime.utc_now()) in [:lt, :eq]
  end

  test "rebuild_for_encounter preserves criteria specificity and difficulty inheritance", %{
    ruleset: ruleset,
    encounter: encounter
  } do
    global =
      insert_criteria!(ruleset, %{
        spell_id: 303,
        spell_name: "Global Swirl",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0}
      })

    heroic =
      insert_criteria!(ruleset, %{
        spell_id: 303,
        spell_name: "Heroic Swirl",
        mechanic_type: "avoidable",
        boss_encounter_id: encounter.wow_encounter_id,
        difficulty_id: 15,
        threshold: %{"max_hits" => 0}
      })

    mythic =
      insert_criteria!(ruleset, %{
        spell_id: 303,
        spell_name: "Mythic Swirl",
        mechanic_type: "avoidable",
        boss_encounter_id: encounter.wow_encounter_id,
        difficulty_id: 16,
        threshold: %{"max_hits" => 0}
      })

    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", "Creature-A", 303, 500, 1)

    assert {:ok, %{inserted: 1}} = FactFailure.rebuild_for_encounter(encounter.id)

    assert Repo.get_by(FactFailure, criterion_dim_id: mythic.id)
    refute Repo.get_by(FactFailure, criterion_dim_id: heroic.id)
    refute Repo.get_by(FactFailure, criterion_dim_id: global.id)
  end

  test "rebuild_for_encounter maps missed interrupts to the raid sentinel", %{
    ruleset: ruleset,
    encounter: encounter
  } do
    criterion =
      insert_criteria!(ruleset, %{
        spell_id: 404,
        spell_name: "Shadow Volley",
        mechanic_type: "interrupt",
        boss_encounter_id: encounter.wow_encounter_id,
        threshold: %{"must_interrupt" => true}
      })

    insert_interrupt_opportunity!(encounter, "Creature-A", 404, 1_000, false)
    insert_interrupt_opportunity!(encounter, "Creature-B", 404, 2_000, false)
    insert_interrupt_opportunity!(encounter, "Creature-C", 404, 3_000, true)

    assert {:ok, %{inserted: 1}} = FactFailure.rebuild_for_encounter(encounter.id)

    raid = Repo.get_by!(DimPlayer, player_guid: "__RAID__")

    assert %FactFailure{failure_count: 2, total_damage: 0} =
             Repo.get_by!(FactFailure,
               encounter_dim_id: encounter.id,
               player_dim_id: raid.id,
               criterion_dim_id: criterion.id
             )
  end

  test "rebuild_for_encounter attributes targeted cone failures to the assigned target", %{
    ruleset: ruleset,
    encounter: encounter
  } do
    criterion =
      insert_criteria!(ruleset, %{
        spell_id: 1_244_221,
        spell_name: "Dread Breath",
        mechanic_type: "targeted_cone",
        boss_encounter_id: encounter.wow_encounter_id,
        threshold: %{
          "target_marker_spell_id" => 1_255_612,
          "impact_spell_ids" => [1_244_225],
          "hit_debuff_spell_ids" => [1_255_979],
          "max_safe_hit_count" => 2,
          "target_role_policy" => "any",
          "allowed_collateral_roles" => ["tank"],
          "position_evidence" => "optional"
        }
      })

    insert_player_info!(encounter, "Player-Aimer", "Aimer")
    insert_player_info!(encounter, "Player-Dps-One", "Dps One")
    insert_player_info!(encounter, "Player-Dps-Two", "Dps Two")
    insert_player_info!(encounter, "Player-Dps-Three", "Dps Three")

    insert_debuff_application!(encounter, "Player-Aimer", 1_255_612, 1_000)
    insert_damage_taken_event!(encounter, "Player-Dps-One", 1_244_225, 8_000, 100_000)
    insert_damage_taken_event!(encounter, "Player-Dps-Two", 1_244_225, 8_100, 120_000)
    insert_damage_taken_event!(encounter, "Player-Dps-Three", 1_244_225, 8_200, 130_000)
    insert_debuff_application!(encounter, "Player-Dps-One", 1_255_979, 8_200)

    assert {:ok, %{inserted: 1}} = FactFailure.rebuild_for_encounter(encounter.id)

    aimer = Repo.get_by!(DimPlayer, player_guid: "Player-Aimer")

    assert %FactFailure{failure_count: 1, total_damage: 350_000} =
             Repo.get_by!(FactFailure,
               encounter_dim_id: encounter.id,
               player_dim_id: aimer.id,
               criterion_dim_id: criterion.id
             )

    refute Repo.get_by(FactFailure,
             encounter_dim_id: encounter.id,
             criterion_dim_id: criterion.id,
             player_dim_id: Repo.get_by!(DimPlayer, player_guid: "Player-Dps-One").id
           )
  end

  test "rebuild_for_encounter replaces stale facts only for the requested encounter", %{
    ruleset: ruleset,
    encounter: encounter,
    other_encounter: other_encounter
  } do
    criterion =
      insert_criteria!(ruleset, %{
        spell_id: 505,
        spell_name: "Bad",
        mechanic_type: "avoidable",
        boss_encounter_id: encounter.wow_encounter_id,
        threshold: %{"max_hits" => 0}
      })

    other_criterion =
      insert_criteria!(ruleset, %{
        spell_id: 606,
        spell_name: "Other Bad",
        mechanic_type: "avoidable",
        boss_encounter_id: other_encounter.wow_encounter_id,
        threshold: %{"max_hits" => 0}
      })

    insert_player_info!(encounter, "Player-One", "One")
    insert_player_info!(other_encounter, "Player-Two", "Two")

    insert_damage_taken!(encounter, "Player-One", "Creature-A", 505, 100, 1)
    insert_damage_taken!(other_encounter, "Player-Two", "Creature-A", 606, 200, 1)

    assert {:ok, %{inserted: 1}} = FactFailure.rebuild_for_encounter(encounter.id)
    assert {:ok, %{inserted: 1}} = FactFailure.rebuild_for_encounter(other_encounter.id)

    player = Repo.get_by!(DimPlayer, player_guid: "Player-One")
    other_player = Repo.get_by!(DimPlayer, player_guid: "Player-Two")

    assert %FactFailure{} =
             Repo.get_by!(FactFailure,
               encounter_dim_id: encounter.id,
               player_dim_id: player.id,
               criterion_dim_id: criterion.id
             )

    assert %FactFailure{} =
             Repo.get_by!(FactFailure,
               encounter_dim_id: other_encounter.id,
               player_dim_id: other_player.id,
               criterion_dim_id: other_criterion.id
             )

    criterion
    |> DimMechanicCriterion.changeset(%{threshold: %{"max_hits" => 9}})
    |> Repo.update!()

    assert {:ok, %{deleted: 1, inserted: 0}} = FactFailure.rebuild_for_encounter(encounter.id)

    refute Repo.get_by(FactFailure,
             encounter_dim_id: encounter.id,
             player_dim_id: player.id,
             criterion_dim_id: criterion.id
           )

    assert Repo.get_by(FactFailure,
             encounter_dim_id: other_encounter.id,
             player_dim_id: other_player.id,
             criterion_dim_id: other_criterion.id
           )
  end

  test "rebuild_for_encounter accepts explicit active ruleset selection", %{
    ruleset: ruleset,
    encounter: encounter
  } do
    criterion =
      insert_criteria!(ruleset, %{
        spell_id: 707,
        spell_name: "Active Bad",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0}
      })

    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", "Creature-A", 707, 100, 1)

    assert {:ok, %{inserted: 1}} =
             FactFailure.rebuild_for_encounter(encounter.id, ruleset: :active)

    assert Repo.get_by(FactFailure,
             encounter_dim_id: encounter.id,
             criterion_dim_id: criterion.id
           )
  end

  test "rebuild_for_encounter accepts explicit ruleset id and keeps other rulesets intact", %{
    ruleset: active_ruleset,
    encounter: encounter
  } do
    explicit_ruleset = insert_ruleset!("Explicit Ruleset", "draft", build_key: "11.2.5")

    active_criterion =
      insert_criteria!(active_ruleset, %{
        spell_id: 808,
        spell_name: "Active Rule",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0}
      })

    explicit_criterion =
      insert_criteria!(explicit_ruleset, %{
        spell_id: 808,
        spell_name: "Explicit Rule",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0}
      })

    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", "Creature-A", 808, 100, 1)

    assert {:ok, %{inserted: 1}} =
             FactFailure.rebuild_for_encounter(encounter.id, ruleset_id: explicit_ruleset.id)

    assert Repo.get_by(FactFailure,
             encounter_dim_id: encounter.id,
             criterion_dim_id: explicit_criterion.id
           )

    explicit_fact =
      Repo.get_by!(FactFailure,
        encounter_dim_id: encounter.id,
        criterion_dim_id: explicit_criterion.id
      )

    assert explicit_fact.ruleset_id == explicit_ruleset.id
    assert explicit_fact.build_key == "11.2.5"

    refute Repo.get_by(FactFailure,
             encounter_dim_id: encounter.id,
             criterion_dim_id: active_criterion.id
           )

    assert {:ok, %{inserted: 1}} = FactFailure.rebuild_for_encounter(encounter.id)

    assert Repo.get_by(FactFailure,
             encounter_dim_id: encounter.id,
             criterion_dim_id: explicit_criterion.id
           )

    assert Repo.get_by(FactFailure,
             encounter_dim_id: encounter.id,
             criterion_dim_id: active_criterion.id
           )
  end

  test "rebuild_for_encounter uses promoted seeded local rules", %{encounter: encounter} do
    {:ok, %{ruleset: seeded_ruleset}} = Rules.seed_initial_rules()
    {:ok, active_ruleset} = Rules.activate_ruleset(seeded_ruleset)
    {:ok, %{criteria: promoted_criteria}} = Rules.promote_ruleset_to_gold(active_ruleset)

    criterion = Enum.find(promoted_criteria, &(&1.spell_id == 1_214_081))

    insert_player_info!(encounter, "Player-One", "One")
    insert_damage_taken!(encounter, "Player-One", "Creature-A", 1_214_081, 100, 1)

    assert {:ok, %{inserted: 1}} = FactFailure.rebuild_for_encounter(encounter.id)

    assert Repo.get_by(FactFailure,
             encounter_dim_id: encounter.id,
             criterion_dim_id: criterion.id
           )
  end

  defp insert_dim_encounter!(wow_encounter_id, difficulty_id) do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      wow_encounter_id: wow_encounter_id,
      name: "Test Boss",
      difficulty_id: difficulty_id,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance"
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

  defp insert_interrupt_opportunity!(
         encounter,
         target_npc_guid,
         interrupted_spell_id,
         opportunity_ms_into_fight,
         success
       ) do
    %InterruptOpportunity{}
    |> InterruptOpportunity.changeset(%{
      encounter_dim_id: encounter.id,
      target_npc_guid: target_npc_guid,
      interrupted_spell_id: interrupted_spell_id,
      opportunity_ms_into_fight: opportunity_ms_into_fight,
      success: success,
      interrupter_guid: if(success, do: "Player-One"),
      interrupting_spell_id: if(success, do: 1766)
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken_event!(
         encounter,
         target_guid,
         spell_id,
         occurred_at_ms_into_fight,
         amount
       ) do
    %DamageTakenEvent{}
    |> DamageTakenEvent.changeset(%{
      encounter_dim_id: encounter.id,
      combat_log_event_index: System.unique_integer([:positive]),
      event_type: "SPELL_DAMAGE",
      occurred_at_ms_into_fight: occurred_at_ms_into_fight,
      target_guid: target_guid,
      source_guid: "Creature-Boss",
      source_is_npc: true,
      spell_id: spell_id,
      spell_name: "Dread Breath",
      amount: amount,
      overkill: 0
    })
    |> Repo.insert!()
  end

  defp insert_debuff_application!(encounter, target_guid, spell_id, applied_at_ms_into_fight) do
    %DebuffApplication{}
    |> DebuffApplication.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: target_guid,
      source_guid: "Creature-Boss",
      spell_id: spell_id,
      applied_at_ms_into_fight: applied_at_ms_into_fight,
      stack_count: 1
    })
    |> Repo.insert!()
  end

  defp insert_ruleset!(name, status, attrs \\ []) do
    %Ruleset{}
    |> Ruleset.changeset(
      Map.merge(
        %{
          name: name,
          status: status,
          product: "wow",
          channel: "retail",
          build_version: "11.2.0.99999",
          build_key: "11.2.0"
        },
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end

  defp insert_criteria!(%Ruleset{} = ruleset, attrs) do
    attrs =
      Map.merge(
        %{
          source_rule_id: System.unique_integer([:positive]),
          ruleset_id: ruleset.id,
          ruleset_version: ruleset.version,
          product: ruleset.product,
          channel: ruleset.channel,
          build_version: ruleset.build_version,
          build_key: ruleset.build_key
        },
        attrs
      )

    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(attrs)
    |> Repo.insert!()
  end
end
