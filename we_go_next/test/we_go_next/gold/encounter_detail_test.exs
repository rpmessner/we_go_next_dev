defmodule WeGoNext.Gold.EncounterDetailTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{
    DimEncounter,
    DimMechanicCriterion,
    DimPlayer,
    EncounterDetail,
    FactFailure
  }

  alias WeGoNext.Repo

  alias WeGoNext.Silver.{
    DamageDone,
    DamageTaken,
    DamageTakenEvent,
    Death,
    DebuffApplication,
    DefensiveBuffWindow,
    InterruptOpportunity,
    PlayerInfo
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "get returns death recap rows joined to encounter-scoped player info" do
    encounter = insert_dim_encounter!()

    insert_player_info!(encounter, %{
      player_guid: "Player-Victim",
      player_name: "Victim",
      class_id: 9,
      spec_id: 266,
      detected_role: "dps"
    })

    insert_death!(encounter, %{
      target_guid: "Player-Victim",
      died_at_ms_into_fight: 12_000,
      killing_blow_spell_id: 123,
      killing_blow_source_guid: "Creature-Boss",
      damage_recap: [
        %{
          "ms_into_fight" => 11_900,
          "spell_id" => 123,
          "spell_name" => "Bad Blast",
          "source_guid" => "Creature-Boss",
          "source_name" => "Test Boss",
          "amount" => 42_000,
          "overkill" => 4_200
        },
        %{
          "ms_into_fight" => 10_500,
          "spell_id" => 456,
          "spell_name" => "Earlier Bad",
          "source_guid" => "Creature-Add",
          "source_name" => "Test Add",
          "amount" => 21_000,
          "overkill" => 0
        }
      ]
    })

    assert {:ok, %{deaths: [death]}} = EncounterDetail.get(encounter.id)

    assert death.target_guid == "Player-Victim"
    assert death.player_name == "Victim"
    assert death.class_id == 9
    assert death.spec_id == 266
    assert death.detected_role == "dps"
    assert death.died_at_ms_into_fight == 12_000
    assert death.killing_blow_spell_id == 123
    assert death.killing_blow_source_guid == "Creature-Boss"
    assert death.encounter_name == "Test Boss"
    assert death.killing_blow["spell_name"] == "Bad Blast"
    assert Enum.map(death.damage_recap, & &1["amount"]) == [42_000, 21_000]
  end

  test "get keeps deaths even when player info is missing" do
    encounter = insert_dim_encounter!()

    insert_death!(encounter, %{
      target_guid: "Player-Missing",
      died_at_ms_into_fight: 4_000,
      damage_recap: []
    })

    assert {:ok, %{deaths: [death]}} = EncounterDetail.get(encounter.id)

    assert death.target_guid == "Player-Missing"
    assert death.player_name == nil
    assert death.class_id == nil
    assert death.killing_blow == nil
  end

  test "get returns interrupt coverage grouped by spell and interrupter" do
    encounter = insert_dim_encounter!()

    insert_player_info!(encounter, %{
      player_guid: "Player-Kicker",
      player_name: "Kicker",
      class_id: 4,
      spec_id: 260,
      detected_role: "dps"
    })

    insert_interrupt_opportunity!(encounter, %{
      target_npc_guid: "Creature-Caster",
      interrupted_spell_id: 777,
      opportunity_ms_into_fight: 1_000,
      success: true,
      interrupter_guid: "Player-Kicker",
      interrupting_spell_id: 1766
    })

    insert_interrupt_opportunity!(encounter, %{
      target_npc_guid: "Creature-Caster",
      interrupted_spell_id: 777,
      opportunity_ms_into_fight: 2_000,
      success: false
    })

    insert_interrupt_opportunity!(encounter, %{
      target_npc_guid: "Creature-Add",
      interrupted_spell_id: 888,
      opportunity_ms_into_fight: 3_000,
      success: false
    })

    insert_interrupt_failure!(encounter, 777, "Must Kick", 1)

    assert {:ok,
            %{
              interrupt_coverage: %{
                spell_coverage: [required_spell],
                player_contributions: [player]
              }
            }} = EncounterDetail.get(encounter.id)

    assert required_spell.spell_id == 777
    assert required_spell.spell_name == "Must Kick"
    assert required_spell.total_opportunities == 2
    assert required_spell.successful_interrupts == 1
    assert required_spell.missed_casts == 1
    assert required_spell.target_count == 1
    assert required_spell.required_failure_count == 1

    assert player.interrupter_guid == "Player-Kicker"
    assert player.player_name == "Kicker"
    assert player.class_id == 4
    assert player.total_interrupts == 1
    assert player.interrupted_spell_count == 1
    assert [%{spell_id: 777, count: 1}] = player.by_spell
  end

  test "get returns failure preview grouped by mechanic and player" do
    encounter = insert_dim_encounter!()

    insert_player_info!(encounter, %{
      player_guid: "Player-One",
      player_name: "One",
      class_id: 9,
      spec_id: 266,
      detected_role: "dps"
    })

    insert_player_info!(encounter, %{
      player_guid: "Player-Two",
      player_name: "Two",
      class_id: 1,
      spec_id: 73,
      detected_role: "tank"
    })

    criterion = insert_failure_criterion!(901, "Ravenous Dive")

    insert_player_failure_with_criterion!(
      encounter,
      criterion,
      "Player-One",
      "One",
      2,
      45_000
    )

    insert_player_failure_with_criterion!(
      encounter,
      criterion,
      "Player-Two",
      "Two",
      1,
      30_000
    )

    assert {:ok, %{failure_preview: preview}} = EncounterDetail.get(encounter.id)

    assert preview.counts == %{mechanics: 1, players: 2, failures: 3, damage: 75_000}
    assert preview.diagnostics == []

    assert [
             %{
               spell_id: 901,
               spell_name: "Ravenous Dive",
               mechanic_type: "avoidable",
               failure_count: 3,
               total_damage: 75_000,
               player_count: 2,
               players: players
             }
           ] = preview.mechanics

    assert Enum.map(players, &{&1.player_name, &1.failure_count, &1.total_damage}) == [
             {"One", 2, 45_000},
             {"Two", 1, 30_000}
           ]
  end

  test "get enriches targeted cone failures with target and collateral context" do
    encounter = insert_dim_encounter!()

    insert_player_info!(encounter, %{
      player_guid: "Player-Aimer",
      player_name: "Aimer",
      detected_role: "dps"
    })

    insert_player_info!(encounter, %{
      player_guid: "Player-One",
      player_name: "One",
      detected_role: "dps"
    })

    insert_player_info!(encounter, %{
      player_guid: "Player-Two",
      player_name: "Two",
      detected_role: "dps"
    })

    insert_player_info!(encounter, %{
      player_guid: "Player-Three",
      player_name: "Three",
      detected_role: "dps"
    })

    criterion =
      insert_failure_criterion!(
        1_244_221,
        "Dread Breath",
        "targeted_cone",
        %{
          "target_marker_spell_id" => 1_255_612,
          "impact_spell_ids" => [1_244_225],
          "hit_debuff_spell_ids" => [1_255_979],
          "max_safe_hit_count" => 2,
          "target_role_policy" => "any",
          "allowed_collateral_roles" => ["tank"],
          "position_evidence" => "optional"
        }
      )

    insert_player_failure_with_criterion!(
      encounter,
      criterion,
      "Player-Aimer",
      "Aimer",
      1,
      90_000
    )

    insert_debuff_application!(encounter, "Player-Aimer", 1_255_612, 1_000)

    insert_damage_taken_event!(encounter, %{
      target_guid: "Player-One",
      spell_id: 1_244_225,
      amount: 40_000,
      occurred_at_ms_into_fight: 8_000
    })

    insert_damage_taken_event!(encounter, %{
      target_guid: "Player-Two",
      spell_id: 1_244_225,
      amount: 50_000,
      occurred_at_ms_into_fight: 8_100
    })

    insert_damage_taken_event!(encounter, %{
      target_guid: "Player-Three",
      spell_id: 1_244_225,
      amount: 60_000,
      occurred_at_ms_into_fight: 8_200
    })

    insert_debuff_application!(encounter, "Player-One", 1_255_979, 8_200)

    assert {:ok, %{failure_preview: %{mechanics: [mechanic]}}} = EncounterDetail.get(encounter.id)

    assert mechanic.mechanic_type == "targeted_cone"

    assert [
             %{
               target_guid: "Player-Aimer",
               target_name: "Aimer",
               hit_count: 3,
               collateral_count: 3,
               confidence: "medium",
               hit_players: hit_players
             }
           ] = mechanic.targeted_cone_events

    assert Enum.map(hit_players, & &1["player_name"]) == ["Three", "Two", "One"]
  end

  test "get returns selected personal pull summary from configured character name" do
    encounter = insert_dim_encounter!()

    insert_player_info!(encounter, %{
      player_guid: "Player-Main",
      player_name: "Mittwoch",
      class_id: 9,
      spec_id: 266,
      detected_role: "dps"
    })

    insert_player_info!(encounter, %{
      player_guid: "Player-Other",
      player_name: "Other",
      class_id: 1,
      spec_id: 73,
      detected_role: "tank"
    })

    insert_damage_done!(encounter, "Player-Main", 501, 3_000, 3, 1_500)
    insert_damage_taken!(encounter, "Player-Main", 601, 900, 2, 600)

    insert_interrupt_opportunity!(encounter, %{
      target_npc_guid: "Creature-Caster",
      interrupted_spell_id: 777,
      opportunity_ms_into_fight: 1_000,
      success: true,
      interrupter_guid: "Player-Main",
      interrupting_spell_id: 1766
    })

    insert_death!(encounter, %{
      target_guid: "Player-Main",
      died_at_ms_into_fight: 90_000,
      damage_recap: []
    })

    insert_player_failure!(encounter, "Player-Main", "Mittwoch", 501, "Bad", 2, 700)

    assert {:ok,
            %{
              personal_pull_summary: %{
                selected_player_guid: "Player-Main",
                players: players
              }
            }} = EncounterDetail.get(encounter.id, character_name: "mittwoch-wyrmrestaccord")

    main = Enum.find(players, &(&1.player_guid == "Player-Main"))

    assert main.player_name == "Mittwoch"
    assert main.damage_done == 3_000
    assert main.damage_done_hits == 3
    assert main.max_damage_done_hit == 1_500
    assert main.damage_taken == 900
    assert main.damage_taken_hits == 2
    assert main.max_damage_taken_hit == 600
    assert main.successful_interrupts == 1
    assert main.interrupted_spell_count == 1
    assert main.death_count == 1
    assert main.first_death_ms == 90_000
    assert main.mechanic_failures == 2
    assert main.failure_damage == 700
    assert main.failed_mechanic_count == 1
  end

  test "get returns same-boss player performance history from real pull rows" do
    previous =
      insert_dim_encounter!(%{
        start_time: ~U[2026-05-01 20:00:00Z],
        success: false,
        fight_time_ms: 240_000
      })

    current =
      insert_dim_encounter!(%{
        start_time: ~U[2026-05-01 20:08:00Z],
        success: true,
        fight_time_ms: 300_000
      })

    other_boss =
      insert_dim_encounter!(%{
        wow_encounter_id: "other-boss",
        name: "Other Boss",
        start_time: ~U[2026-05-01 20:15:00Z]
      })

    for encounter <- [previous, current, other_boss] do
      insert_player_info!(encounter, %{
        player_guid: "Player-Main",
        player_name: "Mittwoch",
        class_id: 9,
        spec_id: 266,
        detected_role: "dps"
      })
    end

    criterion = insert_failure_criterion!(901, "Ravenous Dive")

    insert_damage_taken!(previous, "Player-Main", 601, 4_000, 4, 1_500)
    insert_damage_done!(previous, "Player-Main", 501, 11_000, 11, 2_000)

    insert_player_failure_with_criterion!(
      previous,
      criterion,
      "Player-Main",
      "Mittwoch",
      3,
      3_000
    )

    insert_death!(previous, %{target_guid: "Player-Main", died_at_ms_into_fight: 120_000})

    insert_damage_taken!(current, "Player-Main", 601, 1_000, 1, 1_000)
    insert_damage_done!(current, "Player-Main", 501, 15_000, 15, 3_000)
    insert_player_failure_with_criterion!(current, criterion, "Player-Main", "Mittwoch", 1, 1_000)

    insert_interrupt_opportunity!(current, %{
      target_npc_guid: "Creature-Caster",
      interrupted_spell_id: 777,
      opportunity_ms_into_fight: 1_000,
      success: true,
      interrupter_guid: "Player-Main",
      interrupting_spell_id: 1766
    })

    insert_damage_taken!(other_boss, "Player-Main", 601, 99_000, 9, 20_000)

    assert {:ok, %{personal_pull_summary: %{players: [player]}}} =
             EncounterDetail.get(current.id, character_name: "mittwoch")

    assert %{
             summary: %{
               pull_count: 2,
               kill_count: 1,
               wipe_count: 1,
               total_mechanic_failures: 4,
               total_deaths: 1,
               total_damage_taken: 5_000,
               avg_failures_per_pull: 2.0,
               avg_damage_taken: 2_500.0,
               current_failure_delta: -2,
               current_death_delta: -1,
               current_damage_taken_delta: -3_000
             },
             pulls: [current_pull, previous_pull]
           } = player.performance

    assert current_pull.current == true
    assert current_pull.encounter_dim_id == current.id
    assert current_pull.mechanic_failures == 1
    assert current_pull.death_count == 0
    assert current_pull.damage_taken == 1_000
    assert current_pull.successful_interrupts == 1

    assert previous_pull.current == false
    assert previous_pull.encounter_dim_id == previous.id
    assert previous_pull.mechanic_failures == 3
    assert previous_pull.death_count == 1
    assert previous_pull.damage_taken == 4_000
  end

  test "get returns defensive coverage around failure damage and deaths" do
    encounter = insert_dim_encounter!()

    insert_player_info!(encounter, %{
      player_guid: "Player-Main",
      player_name: "Mittwoch",
      class_id: 9,
      spec_id: 266,
      detected_role: "dps"
    })

    criterion = insert_failure_criterion!(901, "Ravenous Dive")

    insert_player_failure_with_criterion!(
      encounter,
      criterion,
      "Player-Main",
      "Mittwoch",
      1,
      45_000
    )

    insert_damage_taken_event!(encounter, %{
      target_guid: "Player-Main",
      spell_id: 901,
      spell_name: "Ravenous Dive",
      amount: 45_000,
      occurred_at_ms_into_fight: 10_000
    })

    insert_death!(encounter, %{
      target_guid: "Player-Main",
      died_at_ms_into_fight: 12_000,
      killing_blow_spell_id: 902
    })

    insert_defensive_window!(encounter, %{
      target_guid: "Player-Main",
      spell_id: 104_773,
      spell_name: "Unending Resolve",
      category: "personal",
      started_at_ms_into_fight: 9_000,
      ended_at_ms_into_fight: 11_000,
      duration_ms: 2_000
    })

    assert {:ok, %{personal_pull_summary: %{players: [player]}}} =
             EncounterDetail.get(encounter.id, character_name: "mittwoch")

    assert %{
             summary: %{
               windows_count: 1,
               dangerous_events_count: 2,
               covered_events_count: 1,
               uncovered_events_count: 1,
               death_events_count: 1,
               covered_death_count: 0
             },
             events: [failure_event, death_event],
             windows: [window]
           } = player.defensive_analysis

    assert window.spell_name == "Unending Resolve"
    assert failure_event.type == :failure_damage
    assert failure_event.covered == true
    assert Enum.map(failure_event.active_defensives, & &1.spell_name) == ["Unending Resolve"]
    assert death_event.type == :death
    assert death_event.covered == false
    assert death_event.active_defensives == []
  end

  defp insert_dim_encounter!(attrs \\ %{}) do
    %DimEncounter{}
    |> DimEncounter.changeset(
      Map.merge(
        %{
          wow_encounter_id: "test-boss",
          name: "Test Boss",
          difficulty_id: 16,
          difficulty_name: "Mythic",
          group_size: 20,
          instance_id: "test-instance"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp insert_player_info!(%DimEncounter{} = encounter, attrs) do
    attrs =
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          detected_role: "unknown"
        },
        attrs
      )

    %PlayerInfo{}
    |> PlayerInfo.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_death!(%DimEncounter{} = encounter, attrs) do
    attrs =
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          target_guid: "Player-One",
          died_at_ms_into_fight: 1_000,
          damage_recap: []
        },
        attrs
      )

    %Death{}
    |> Death.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_damage_done!(
         %DimEncounter{} = encounter,
         source_guid,
         spell_id,
         total_amount,
         hit_count,
         max_hit
       ) do
    %DamageDone{}
    |> DamageDone.changeset(%{
      encounter_dim_id: encounter.id,
      source_guid: source_guid,
      target_guid: "Creature-Boss",
      spell_id: spell_id,
      total_amount: total_amount,
      hit_count: hit_count,
      max_hit: max_hit
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken!(
         %DimEncounter{} = encounter,
         target_guid,
         spell_id,
         total_amount,
         hit_count,
         max_hit
       ) do
    %DamageTaken{}
    |> DamageTaken.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: target_guid,
      source_guid: "Creature-Boss",
      spell_id: spell_id,
      total_amount: total_amount,
      hit_count: hit_count,
      max_hit: max_hit,
      overkill_total: 0,
      source_is_npc: true
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken_event!(%DimEncounter{} = encounter, attrs) do
    attrs =
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          combat_log_event_index: System.unique_integer([:positive]),
          event_type: "SPELL_DAMAGE",
          occurred_at_ms_into_fight: 1_000,
          target_guid: "Player-One",
          source_guid: "Creature-Boss",
          source_is_npc: true,
          spell_id: 101,
          spell_name: "Bad",
          amount: 100,
          overkill: 0
        },
        attrs
      )

    %DamageTakenEvent{}
    |> DamageTakenEvent.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_defensive_window!(%DimEncounter{} = encounter, attrs) do
    attrs =
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          target_guid: "Player-One",
          source_guid: "Player-One",
          spell_id: 104_773,
          spell_name: "Unending Resolve",
          category: "personal",
          started_at_ms_into_fight: 1_000
        },
        attrs
      )

    %DefensiveBuffWindow{}
    |> DefensiveBuffWindow.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_interrupt_opportunity!(%DimEncounter{} = encounter, attrs) do
    attrs =
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          target_npc_guid: "Creature-One",
          interrupted_spell_id: 777,
          opportunity_ms_into_fight: System.unique_integer([:positive]),
          success: false
        },
        attrs
      )

    %InterruptOpportunity{}
    |> InterruptOpportunity.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_interrupt_failure!(%DimEncounter{} = encounter, spell_id, spell_name, failure_count) do
    player =
      %DimPlayer{}
      |> DimPlayer.changeset(%{
        player_guid: "RAID",
        player_name: "Raid"
      })
      |> Repo.insert!()

    criterion =
      %DimMechanicCriterion{}
      |> DimMechanicCriterion.changeset(%{
        source_rule_id: System.unique_integer([:positive]),
        ruleset_id: System.unique_integer([:positive]),
        ruleset_version: 1,
        spell_id: spell_id,
        spell_name: spell_name,
        mechanic_type: "interrupt",
        threshold: %{"must_interrupt" => true}
      })
      |> Repo.insert!()

    %FactFailure{}
    |> FactFailure.changeset(%{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      ruleset_id: criterion.ruleset_id,
      ruleset_version: criterion.ruleset_version,
      product: criterion.product,
      channel: criterion.channel,
      build_version: criterion.build_version,
      build_key: criterion.build_key,
      failure_count: failure_count,
      total_damage: 0
    })
    |> Repo.insert!()
  end

  defp insert_player_failure!(
         %DimEncounter{} = encounter,
         player_guid,
         player_name,
         spell_id,
         spell_name,
         failure_count,
         total_damage
       ) do
    player =
      %DimPlayer{}
      |> DimPlayer.changeset(%{
        player_guid: player_guid,
        player_name: player_name
      })
      |> Repo.insert!()

    criterion =
      %DimMechanicCriterion{}
      |> DimMechanicCriterion.changeset(%{
        source_rule_id: System.unique_integer([:positive]),
        ruleset_id: System.unique_integer([:positive]),
        ruleset_version: 1,
        spell_id: spell_id,
        spell_name: spell_name,
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0}
      })
      |> Repo.insert!()

    %FactFailure{}
    |> FactFailure.changeset(%{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      ruleset_id: criterion.ruleset_id,
      ruleset_version: criterion.ruleset_version,
      product: criterion.product,
      channel: criterion.channel,
      build_version: criterion.build_version,
      build_key: criterion.build_key,
      failure_count: failure_count,
      total_damage: total_damage
    })
    |> Repo.insert!()
  end

  defp insert_failure_criterion!(
         spell_id,
         spell_name,
         mechanic_type \\ "avoidable",
         threshold \\ %{"max_hits" => 0}
       ) do
    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: System.unique_integer([:positive]),
      ruleset_version: 1,
      spell_id: spell_id,
      spell_name: spell_name,
      mechanic_type: mechanic_type,
      threshold: threshold
    })
    |> Repo.insert!()
  end

  defp insert_debuff_application!(
         %DimEncounter{} = encounter,
         target_guid,
         spell_id,
         applied_at_ms_into_fight
       ) do
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

  defp insert_player_failure_with_criterion!(
         %DimEncounter{} = encounter,
         %DimMechanicCriterion{} = criterion,
         player_guid,
         player_name,
         failure_count,
         total_damage
       ) do
    player = get_or_insert_dim_player!(player_guid, player_name)

    %FactFailure{}
    |> FactFailure.changeset(%{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      ruleset_id: criterion.ruleset_id,
      ruleset_version: criterion.ruleset_version,
      product: criterion.product,
      channel: criterion.channel,
      build_version: criterion.build_version,
      build_key: criterion.build_key,
      failure_count: failure_count,
      total_damage: total_damage
    })
    |> Repo.insert!()
  end

  defp get_or_insert_dim_player!(player_guid, player_name) do
    case Repo.get_by(DimPlayer, player_guid: player_guid) do
      %DimPlayer{} = player ->
        player

      nil ->
        %DimPlayer{}
        |> DimPlayer.changeset(%{
          player_guid: player_guid,
          player_name: player_name
        })
        |> Repo.insert!()
    end
  end
end
