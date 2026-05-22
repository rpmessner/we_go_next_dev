defmodule WeGoNextWeb.FailureLiveTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset

  test "renders grouped mechanic failures", %{conn: conn} do
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

  test "renders an empty state for date ranges without tracked failures", %{conn: conn} do
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

  test "defaults to latest imported encounter date range without query params", %{conn: conn} do
    old_player = insert_player!("Player-Old-#{System.unique_integer([:positive])}", "Old")

    recent_player =
      insert_player!("Player-Recent-#{System.unique_integer([:positive])}", "Recent")

    old_encounter = insert_encounter!("boss-old", "Boss Old", ~U[2026-04-01 20:00:00Z])
    recent_encounter = insert_encounter!("boss-recent", "Boss Recent", ~U[2026-05-10 20:00:00Z])
    old_criterion = insert_criterion!(301, "Old Swirl", "avoidable", "Boss Old")
    recent_criterion = insert_criterion!(302, "Recent Swirl", "avoidable", "Boss Recent")

    insert_failure!(old_encounter, old_player, old_criterion, 1, 100)
    insert_failure!(recent_encounter, recent_player, recent_criterion, 1, 200)

    html =
      conn
      |> get(~p"/failures")
      |> html_response(200)

    assert html =~ ~s(value="2026-04-27")
    assert html =~ ~s(value="2026-05-10")
    assert html =~ "Recent Swirl"
    refute html =~ "Old Swirl"
  end

  test "explains missing synced current-tier mechanics", %{conn: conn} do
    html =
      conn
      |> get(~p"/failures")
      |> html_response(200)

    assert html =~ "Data Readiness"
    assert html =~ "Current-tier mechanics not synced"
    assert html =~ "Sync current-tier mechanics and rebuild failures"
  end

  test "explains synced mechanics without failure-ready rows", %{conn: conn} do
    %Ruleset{}
    |> Ruleset.changeset(%{
      name: "Unpromoted Failure Rules #{System.unique_integer([:positive])}",
      status: "active"
    })
    |> Repo.insert!()

    html =
      conn
      |> get(~p"/failures")
      |> html_response(200)

    assert html =~ "Mechanics need sync"
    assert html =~ "No failure-ready mechanics are synced"
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
