defmodule WeGoNextWeb.Features.FailuresTest do
  @moduledoc """
  End-to-end coverage for the gold-backed mechanic failures page.
  """
  use WeGoNextWeb.FeatureCase, async: false

  alias WeGoNext.Gold.{DimEncounter, FactFailure}
  alias WeGoNext.Rules
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo}

  feature "renders medallion-backed failures from the live catalog and silver rows", %{
    session: session
  } do
    {:ok, expected} = prepare_failure_fixture()

    session
    |> FailuresPage.navigate()
    |> FailuresPage.ensure_page_loaded()
    |> FailuresPage.assert_stat("Failures", expected.failure_count)
    |> FailuresPage.assert_stat("Players", 1)
    |> FailuresPage.assert_stat("Damage", expected.total_damage)
    |> FailuresPage.assert_player_group(expected.player_name, expected.player_guid)
    |> FailuresPage.assert_failure_row(%{
      spell_id: expected.spell_id,
      mechanic_type: "Avoidable",
      failure_count: expected.failure_count,
      total_damage: expected.total_damage,
      encounter_count: 1
    })
  end

  defp prepare_failure_fixture do
    {:ok, %{criteria: criteria}} = Rules.sync_current_tier_rules()
    criterion = Enum.find(criteria, &(&1.mechanic_type == "avoidable"))
    encounter = insert_dim_encounter!(criterion.boss_encounter_id)

    player_guid = "Player-Feature-#{System.unique_integer([:positive])}"
    player_name = "Feature Tester"
    failure_count = 3
    total_damage = 500

    insert_player_info!(encounter, player_guid, player_name)
    insert_damage_taken!(encounter, player_guid, criterion.spell_id, total_damage, failure_count)

    assert {:ok, %{inserted: 1}} = FactFailure.rebuild_for_encounter(encounter.id)

    fact =
      Repo.get_by!(FactFailure,
        encounter_dim_id: encounter.id,
        criterion_dim_id: criterion.id
      )

    {:ok,
     %{
       player_guid: player_guid,
       player_name: player_name,
       spell_id: criterion.spell_id,
       failure_count: fact.failure_count,
       total_damage: fact.total_damage
     }}
  end

  defp insert_dim_encounter!(boss_id) do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      wow_encounter_id: boss_id,
      name: "Feature Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "feature-instance",
      start_time: ~U[2026-05-18 20:00:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_player_info!(encounter, player_guid, player_name) do
    %PlayerInfo{}
    |> PlayerInfo.changeset(%{
      encounter_dim_id: encounter.id,
      player_guid: player_guid,
      player_name: player_name,
      class_id: 9,
      spec_id: 266,
      detected_role: "dps"
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken!(encounter, player_guid, spell_id, total_amount, hit_count) do
    %DamageTaken{}
    |> DamageTaken.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: player_guid,
      source_guid: "Creature-Feature",
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
