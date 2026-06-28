defmodule WeGoNextWeb.EncounterLiveShowTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Gold.{
    DimEncounter,
    DimMechanicCriterion,
    DimPlayer,
    EncounterDetail,
    FactFailure
  }

  alias WeGoNext.Repo

  alias WeGoNext.Silver.{
    DamageDone,
    DamageTaken,
    DamageTakenEvent,
    Death,
    DebuffApplication,
    DefensiveBuffWindow,
    InterruptOpportunity,
    PlayerInfo
  }

  test "renders an encounter detail page keyed by imported pull id", %{conn: conn} do
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
    assert html =~ "Encounter detail for imported pull ##{encounter.id}"
    assert html =~ "Started May 01, 2026 08:00 PM"
    assert html =~ "Pull ID"
    assert html =~ "Pull Signals"
    assert html =~ "Tracked Failures"
    assert html =~ "Failure Damage"
    assert html =~ "Top Damage Taken"
    assert html =~ "Bad · 1 hit"
    assert html =~ "20 expected"
    assert html =~ ~s(href="/failures")
    assert html =~ "Roster"
    assert html =~ "Tankone"
    assert html =~ "Tank"
    assert html =~ "Warlock"
    assert html =~ "Dps"
    assert html =~ "Demonology"
    assert html =~ "498"
    assert html =~ "Death Recap"
    assert html =~ ~S|<span class="ml-1 text-zinc-500">(1)</span>|
    assert html =~ "Mechanics"
    assert html =~ "Damage"
    assert html =~ "Failures"
    assert html =~ "Interrupt Coverage"
    assert html =~ ~S|<span class="ml-1 text-zinc-500">(2)</span>|
    assert html =~ "Personal Pulls"

    refute html =~ "mechanic_criteria"
  end

  test "renders observed mechanics preview after switching tabs", %{conn: conn} do
    encounter = insert_dim_encounter!()
    player = insert_dim_player!()

    insert_damage_taken_event!(encounter)
    insert_interrupt_opportunity!(encounter, 2_000, false)
    insert_failure!(encounter, player)

    html =
      conn
      |> get(~p"/encounters/#{encounter.id}?tab=mechanics")
      |> html_response(200)

    assert html =~ "Pull Review"
    assert html =~ "Damage Taken"
    assert html =~ "Debuffs"
    assert html =~ "Encounter Spells"
    assert html =~ "Category"
    assert html =~ "Seen As"
    assert html =~ "Bad"
    assert html =~ "Avoidable"
    assert html =~ "1 failure"
    assert html =~ "Spell 101"
    assert html =~ "Show untagged/noise"
    refute html =~ "Damage Done Ranking"
    refute html =~ "Low Damage Warnings"
    refute html =~ "criterion"
    refute html =~ "snapshot"
    refute html =~ "ruleset"
  end

  test "renders damage tab ranking and low damage warnings without early deaths", %{conn: conn} do
    encounter = insert_dim_encounter!()

    insert_player_info!(encounter, %{
      player_guid: "Player-One",
      player_name: "One",
      class_id: 9,
      spec_id: 266,
      detected_role: "dps"
    })

    insert_player_info!(encounter, %{
      player_guid: "Player-Low",
      player_name: "Low",
      class_id: 8,
      spec_id: 62,
      detected_role: "dps"
    })

    insert_player_info!(encounter, %{
      player_guid: "Player-Early",
      player_name: "Early",
      class_id: 4,
      spec_id: 260,
      detected_role: "dps"
    })

    insert_damage_done!(encounter, "Player-One", 501, 900_000)
    insert_damage_done!(encounter, "Player-Low", 501, 120_000)
    insert_damage_done!(encounter, "Player-Early", 501, 10_000)
    insert_death!(encounter, "Player-Early", %{died_at_ms_into_fight: 10_000})

    {:ok, detail} = EncounterDetail.get(encounter.id)

    assert Enum.map(detail.pull_review.low_dps, & &1.player_name) == ["Low"]

    refute Enum.any?(detail.pull_review.low_dps, fn player ->
             player.player_name == "Early"
           end)

    html =
      conn
      |> get(~p"/encounters/#{encounter.id}?tab=damage")
      |> html_response(200)

    assert html =~ "Low Damage Warnings"
    assert html =~ "Damage Done Ranking"
    assert html =~ "Low"
    assert html =~ "400"
    assert html =~ "Early"
    assert html =~ "Early death at 0:10"
    assert html =~ "Survived"
    refute html =~ "Show player-applied debuffs"
    refute html =~ "criterion"
    refute html =~ "source_data"
    refute html =~ "promotion"
  end

  test "keeps damage taken and debuff filters on mechanics tab", %{conn: conn} do
    encounter = insert_dim_encounter!()
    player = insert_dim_player!()

    insert_damage_taken_event!(encounter, %{spell_id: 101, spell_name: "Bad", amount: 100})
    insert_damage_taken_event!(encounter, %{spell_id: 202, spell_name: "Noise", amount: 50})
    insert_debuff_application!(encounter, %{spell_id: 303, source_guid: "Creature-Boss"})
    insert_debuff_application!(encounter, %{spell_id: 404, source_guid: "Player-One"})
    insert_failure!(encounter, player)

    html =
      conn
      |> get(~p"/encounters/#{encounter.id}?tab=mechanics")
      |> html_response(200)

    assert html =~ "Damage Taken"
    assert html =~ "Debuffs"
    assert html =~ "Show player-applied debuffs"
    assert html =~ "Encounter"
    assert html =~ "Bad"
    assert html =~ "Avoidable"
    assert html =~ "Untagged"
    refute html =~ "Damage Done Ranking"
    refute html =~ "Low Damage Warnings"
    refute html =~ "Player applied"
    refute html =~ "criterion"
    refute html =~ "source_data"
    refute html =~ "promotion"
  end

  test "renders failure preview from tracked failures", %{conn: conn} do
    encounter = insert_dim_encounter!()
    player = insert_dim_player!()

    insert_player_info!(encounter, %{
      player_guid: "Player-One",
      player_name: "One",
      class_id: 9,
      spec_id: 266,
      detected_role: "dps"
    })

    insert_failure!(encounter, player)

    html =
      conn
      |> get(~p"/encounters/#{encounter.id}?tab=failures")
      |> html_response(200)

    assert html =~ "Failures"
    assert html =~ "Bad"
    assert html =~ "Spell 101"
    assert html =~ "One"
    assert html =~ "1"
    assert html =~ "100 damage"
    refute html =~ "No mechanic failures exist"
  end

  test "renders player encounter performance history on personal tab", %{conn: conn} do
    previous =
      insert_dim_encounter!(%{
        start_time: ~U[2026-05-01 19:50:00Z],
        success: false,
        fight_time_ms: 240_000
      })

    current =
      insert_dim_encounter!(%{
        start_time: ~U[2026-05-01 20:00:00Z],
        success: true,
        fight_time_ms: 300_000
      })

    player = insert_dim_player!()

    for encounter <- [previous, current] do
      insert_player_info!(encounter, %{
        player_guid: "Player-One",
        player_name: "One",
        class_id: 9,
        spec_id: 266,
        detected_role: "dps"
      })

      insert_damage_taken!(encounter)
      insert_failure!(encounter, player)
    end

    insert_damage_taken_event!(current)
    insert_defensive_window!(current)
    insert_death!(previous)

    html =
      conn
      |> get(~p"/encounters/#{current.id}?tab=personal")
      |> html_response(200)

    assert html =~ "Defensive Coverage"
    assert html =~ "Dangerous Events"
    assert html =~ "Covered"
    assert html =~ "Unending Resolve"
    assert html =~ "Failure damage"
    assert html =~ "Encounter Performance"
    assert html =~ "Recent Pulls"
    assert html =~ "Avg Failures"
    assert html =~ "Failure Delta"
    assert html =~ "Current pull"
    assert html =~ "Kill"
    assert html =~ "Wipe"
  end

  test "renders not found state for missing pull id", %{conn: conn} do
    html =
      conn
      |> get(~p"/encounters/999999")
      |> html_response(200)

    assert html =~ "Encounter Not Found"
    assert html =~ "No imported pull exists for that ID"
  end

  defp insert_dim_encounter!(attrs \\ %{}) do
    %DimEncounter{}
    |> DimEncounter.changeset(
      Map.merge(
        %{
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
        },
        attrs
      )
    )
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

  defp insert_damage_done!(%DimEncounter{} = encounter, source_guid, spell_id, total_amount) do
    %DamageDone{}
    |> DamageDone.changeset(%{
      encounter_dim_id: encounter.id,
      source_guid: source_guid,
      target_guid: "Creature-Boss",
      spell_id: spell_id,
      total_amount: total_amount,
      hit_count: 3,
      max_hit: div(total_amount, 3)
    })
    |> Repo.insert!()
  end

  defp insert_damage_taken_event!(%DimEncounter{} = encounter, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          combat_log_event_index: System.unique_integer([:positive]),
          event_type: "SPELL_DAMAGE",
          occurred_at_ms_into_fight: 1_000,
          target_guid: "Player-One",
          target_name: "One",
          source_guid: "Creature-One",
          source_name: "Creature One",
          source_is_npc: true,
          spell_id: 101,
          spell_name: "Bad",
          amount: 100,
          overkill: 0
        },
        attrs
      )

    %DamageTakenEvent{}
    |> DamageTakenEvent.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_death!(%DimEncounter{} = encounter) do
    insert_death!(encounter, "Player-One")
  end

  defp insert_death!(%DimEncounter{} = encounter, target_guid, attrs \\ %{}) do
    %Death{}
    |> Death.changeset(
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          target_guid: target_guid,
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
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp insert_debuff_application!(%DimEncounter{} = encounter, attrs) do
    attrs =
      Map.merge(
        %{
          encounter_dim_id: encounter.id,
          target_guid: "Player-One",
          source_guid: "Creature-One",
          spell_id: 303,
          applied_at_ms_into_fight: 1_000,
          stack_count: 1
        },
        attrs
      )

    %DebuffApplication{}
    |> DebuffApplication.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_defensive_window!(%DimEncounter{} = encounter) do
    %DefensiveBuffWindow{}
    |> DefensiveBuffWindow.changeset(%{
      encounter_dim_id: encounter.id,
      target_guid: "Player-One",
      source_guid: "Player-One",
      spell_id: 104_773,
      spell_name: "Unending Resolve",
      category: "personal",
      started_at_ms_into_fight: 500,
      ended_at_ms_into_fight: 1_500,
      duration_ms: 1_000
    })
    |> Repo.insert!()
  end

  defp insert_interrupt_opportunity!(%DimEncounter{} = encounter, time_ms, success) do
    %InterruptOpportunity{}
    |> InterruptOpportunity.changeset(%{
      encounter_dim_id: encounter.id,
      target_npc_guid: "Creature-Caster",
      interrupted_spell_id: 1_249_017,
      opportunity_ms_into_fight: time_ms,
      success: success,
      interrupter_guid: if(success, do: "Player-One"),
      interrupting_spell_id: if(success, do: 1766)
    })
    |> Repo.insert!()
  end

  defp insert_failure!(%DimEncounter{} = encounter, %DimPlayer{} = player) do
    criterion = get_or_insert_failure_criterion!()

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

  defp get_or_insert_failure_criterion! do
    Repo.get_by(DimMechanicCriterion, spell_id: 101, mechanic_type: "avoidable") ||
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
  end
end
