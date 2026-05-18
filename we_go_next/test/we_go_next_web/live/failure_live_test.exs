defmodule WeGoNextWeb.FailureLiveTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset

  test "renders grouped gold failure facts", %{conn: conn} do
    player = insert_player!("Player-One-#{System.unique_integer([:positive])}", "One")
    raid = get_or_insert_player!("__RAID__", "Raid")
    encounter = insert_encounter!("boss-one", "Boss One", ~U[2026-05-01 20:00:00Z])
    swirl = insert_criterion!(101, "Swirl", "avoidable", "Boss One")
    cast = insert_criterion!(202, "Shadow Volley", "interrupt", "Boss One")

    insert_failure!(encounter, player, swirl, 2, 500)
    insert_failure!(encounter, raid, cast, 1, 0)

    html =
      conn
      |> get(~p"/failures")
      |> html_response(200)

    assert html =~ "Mechanic Failures"
    assert html =~ "One"
    assert html =~ "Raid"
    assert html =~ "Swirl"
    assert html =~ "Shadow Volley"
    assert html =~ "500"
  end

  test "renders an empty state for date ranges without facts", %{conn: conn} do
    player = insert_player!("Player-One-#{System.unique_integer([:positive])}", "One")
    encounter = insert_encounter!("boss-one", "Boss One", ~U[2026-05-01 20:00:00Z])
    swirl = insert_criterion!(101, "Swirl", "avoidable", "Boss One")
    insert_failure!(encounter, player, swirl, 2, 500)

    html =
      conn
      |> get(~p"/failures?start_date=2026-05-03&end_date=2026-05-03")
      |> html_response(200)

    assert html =~ "No mechanic failures found"
    refute html =~ "Swirl"
  end

  defp insert_player!(guid, name) do
    %DimPlayer{}
    |> DimPlayer.changeset(%{player_guid: guid, player_name: name})
    |> Repo.insert!()
  end

  defp get_or_insert_player!(guid, name) do
    case Repo.get_by(DimPlayer, player_guid: guid) do
      %DimPlayer{} = player ->
        player

      nil ->
        insert_player!(guid, name)
    end
  end

  defp insert_encounter!(wow_encounter_id, name, start_time) do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      wow_encounter_id: wow_encounter_id,
      name: name,
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "test-instance",
      start_time: start_time
    })
    |> Repo.insert!()
  end

  defp insert_criterion!(spell_id, spell_name, mechanic_type, boss_name) do
    ruleset =
      %Ruleset{}
      |> Ruleset.changeset(%{name: "Failure Live Rules #{System.unique_integer([:positive])}"})
      |> Repo.insert!()

    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      spell_id: spell_id,
      spell_name: spell_name,
      mechanic_type: mechanic_type,
      boss_name: boss_name,
      threshold: %{"max_hits" => 0},
      active: true
    })
    |> Repo.insert!()
  end

  defp insert_failure!(encounter, player, criterion, failure_count, total_damage) do
    %FactFailure{}
    |> FactFailure.changeset(%{
      encounter_dim_id: encounter.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      failure_count: failure_count,
      total_damage: total_damage
    })
    |> Repo.insert!()
  end
end
