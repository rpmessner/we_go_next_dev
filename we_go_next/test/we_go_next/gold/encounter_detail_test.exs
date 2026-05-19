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
  alias WeGoNext.Silver.{DamageDone, DamageTaken, Death, InterruptOpportunity, PlayerInfo}

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
                spell_coverage: [required_spell, raw_spell],
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

    assert raw_spell.spell_id == 888
    assert raw_spell.required_failure_count == nil

    assert player.interrupter_guid == "Player-Kicker"
    assert player.player_name == "Kicker"
    assert player.class_id == 4
    assert player.total_interrupts == 1
    assert player.interrupted_spell_count == 1
    assert [%{spell_id: 777, count: 1}] = player.by_spell
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
end
