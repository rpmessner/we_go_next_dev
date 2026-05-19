defmodule WeGoNext.Gold.RebuildsTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure, Rebuilds}
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    Repo.delete_all(FactFailure)
    Repo.delete_all(DimMechanicCriterion)
    Repo.delete_all(DamageTaken)
    Repo.delete_all(PlayerInfo)
    Repo.delete_all(DimPlayer)
    Repo.delete_all(DimEncounter)
    Repo.delete_all(Ruleset)

    :ok
  end

  test "status returns gold encounter and failure fact counts" do
    encounter = insert_dim_encounter!("boss-one")
    player = insert_player!("Player-One", "One")
    criterion = insert_criterion!(insert_ruleset!("Rules", "active"), encounter, 101)

    insert_failure!(encounter, player, criterion)

    assert Rebuilds.status() == %{
             gold_encounters_count: 1,
             failure_facts_count: 1
           }
  end

  test "rebuild_all recomputes facts for all gold encounters from silver rows" do
    ruleset = insert_ruleset!("Active Ruleset", "active")
    first_encounter = insert_dim_encounter!("boss-one")
    second_encounter = insert_dim_encounter!("boss-two")

    first_criterion = insert_criterion!(ruleset, first_encounter, 101)
    second_criterion = insert_criterion!(ruleset, second_encounter, 202)

    insert_player_info!(first_encounter, "Player-One", "One")
    insert_player_info!(second_encounter, "Player-Two", "Two")
    insert_damage_taken!(first_encounter, "Player-One", 101, 100, 1)
    insert_damage_taken!(second_encounter, "Player-Two", 202, 200, 1)

    assert {:ok, %{encounters: 2, deleted: 0, inserted: 2, skipped: 0}} =
             Rebuilds.rebuild_all(ruleset: :active)

    assert fact_exists?(first_encounter, "Player-One", first_criterion)
    assert fact_exists?(second_encounter, "Player-Two", second_criterion)
  end

  defp fact_exists?(encounter, player_guid, criterion) do
    player = Repo.get_by(DimPlayer, player_guid: player_guid)

    player &&
      Repo.get_by(FactFailure,
        encounter_dim_id: encounter.id,
        player_dim_id: player.id,
        criterion_dim_id: criterion.id
      )
  end

  defp insert_dim_encounter!(wow_encounter_id) do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      wow_encounter_id: wow_encounter_id,
      name: "Test Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance"
    })
    |> Repo.insert!()
  end

  defp insert_player!(guid, name) do
    %DimPlayer{}
    |> DimPlayer.changeset(%{player_guid: guid, player_name: name})
    |> Repo.insert!()
  end

  defp insert_ruleset!(name, status) do
    %Ruleset{}
    |> Ruleset.changeset(%{name: name, status: status})
    |> Repo.insert!()
  end

  defp insert_criterion!(%Ruleset{} = ruleset, %DimEncounter{} = encounter, spell_id) do
    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      spell_id: spell_id,
      spell_name: "Bad #{spell_id}",
      mechanic_type: "avoidable",
      boss_encounter_id: encounter.wow_encounter_id,
      difficulty_id: 16,
      threshold: %{"max_hits" => 0}
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

  defp insert_damage_taken!(encounter, player_guid, spell_id, total_amount, hit_count) do
    %DamageTaken{}
    |> DamageTaken.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: player_guid,
      source_guid: "Creature-A",
      spell_id: spell_id,
      total_amount: total_amount,
      hit_count: hit_count,
      max_hit: total_amount,
      overkill_total: 0,
      source_is_npc: true
    })
    |> Repo.insert!()
  end

  defp insert_failure!(encounter, player, criterion) do
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
      failure_count: 1,
      total_damage: 100
    })
    |> Repo.insert!()
  end
end
