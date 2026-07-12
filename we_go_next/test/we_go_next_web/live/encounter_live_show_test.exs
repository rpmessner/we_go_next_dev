defmodule WeGoNextWeb.EncounterLiveShowTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Gold.{
    DimEncounter,
    DimMechanicCriterion,
    DimPlayer,
    EncounterDetail,
    FactFailure
  }

  alias WeGoNext.{Documents, Repo}
  alias WeGoNext.Mirror.MirrorUpload

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
    generate_document!(encounter)

    html =
      conn
      |> get(~p"/encounters/#{encounter.source_encounter_key}")
      |> html_response(200)

    assert html =~ "Plexus Sentinel"
    assert html =~ "Encounter document #{encounter.source_encounter_key}"
    assert html =~ "Started May 01, 2026 08:00 PM"
    assert html =~ "Source Key"
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
    generate_document!(encounter)

    html =
      conn
      |> get(~p"/encounters/#{encounter.source_encounter_key}?tab=mechanics")
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

    generate_document!(encounter)

    html =
      conn
      |> get(~p"/encounters/#{encounter.source_encounter_key}?tab=damage")
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
    generate_document!(encounter)

    html =
      conn
      |> get(~p"/encounters/#{encounter.source_encounter_key}?tab=mechanics")
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
    generate_document!(encounter)

    html =
      conn
      |> get(~p"/encounters/#{encounter.source_encounter_key}?tab=failures")
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
    generate_document!(current)

    html =
      conn
      |> get(~p"/encounters/#{current.source_encounter_key}?tab=personal")
      |> html_response(200)

    assert html =~ "Personal Pulls"
    assert html =~ "Plexus Sentinel"
    assert html =~ current.source_encounter_key
  end

  test "renders not found state for missing pull id", %{conn: conn} do
    html =
      conn
      |> get(~p"/encounters/999999")
      |> html_response(200)

    assert html =~ "Encounter Not Found"
    assert html =~ "No encounter document exists for source key 999999"
  end

  test "renders encounter detail from a fixture document without read-model rows", %{conn: conn} do
    write_fixture_document!("fixture-source-key", %{
      roster: [
        %{
          player_guid: "Player-Fixture",
          player_name: "Fixtureplayer",
          class_id: 9,
          spec_id: 266,
          detected_role: "dps",
          item_level: 515
        }
      ],
      counts: %{players: 1, deaths: 0, interrupt_opportunities: 0},
      observed_mechanics: %{
        counts: %{observed_spells: 1},
        mechanics: [
          %{
            spell_id: 101,
            spell_name: "Fixture Blast",
            boss_name: "Fixture Boss",
            observed: %{total_damage: 100, damage_hits: 1, debuff_applications: 0},
            facts: %{failure_count: 0},
            operator: %{catalog: nil, criteria: [], rule_status: "untracked", diagnostics: []}
          }
        ]
      }
    })

    html =
      conn
      |> get(~p"/encounters/fixture-source-key")
      |> html_response(200)

    assert html =~ "Fixture Boss"
    assert html =~ "Encounter document fixture-source-key"
    assert html =~ "Fixtureplayer"
    assert html =~ "Mechanics"
    refute html =~ "Encounter Not Found"
  end

  test "explains empty fixture documents", %{conn: conn} do
    write_fixture_document!("empty-source-key")

    html =
      conn
      |> get(~p"/encounters/empty-source-key")
      |> html_response(200)

    assert html =~ "Empty Encounter Document"
    assert html =~ "no roster, deaths, failures, damage review rows"
    assert html =~ "No player roster data exists for this pull yet."
  end

  test "explains stale fixture documents", %{conn: conn} do
    write_fixture_document!("stale-source-key", %{
      derivation_version: "old-derivation",
      roster: [
        %{
          player_guid: "Player-Stale",
          player_name: "Staleplayer",
          class_id: 1,
          spec_id: 71,
          detected_role: "dps",
          item_level: nil
        }
      ],
      counts: %{players: 1, deaths: 0, interrupt_opportunities: 0}
    })

    html =
      conn
      |> get(~p"/encounters/stale-source-key")
      |> html_response(200)

    assert html =~ "Stale Encounter Document"
    assert html =~ "old-derivation"
    assert html =~ to_string(Documents.current_derivation_version())
  end

  test "shows upload button and manually queues a document upload", %{conn: conn} do
    write_fixture_document!("upload-source-key")

    html =
      conn
      |> get(~p"/encounters/upload-source-key")
      |> html_response(200)

    assert html =~ "Public Upload"
    assert html =~ "Not queued"
    assert html =~ "Upload"
    assert html =~ ~s(phx-click="enqueue_upload")

    {:ok, document} = Documents.fetch_encounter("upload-source-key")

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, document: document}
    }

    assert {:noreply, _socket} =
             WeGoNextWeb.EncounterLive.Show.handle_event("enqueue_upload", %{}, socket)

    assert %MirrorUpload{state: "pending"} =
             Repo.get_by!(MirrorUpload, source_encounter_key: "upload-source-key")
  end

  test "shows re-upload label for published documents", %{conn: conn} do
    write_fixture_document!("published-source-key")

    insert_upload!("published-source-key", %{
      state: "published",
      attempt_count: 1,
      published_at: ~U[2026-07-08 20:20:00Z]
    })

    html =
      conn
      |> get(~p"/encounters/published-source-key")
      |> html_response(200)

    assert html =~ "Published"
    assert html =~ "Re-upload"
    assert html =~ "Attempts 1"

    assert html =~
             ~s(href="https://we-go-next.gigalixirapp.com/r/raid-night/encounters/published-source-key")

    assert html =~ "View public report"
  end

  test "live-updates the upload panel when publishing completes", %{conn: conn} do
    source_encounter_key = "live-upload-source-key"
    write_fixture_document!(source_encounter_key)
    upload = insert_upload!(source_encounter_key, %{state: "pending"})

    {:ok, view, html} =
      Phoenix.LiveViewTest.live(conn, ~p"/encounters/#{source_encounter_key}")

    assert html =~ "Pending"
    refute html =~ "View public report"

    upload
    |> MirrorUpload.changeset(%{
      state: "published",
      attempt_count: 1,
      published_at: ~U[2026-07-12 20:20:00Z]
    })
    |> Repo.update!()

    Phoenix.PubSub.broadcast(
      WeGoNext.PubSub,
      "mirror_upload:#{source_encounter_key}",
      {:mirror_upload_updated, source_encounter_key}
    )

    html = Phoenix.LiveViewTest.render(view)
    assert html =~ "Published"
    assert html =~ "View public report"
  end

  test "shows upload error diagnostics", %{conn: conn} do
    write_fixture_document!("error-source-key")

    insert_upload!("error-source-key", %{
      state: "error",
      attempt_count: 2,
      last_error: "{:error, :r2_not_configured}",
      last_attempted_at: ~U[2026-07-08 20:25:00Z]
    })

    html =
      conn
      |> get(~p"/encounters/error-source-key")
      |> html_response(200)

    assert html =~ "Error"
    assert html =~ "Upload error"
    assert html =~ "r2_not_configured"
    assert html =~ "Attempts 2"
  end

  defp insert_dim_encounter!(attrs \\ %{}) do
    source_start_byte = System.unique_integer([:positive])

    %DimEncounter{}
    |> DimEncounter.changeset(
      Map.merge(
        %{
          source_head_sha256: String.duplicate("a", 64),
          source_encounter_key: "source-key-#{System.unique_integer([:positive])}",
          wow_encounter_id: "2887",
          name: "Plexus Sentinel",
          difficulty_id: 16,
          difficulty_name: "Mythic",
          group_size: 20,
          instance_id: "2652",
          start_time: ~U[2026-05-01 20:00:00Z],
          end_time: ~U[2026-05-01 20:05:00Z],
          success: false,
          fight_time_ms: 300_000,
          start_byte: source_start_byte,
          end_byte: source_start_byte + 1_000
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

  defp generate_document!(%DimEncounter{} = encounter) do
    assert {:ok, _result} = Documents.generate_for_encounter(encounter.id)
  end

  defp write_fixture_document!(source_encounter_key, overrides \\ %{}) do
    document =
      %{
        schema_version: 1,
        generated_at: "2026-07-08T20:10:00Z",
        derivation_version: Documents.current_derivation_version(),
        source_encounter_key: source_encounter_key,
        encounter: %{
          id: 9_001,
          source_encounter_key: source_encounter_key,
          wow_encounter_id: "fixture-boss",
          name: "Fixture Boss",
          difficulty_id: 16,
          difficulty_name: "Mythic",
          group_size: 20,
          instance_id: "fixture-instance",
          start_time: "2026-07-08T20:00:00Z",
          end_time: "2026-07-08T20:05:00Z",
          success: false,
          fight_time_ms: 300_000,
          operator: %{}
        },
        counts: %{players: 0, deaths: 0, interrupt_opportunities: 0, operator: %{}},
        roster: [],
        deaths: [],
        pull_review: %{
          damage_done: [],
          low_dps: [],
          damage_taken_spells: [],
          debuffs: %{all: [], boss: [], player: []}
        },
        failure_preview: %{
          counts: %{mechanics: 0, players: 0, failures: 0, damage: 0},
          mechanics: [],
          operator: %{diagnostics: []}
        },
        interrupt_coverage: %{spell_coverage: [], player_contributions: []},
        personal_pull_summary: %{
          selected_player_guid: nil,
          players: [],
          operator: %{selected_player_guid: nil}
        },
        observed_mechanics: %{counts: %{observed_spells: 0, operator: %{}}, mechanics: []}
      }
      |> deep_merge(overrides)

    path =
      Path.join([
        Application.fetch_env!(:we_go_next, :documents_root),
        "encounters",
        "#{source_encounter_key}.json"
      ])

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(document))
  end

  defp deep_merge(map, overrides) do
    Map.merge(map, overrides, fn _key, left, right ->
      if is_map(left) and is_map(right), do: deep_merge(left, right), else: right
    end)
  end

  defp insert_upload!(source_encounter_key, attrs) do
    %MirrorUpload{}
    |> MirrorUpload.changeset(
      Map.merge(
        %{
          source_encounter_key: source_encounter_key,
          state: "pending",
          attempt_count: 0
        },
        attrs
      )
    )
    |> Repo.insert!()
  end
end
