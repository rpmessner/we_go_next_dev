defmodule WeGoNext.Gold.ObservedMechanicsTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{
    DimEncounter,
    DimMechanicCriterion,
    DimPlayer,
    FactFailure,
    ObservedMechanics
  }

  alias WeGoNext.Repo

  alias WeGoNext.Silver.{
    DamageTakenEvent,
    DebuffApplication,
    InterruptOpportunity
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "for_encounter returns observed damage enriched with catalog criteria and facts" do
    encounter = insert_encounter!("3180", "Lightblinded Vanguard", 16)

    insert_damage_taken_event!(encounter, %{
      combat_log_event_index: 1,
      target_guid: "Player-One",
      target_name: "One",
      spell_id: 1_248_652,
      spell_name: "Divine Toll",
      amount: 10_000,
      occurred_at_ms_into_fight: 12_000
    })

    insert_damage_taken_event!(encounter, %{
      combat_log_event_index: 2,
      target_guid: "Player-Two",
      target_name: "Two",
      spell_id: 1_248_652,
      spell_name: "Divine Toll",
      amount: 15_000,
      occurred_at_ms_into_fight: 18_000
    })

    criterion = insert_criterion!(1_248_652, "Divine Toll", encounter)
    player = insert_player!("Player-One", "One")
    insert_failure!(encounter, player, criterion, 2, 25_000)

    assert {:ok, %{mechanics: [row], counts: counts}} =
             ObservedMechanics.for_encounter(encounter.id)

    assert counts.observed_spells == 1
    assert counts.producing_failures == 1

    assert row.spell_id == 1_248_652
    assert row.spell_name == "Divine Toll"
    assert row.boss_name == "Lightblinded Vanguard"
    assert row.rule_status == :producing_failures
    assert row.diagnostics == []

    assert row.observed.damage_hits == 2
    assert row.observed.affected_players == 2
    assert row.observed.total_damage == 25_000
    assert row.observed.max_hit == 15_000
    assert row.observed.first_seen_ms == 12_000
    assert row.observed.last_seen_ms == 18_000

    assert row.catalog.mechanic_type == :avoidable
    assert row.catalog.track == true
    assert [%{criterion_dim_id: criterion_dim_id}] = row.criteria
    assert criterion_dim_id == criterion.id
    assert row.facts.failure_count == 2
    assert row.facts.total_damage == 25_000
    assert row.facts.failed_player_count == 1
  end

  test "for_encounter treats non-code-defined observations as raw combat-log events" do
    encounter = insert_encounter!("3306", "Chimaerus the Undreamt God", 16)

    insert_debuff_application!(encounter, %{
      spell_id: 555_555,
      target_guid: "Player-One",
      applied_at_ms_into_fight: 4_000,
      stack_count: 3
    })

    insert_interrupt_opportunity!(encounter, %{
      interrupted_spell_id: 1_249_017,
      opportunity_ms_into_fight: 7_000,
      success: false
    })

    assert {:ok, %{mechanics: mechanics, counts: counts}} =
             ObservedMechanics.for_encounter(encounter.id)

    assert counts.observed_spells == 2
    assert counts.catalog_context == 1
    assert counts.code_defined == 1
    assert counts.observed_only == 1

    raw_row = Enum.find(mechanics, &(&1.spell_id == 555_555))
    catalog_row = Enum.find(mechanics, &(&1.spell_id == 1_249_017))

    assert raw_row.spell_name == "Unknown Spell 555555"
    assert raw_row.rule_status == :observed_only
    assert raw_row.observed.debuff_applications == 1
    assert raw_row.observed.debuffed_players == 1
    assert raw_row.observed.max_stack_count == 3
    assert raw_row.catalog == nil

    assert catalog_row.spell_name == "Fearsome Cry"
    assert catalog_row.rule_status == :catalog_context
    assert catalog_row.catalog.track == false
    assert catalog_row.observed.interrupt_opportunities == 1
    assert catalog_row.observed.missed_interrupts == 1
  end

  test "for_encounter reports invalid and missing IDs" do
    assert {:error, :invalid_id} = ObservedMechanics.for_encounter("not-an-id")
    assert {:error, :not_found} = ObservedMechanics.for_encounter(999_999_999)
  end

  defp insert_encounter!(wow_encounter_id, name, difficulty_id) do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      wow_encounter_id: wow_encounter_id,
      name: name,
      difficulty_id: difficulty_id,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "fixture-instance"
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken_event!(%DimEncounter{} = encounter, attrs) do
    attrs =
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          event_type: "SPELL_DAMAGE",
          source_guid: "Creature-Boss",
          source_name: encounter.name,
          source_is_npc: true,
          spell_school: 2,
          overkill: 0
        },
        attrs
      )

    %DamageTakenEvent{}
    |> DamageTakenEvent.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_debuff_application!(%DimEncounter{} = encounter, attrs) do
    attrs =
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          source_guid: "Creature-Boss",
          duration_ms: nil
        },
        attrs
      )

    %DebuffApplication{}
    |> DebuffApplication.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_interrupt_opportunity!(%DimEncounter{} = encounter, attrs) do
    attrs =
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          target_npc_guid: "Creature-Caster"
        },
        attrs
      )

    %InterruptOpportunity{}
    |> InterruptOpportunity.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_criterion!(spell_id, spell_name, %DimEncounter{} = encounter) do
    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: System.unique_integer([:positive]),
      ruleset_version: 1,
      spell_id: spell_id,
      spell_name: spell_name,
      mechanic_type: "avoidable",
      boss_encounter_id: encounter.wow_encounter_id,
      boss_name: encounter.name,
      difficulty_id: encounter.difficulty_id,
      threshold: %{"max_hits" => 0},
      active: true
    })
    |> Repo.insert!()
  end

  defp insert_player!(guid, name) do
    %DimPlayer{}
    |> DimPlayer.changeset(%{player_guid: guid, player_name: name})
    |> Repo.insert!()
  end

  defp insert_failure!(
         %DimEncounter{} = encounter,
         %DimPlayer{} = player,
         criterion,
         count,
         damage
       ) do
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
      failure_count: count,
      total_damage: damage
    })
    |> Repo.insert!()
  end
end
