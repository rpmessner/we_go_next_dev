defmodule WeGoNext.Gold.FailureSummaryTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Gold.{
    DimEncounter,
    DimMechanicCriterion,
    DimPlayer,
    FactFailure,
    FailureSummary
  }

  alias WeGoNext.Repo
  alias WeGoNext.Rules.Ruleset

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    ruleset =
      %Ruleset{}
      |> Ruleset.changeset(%{name: "Failure Summary Rules", status: "active"})
      |> Repo.insert!()

    suffix = System.unique_integer([:positive])

    one =
      %DimPlayer{}
      |> DimPlayer.changeset(%{
        player_guid: "Player-One-#{suffix}",
        player_name: "One",
        class_id: 1,
        spec_id: 71
      })
      |> Repo.insert!()

    raid = get_or_insert_player!("__RAID__", "Raid")

    swirl = insert_criterion!(ruleset, 101, "Swirl", "avoidable")
    cast = insert_criterion!(ruleset, 202, "Shadow Volley", "interrupt")

    early = insert_encounter!("boss-one", "Boss One", ~U[2026-05-01 20:00:00Z])
    late = insert_encounter!("boss-two", "Boss Two", ~U[2026-05-03 20:00:00Z])

    {:ok, one: one, raid: raid, swirl: swirl, cast: cast, early: early, late: late}
  end

  test "list_grouped_failures groups by player and criterion", %{
    one: one,
    raid: raid,
    swirl: swirl,
    cast: cast,
    early: early,
    late: late
  } do
    insert_failure!(early, one, swirl, 2, 500)
    insert_failure!(late, one, swirl, 3, 700)
    insert_failure!(late, raid, cast, 1, 0)

    rows = FailureSummary.list_grouped_failures()

    assert [
             %{
               player_name: "One",
               spell_name: "Swirl",
               failure_count: 5,
               total_damage: 1_200,
               encounter_count: 2
             },
             %{
               player_name: "Raid",
               spell_name: "Shadow Volley",
               failure_count: 1,
               total_damage: 0,
               encounter_count: 1
             }
           ] = rows

    assert [
             %{player_name: "One", failure_count: 5, failures: [_]},
             %{player_name: "Raid", failure_count: 1, failures: [_]}
           ] = FailureSummary.group_by_player(rows)
  end

  test "list_grouped_failures applies inclusive date filters", %{
    one: one,
    swirl: swirl,
    early: early,
    late: late
  } do
    insert_failure!(early, one, swirl, 2, 500)
    insert_failure!(late, one, swirl, 3, 700)

    assert [
             %{
               spell_name: "Swirl",
               failure_count: 3,
               total_damage: 700,
               encounter_count: 1
             }
           ] =
             FailureSummary.list_grouped_failures(%{
               start_date: ~D[2026-05-03],
               end_date: ~D[2026-05-03]
             })
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

  defp insert_criterion!(ruleset, spell_id, spell_name, mechanic_type) do
    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      spell_id: spell_id,
      spell_name: spell_name,
      mechanic_type: mechanic_type,
      threshold: %{"max_hits" => 0},
      active: true
    })
    |> Repo.insert!()
  end

  defp get_or_insert_player!(guid, name) do
    case Repo.get_by(DimPlayer, player_guid: guid) do
      %DimPlayer{} = player ->
        player

      nil ->
        %DimPlayer{}
        |> DimPlayer.changeset(%{player_guid: guid, player_name: name})
        |> Repo.insert!()
    end
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
