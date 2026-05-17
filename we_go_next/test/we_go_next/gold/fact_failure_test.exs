defmodule WeGoNext.Gold.FactFailureTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo
  alias WeGoNext.Silver.{DamageTaken, InterruptOpportunity, PlayerInfo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    encounter = insert_dim_encounter!("boss-one", 16)
    other_encounter = insert_dim_encounter!("boss-two", 16)

    {:ok, encounter: encounter, other_encounter: other_encounter}
  end

  test "rebuild_for_encounter builds avoidable facts from aggregated silver damage", %{
    encounter: encounter
  } do
    criterion =
      insert_criteria!(%{
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

  test "rebuild_for_encounter preserves criteria specificity and difficulty inheritance", %{
    encounter: encounter
  } do
    global =
      insert_criteria!(%{
        spell_id: 303,
        spell_name: "Global Swirl",
        mechanic_type: "avoidable",
        threshold: %{"max_hits" => 0}
      })

    heroic =
      insert_criteria!(%{
        spell_id: 303,
        spell_name: "Heroic Swirl",
        mechanic_type: "avoidable",
        boss_encounter_id: encounter.wow_encounter_id,
        difficulty_id: 15,
        threshold: %{"max_hits" => 0}
      })

    mythic =
      insert_criteria!(%{
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
    encounter: encounter
  } do
    criterion =
      insert_criteria!(%{
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

  test "rebuild_for_encounter replaces stale facts only for the requested encounter", %{
    encounter: encounter,
    other_encounter: other_encounter
  } do
    criterion =
      insert_criteria!(%{
        spell_id: 505,
        spell_name: "Bad",
        mechanic_type: "avoidable",
        boss_encounter_id: encounter.wow_encounter_id,
        threshold: %{"max_hits" => 0}
      })

    other_criterion =
      insert_criteria!(%{
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

  defp insert_criteria!(attrs) do
    attrs =
      Map.merge(
        %{
          source_rule_id: System.unique_integer([:positive]),
          ruleset_id: 1,
          ruleset_version: 1
        },
        attrs
      )

    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(attrs)
    |> Repo.insert!()
  end
end
