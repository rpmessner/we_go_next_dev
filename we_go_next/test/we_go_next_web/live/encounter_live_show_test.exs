defmodule WeGoNextWeb.EncounterLiveShowTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo
  alias WeGoNext.Silver.{DamageTaken, DamageTakenEvent, PlayerInfo}

  test "renders a medallion encounter detail shell keyed by gold encounter id", %{conn: conn} do
    encounter = insert_dim_encounter!()
    player = insert_dim_player!()

    insert_player_info!(encounter)
    insert_damage_taken!(encounter)
    insert_damage_taken_event!(encounter)
    insert_failure!(encounter, player)

    html =
      conn
      |> get(~p"/encounters/#{encounter.id}")
      |> html_response(200)

    assert html =~ "Plexus Sentinel"
    assert html =~ "Medallion encounter detail keyed by gold encounter ##{encounter.id}"
    assert html =~ "Gold Encounter ID"
    assert html =~ "Damage Hits"
    assert html =~ "Failure Facts"

    refute html =~ "Summary"
    refute html =~ "mechanic_criteria"
  end

  test "renders not found state for missing gold encounter id", %{conn: conn} do
    html =
      conn
      |> get(~p"/encounters/999999")
      |> html_response(200)

    assert html =~ "Encounter Not Found"
    assert html =~ "No gold encounter exists for that ID"
  end

  defp insert_dim_encounter! do
    %DimEncounter{}
    |> DimEncounter.changeset(%{
      wow_encounter_id: "2887",
      name: "Plexus Sentinel",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "2652",
      start_time: ~U[2026-05-01 20:00:00Z],
      end_time: ~U[2026-05-01 20:05:00Z],
      success: false,
      fight_time_ms: 300_000
    })
    |> Repo.insert!()
  end

  defp insert_dim_player! do
    %DimPlayer{}
    |> DimPlayer.changeset(%{
      player_guid: "Player-One",
      player_name: "One"
    })
    |> Repo.insert!()
  end

  defp insert_player_info!(%DimEncounter{} = encounter) do
    %PlayerInfo{}
    |> PlayerInfo.changeset(%{
      encounter_dim_id: encounter.id,
      player_guid: "Player-One",
      player_name: "One",
      detected_role: "unknown"
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken!(%DimEncounter{} = encounter) do
    %DamageTaken{}
    |> DamageTaken.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: "Player-One",
      source_guid: "Creature-One",
      spell_id: 101,
      total_amount: 100,
      hit_count: 1,
      max_hit: 100,
      overkill_total: 0,
      source_is_npc: true
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken_event!(%DimEncounter{} = encounter) do
    %DamageTakenEvent{}
    |> DamageTakenEvent.changeset(%{
      encounter_dim_id: encounter.id,
      combat_log_event_index: 1,
      event_type: "SPELL_DAMAGE",
      occurred_at_ms_into_fight: 1_000,
      target_guid: "Player-One",
      source_guid: "Creature-One",
      source_is_npc: true,
      spell_id: 101,
      amount: 100,
      overkill: 0
    })
    |> Repo.insert!()
  end

  defp insert_failure!(%DimEncounter{} = encounter, %DimPlayer{} = player) do
    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(%{
      source_rule_id: System.unique_integer([:positive]),
      ruleset_id: System.unique_integer([:positive]),
      ruleset_version: 1,
      spell_id: 101,
      spell_name: "Bad",
      mechanic_type: "avoidable",
      threshold: %{"max_hits" => 0}
    })
    |> Repo.insert!()
    |> then(fn criterion ->
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
    end)
  end
end
