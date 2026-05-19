defmodule WeGoNextWeb.EncounterLiveShowTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo
  alias WeGoNext.Silver.{DamageTaken, DamageTakenEvent, Death, InterruptOpportunity, PlayerInfo}

  test "renders a medallion encounter detail shell keyed by gold encounter id", %{conn: conn} do
    encounter = insert_dim_encounter!()
    player = insert_dim_player!()

    insert_player_info!(encounter, %{
      player_guid: "Player-Tank",
      player_name: "Tankone",
      class_id: 1,
      spec_id: 73,
      item_level: 501,
      detected_role: "tank"
    })

    insert_player_info!(encounter, %{
      player_guid: "Player-One",
      player_name: "One",
      class_id: 9,
      spec_id: 266,
      item_level: 498,
      detected_role: "dps"
    })

    insert_damage_taken!(encounter)
    insert_damage_taken_event!(encounter)
    insert_death!(encounter)
    insert_interrupt_opportunity!(encounter, 1_000, true)
    insert_interrupt_opportunity!(encounter, 2_000, false)
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
    assert html =~ ~s(href="/failures")
    assert html =~ "Roster"
    assert html =~ "Tankone"
    assert html =~ "Tank"
    assert html =~ "Warlock"
    assert html =~ "Spec 266"
    assert html =~ "498"
    assert html =~ "Death Recap"
    assert html =~ ~S|<span class="ml-1 text-zinc-500">(1)</span>|
    assert html =~ "Interrupt Coverage"
    assert html =~ ~S|<span class="ml-1 text-zinc-500">(2)</span>|
    assert html =~ "Personal Pulls"

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

  defp insert_death!(%DimEncounter{} = encounter) do
    %Death{}
    |> Death.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: "Player-One",
      died_at_ms_into_fight: 10_000,
      killing_blow_spell_id: 101,
      killing_blow_source_guid: "Creature-One",
      damage_recap: [
        %{
          "ms_into_fight" => 10_000,
          "spell_id" => 101,
          "spell_name" => "Bad",
          "source_guid" => "Creature-One",
          "source_name" => "Creature One",
          "amount" => 100,
          "overkill" => 10
        }
      ]
    })
    |> Repo.insert!()
  end

  defp insert_interrupt_opportunity!(%DimEncounter{} = encounter, time_ms, success) do
    %InterruptOpportunity{}
    |> InterruptOpportunity.changeset(%{
      encounter_dim_id: encounter.id,
      target_npc_guid: "Creature-Caster",
      interrupted_spell_id: 777,
      opportunity_ms_into_fight: time_ms,
      success: success,
      interrupter_guid: if(success, do: "Player-One"),
      interrupting_spell_id: if(success, do: 1766)
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
