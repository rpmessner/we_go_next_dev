defmodule WeGoNextWeb.PublicLiveTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Documents
  alias WeGoNext.Mirror.PublicReport
  alias WeGoNext.Repo
  alias WeGoNext.Support.StubSourceDocumentStore

  setup do
    original_mode = WeGoNext.mode()
    original_documents_store = Application.get_env(:we_go_next, :documents_store)

    Application.put_env(:we_go_next, :mode, :public)
    Application.put_env(:we_go_next, :documents_store, StubSourceDocumentStore)
    StubSourceDocumentStore.reset!()

    on_exit(fn ->
      Application.put_env(:we_go_next, :mode, original_mode)
      restore_env(:documents_store, original_documents_store)
      StubSourceDocumentStore.reset!()
    end)

    %{report: insert_report!("raid-night", "Raid Night")}
  end

  test "valid report slug renders public encounter list", %{conn: conn} do
    write_fixture_document!("encounter-one", %{
      encounter: %{name: "Boss One"},
      counts: %{players: 2, deaths: 1},
      failure_preview: %{counts: %{mechanics: 1, players: 1, failures: 2, damage: 500}}
    })

    html =
      conn
      |> get(~p"/r/raid-night")
      |> html_response(200)

    assert html =~ "Raid Night"
    assert html =~ "Boss One"
    refute html =~ "Settings"
    refute html =~ "Upload"
  end

  test "public dashboard filters encounters by named raid night", %{conn: conn} do
    write_fixture_document!("older-encounter", %{
      raid_night: %{key: "20260705T120000", name: "Holiday Raid", date: "2026-07-05"},
      encounter: %{name: "Older Boss", start_time: "2026-07-05T12:30:00Z"}
    })

    write_fixture_document!("newer-encounter", %{
      raid_night: %{key: "20260712T105733", name: "Sunday Mythic Progression", date: "2026-07-12"},
      encounter: %{name: "Newer Boss", start_time: "2026-07-12T11:30:00Z"}
    })

    {:ok, view, html} = Phoenix.LiveViewTest.live(conn, ~p"/r/raid-night")

    assert html =~ "Sunday Mythic Progression"
    assert html =~ "Holiday Raid"
    assert html =~ "Newer Boss"
    refute html =~ "Older Boss"

    html =
      view
      |> Phoenix.LiveViewTest.element("#raid-night-selector")
      |> Phoenix.LiveViewTest.render_change(%{"raid_night_key" => "20260705T120000"})

    assert html =~ "Older Boss"
    refute html =~ "Newer Boss"
  end

  test "bad slug returns 404", %{conn: conn} do
    assert conn
           |> get(~p"/r/wrong")
           |> response(404) == "Not Found"
  end

  test "disabled report slug returns 404", %{conn: conn} do
    insert_report!("disabled-report", "Disabled", false)

    assert conn
           |> get(~p"/r/disabled-report")
           |> response(404) == "Not Found"
  end

  test "public mode parser routes remain unavailable", %{conn: conn} do
    assert conn
           |> get(~p"/settings")
           |> response(404) == "Not Found"
  end

  test "public failures route is pruned", %{conn: conn} do
    assert conn
           |> get("/r/raid-night/failures")
           |> response(404) == "Not Found"
  end

  test "public encounter failure page renders per-encounter breakdown", %{
    conn: conn
  } do
    write_fixture_document!("encounter-one", %{
      encounter: %{name: "Boss One"},
      roster: [
        %{
          player_guid: "Player-One",
          player_name: "One",
          detected_role: "dps",
          class_id: 9
        }
      ],
      counts: %{players: 1, deaths: 0, interrupt_opportunities: 1},
      failure_preview: %{
        counts: %{mechanics: 1, players: 1, failures: 1, damage: 0},
        mechanics: [
          %{
            spell_id: 202,
            spell_name: "Shadow Volley",
            mechanic_type: "interrupt",
            failure_count: 1,
            total_damage: 0,
            players: [
              %{
                player_guid: "Player-One",
                player_name: "One",
                detected_role: "dps",
                class_id: 9,
                failure_count: 1,
                total_damage: 0
              }
            ]
          }
        ]
      }
    })

    html =
      conn
      |> get(~p"/r/raid-night/encounters/encounter-one?tab=failures")
      |> html_response(200)

    assert html =~ "Boss One"
    assert html =~ "Shadow Volley"
    assert html =~ "Interrupt"
    assert html =~ "One"
    refute html =~ "Upload"
    refute html =~ "Re-upload"
    refute html =~ "Source Key"
  end

  test "public encounter failure page handles unknown encounter key", %{conn: conn} do
    html =
      conn
      |> get(~p"/r/raid-night/encounters/missing")
      |> html_response(200)

    assert html =~ "Encounter Not Found"
  end

  test "public list renders encounters from the uploaded document index", %{
    conn: conn
  } do
    write_fixture_document!("shared-key", %{encounter: %{name: "Boss One"}})

    html =
      conn
      |> get(~p"/r/raid-night")
      |> html_response(200)

    assert html =~ "Boss One"
  end

  test "public list explains empty document index", %{conn: conn} do
    StubSourceDocumentStore.put("index.json", Jason.encode!(%{schema_version: 1, encounters: []}))

    html =
      conn
      |> get(~p"/r/raid-night")
      |> html_response(200)

    assert html =~ "No Uploaded Encounters"
  end

  test "public detail explains stale fixture documents", %{conn: conn} do
    write_fixture_document!("stale-key", %{derivation_version: -1})

    html =
      conn
      |> get(~p"/r/raid-night/encounters/stale-key")
      |> html_response(200)

    assert html =~ "Stale Encounter Document"
    assert html =~ to_string(Documents.current_derivation_version())
  end

  test "public detail explains empty fixture documents", %{conn: conn} do
    write_fixture_document!("empty-key")

    html =
      conn
      |> get(~p"/r/raid-night/encounters/empty-key")
      |> html_response(200)

    assert html =~ "Empty Encounter Document"
  end

  test "public LiveViews do not reference Accounts or silver modules" do
    source =
      [
        "lib/we_go_next_web/live/public_document_live/index.ex",
        "lib/we_go_next_web/live/public_document_live/show.ex"
      ]
      |> Enum.map(&File.read!(Path.expand("../../../#{&1}", __DIR__)))
      |> Enum.join("\n")

    refute source =~ "Accounts"
    refute source =~ "WeGoNext.Silver"
    refute source =~ "silver."
    refute source =~ "WeGoNext.Import"
    refute source =~ "WeGoNext.CombatLogParser"
  end

  test "public R2 store config does not fall back to parser account settings" do
    original_r2 = Application.get_env(:we_go_next, :documents_r2)

    Application.delete_env(:we_go_next, :documents_r2)

    try do
      assert WeGoNext.Documents.Store.R2.config() == {:error, :r2_not_configured}
    after
      restore_env(:documents_r2, original_r2)
    end
  end

  defp insert_report!(slug, title, enabled \\ true) do
    %PublicReport{}
    |> PublicReport.changeset(%{slug: slug, title: title, enabled: enabled})
    |> Repo.insert!()
  end

  defp write_fixture_document!(source_encounter_key, overrides \\ %{}) do
    document =
      %{
        schema_version: 1,
        generated_at: "2026-07-08T20:10:00Z",
        derivation_version: Documents.current_derivation_version(),
        source_encounter_key: source_encounter_key,
        raid_night: %{
          key: "20260708T200000",
          name: "Raid Night — Jul 08, 2026",
          date: "2026-07-08"
        },
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
          diagnostics: [],
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

    StubSourceDocumentStore.put(
      "encounters/#{source_encounter_key}.json",
      Jason.encode!(document)
    )

    write_index!()
  end

  defp write_index! do
    encounters =
      StubSourceDocumentStore.objects()
      |> Enum.flat_map(fn
        {"encounters/" <> _key, body} ->
          {:ok, document} = Jason.decode(body)
          [Documents.index_entry(document)]

        _other ->
          []
      end)

    StubSourceDocumentStore.put(
      "index.json",
      Jason.encode!(%{schema_version: 1, encounters: encounters})
    )
  end

  defp deep_merge(map, overrides) do
    Map.merge(map, overrides, fn _key, left, right ->
      if is_map(left) and is_map(right), do: deep_merge(left, right), else: right
    end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:we_go_next, key)
  defp restore_env(key, value), do: Application.put_env(:we_go_next, key, value)
end
