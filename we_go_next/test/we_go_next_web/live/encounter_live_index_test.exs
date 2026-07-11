defmodule WeGoNextWeb.EncounterLiveIndexTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.{Accounts, CombatLogFile, FileWatcher}
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo
  alias WeGoNext.Rules
  alias WeGoNext.Rules.{MechanicCriterion, Ruleset}
  alias WeGoNext.Silver.{DamageTaken, PlayerInfo}

  setup do
    Repo.delete_all(FactFailure)
    Repo.delete_all(DimMechanicCriterion)
    Repo.delete_all(DamageTaken)
    Repo.delete_all(PlayerInfo)
    Repo.delete_all(DimPlayer)
    Repo.delete_all(DimEncounter)
    Repo.delete_all(MechanicCriterion)
    Repo.delete_all(Ruleset)
    Repo.delete_all(Encounter)
    Repo.delete_all(CombatLogFile)
    FileWatcher.stop_watching()
    on_exit(fn -> FileWatcher.stop_watching() end)

    :ok
  end

  test "does not render warehouse operation controls", %{conn: conn} do
    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    refute html =~ "Current-Tier Mechanics"
    refute html =~ "synced mechanics"
    refute html =~ "failure-ready mechanics"
    refute html =~ "Sync Mechanics"
    refute html =~ "Seed Bundled Rules"
    refute html =~ "Promote Active Rules"
    refute html =~ "Rules Operations"
    refute html =~ "No active ruleset"
    refute html =~ "Data Recompute"
    refute html =~ "Rebuild Failures"
    refute html =~ "Force Reimport Log"
    refute html =~ "tracked failure rows"
    refute html =~ "checked-in mechanic code"
  end

  test "does not render per-log management on the home page", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    log = insert_combat_log!(user, "/tmp/wgn-home-no-logs.log")
    insert_encounter!(log, %{start_time: ~U[2026-04-12 20:00:00Z]})

    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    refute html =~ "Imported Logs"
    refute html =~ ~s(phx-click="reimport_log")
    refute html =~ ~s(phx-click="toggle_publish_enabled")
    refute html =~ "Warcraft Logs report URL"
    assert html =~ ~s(href="/logs")
  end

  test "log dropdown contains imported and unimported discovered logs", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    dir = Path.join(System.tmp_dir!(), "wgn-home-logs-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    imported_path = Path.join(dir, "WoWCombatLog-010126_010101.txt")
    unimported_path = Path.join(dir, "WoWCombatLog-010226_010101.txt")
    File.write!(imported_path, "imported")
    File.write!(unimported_path, "unimported")

    {:ok, _user} = Accounts.set_wow_logs_path(user, dir)
    insert_combat_log!(user, imported_path)

    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert html =~ "Combat Log"
    assert html =~ ~s(value="#{unimported_path}")
    assert html =~ ~s(value="#{imported_path}")
    assert html =~ "log date Jan 02, 2026"
    assert length(Regex.scan(~r/id="log-selector"/, html)) == 1
    refute html =~ ~s(id="filter-log")
    refute html =~ "modified"
    refute html =~ "Currently loaded:"
    refute html =~ "✓ (complete)"
  end

  test "does not expose current-tier sync state on the home page", %{conn: conn} do
    assert {:ok, %{ruleset: active_ruleset, criteria: criteria, promoted: promoted}} =
             Rules.sync_current_tier_rules(activate: true, promote: true)

    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert active_ruleset.name == "Midnight Season 1 Mechanics"
    assert length(criteria) == 30
    assert length(promoted.criteria) == 30
    refute html =~ "30 synced mechanics"
    refute html =~ "30 failure-ready mechanics"
    refute html =~ "Active: Midnight Season 1 Mechanics"
    assert Repo.aggregate(DimMechanicCriterion, :count) == 30
  end

  test "encounter headers prefer code-defined raid names over raw instance ids", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    log = insert_combat_log!(user, "/tmp/wgn-vorasius.log")

    insert_encounter!(log, %{
      wow_encounter_id: "3177",
      name: "Vorasius",
      instance_id: "2913",
      difficulty_id: 15,
      difficulty_name: "Heroic",
      success: false,
      start_byte: 0,
      end_byte: 100,
      start_time: DateTime.utc_now()
    })

    dim =
      insert_dim_encounter!(log, %{
        wow_encounter_id: "3177",
        name: "Vorasius",
        instance_id: "2913",
        difficulty_id: 15,
        difficulty_name: "Heroic",
        success: false,
        start_byte: 0,
        end_byte: 100,
        start_time: DateTime.utc_now()
      })

    FileWatcher.watch(log)
    FileWatcher.current_file()

    write_document_index!([
      %{
        source_encounter_key: dim.source_encounter_key,
        boss: "Vorasius",
        wow_encounter_id: "3177",
        difficulty_id: 15,
        difficulty_name: "Heroic",
        instance_id: "2913",
        start_time: "2026-07-08T20:00:00Z",
        end_time: "2026-07-08T20:05:00Z",
        success: false,
        fight_time_ms: 300_000,
        headline_counts: %{players: 20, deaths: 0, failures: 0, failure_damage: 0, low_damage: 0}
      }
    ])

    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert html =~ "The Voidspire"
    refute html =~ ~r/March on Quel&#39;Danas.*Vorasius/s
  end

  test "encounter list defaults to the latest log and can show all logs", %{conn: conn} do
    user = Accounts.get_or_create_default_user()

    old_log = insert_combat_log!(user, "/tmp/wgn-filter-old.log")
    new_log = insert_combat_log!(user, "/tmp/wgn-filter-new.log")

    # Reimport scenario: the OLD raid night was parsed most recently. Ordering
    # and the default filter must follow encounter dates, not parse time.
    {:ok, _} =
      old_log
      |> CombatLogFile.changeset(%{})
      |> Ecto.Changeset.put_change(
        :last_parsed_at,
        DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update()

    insert_encounter!(old_log, %{start_time: ~U[2026-04-12 20:00:00Z]})
    insert_encounter!(new_log, %{start_time: ~U[2026-04-19 20:00:00Z]})

    old_dim =
      insert_dim_encounter!(old_log, %{
        wow_encounter_id: "1001",
        name: "Old Boss",
        start_byte: 0,
        end_byte: 100,
        start_time: ~U[2026-04-12 20:00:00Z]
      })

    new_dim =
      insert_dim_encounter!(new_log, %{
        wow_encounter_id: "1002",
        name: "New Boss",
        start_byte: 0,
        end_byte: 100,
        start_time: ~U[2026-04-19 20:00:00Z]
      })

    write_document_index!([
      index_entry(old_dim, "Old Boss", "2026-04-12T20:00:00Z"),
      index_entry(new_dim, "New Boss", "2026-04-19T20:00:00Z")
    ])

    {:ok, view, html} = Phoenix.LiveViewTest.live(conn, ~p"/")

    assert html =~ "New Boss"
    refute html =~ "Old Boss"

    assert Phoenix.LiveViewTest.has_element?(
             view,
             "#log-selector-form button:not([disabled])",
             "Import"
           )

    html =
      view
      |> Phoenix.LiveViewTest.element("#log-selector-form")
      |> Phoenix.LiveViewTest.render_change(%{"log_path" => "all"})

    assert html =~ "New Boss"
    assert html =~ "Old Boss"

    html =
      view
      |> Phoenix.LiveViewTest.element("#log-selector-form")
      |> Phoenix.LiveViewTest.render_change(%{"log_path" => old_log.file_path})

    refute html =~ "New Boss"
    assert html =~ "Old Boss"
  end

  test "encounters within a log render in combat log order", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    log = insert_combat_log!(user, "/tmp/wgn-pull-order.log")

    early_dim =
      insert_dim_encounter!(log, %{
        wow_encounter_id: "1001",
        name: "Early Pull",
        start_byte: 100,
        end_byte: 200,
        start_time: ~U[2026-04-19 20:00:00Z]
      })

    late_dim =
      insert_dim_encounter!(log, %{
        wow_encounter_id: "1001",
        name: "Late Pull",
        start_byte: 300,
        end_byte: 400,
        start_time: ~U[2026-04-19 20:10:00Z]
      })

    write_document_index!([
      index_entry(late_dim, "Late Pull", "2026-04-19T20:10:00Z"),
      index_entry(early_dim, "Early Pull", "2026-04-19T20:00:00Z")
    ])

    {:ok, view, html} = Phoenix.LiveViewTest.live(conn, ~p"/")

    pulls =
      ~r/aria-label="Open (Early Pull|Late Pull)"/
      |> Regex.scan(html, capture: :all_but_first)
      |> List.flatten()

    assert pulls == ["Early Pull", "Late Pull"]

    html =
      view
      |> Phoenix.LiveViewTest.element("#encounter-sort-direction")
      |> Phoenix.LiveViewTest.render_click()

    pulls =
      ~r/aria-label="Open (Early Pull|Late Pull)"/
      |> Regex.scan(html, capture: :all_but_first)
      |> List.flatten()

    assert pulls == ["Late Pull", "Early Pull"]
    assert html =~ "Newest first"
    assert_patch(view, ~p"/?sort=desc")

    {:ok, _remounted_view, remounted_html} =
      Phoenix.LiveViewTest.live(conn, ~p"/?sort=desc")

    assert remounted_html =~ "Newest first"
  end

  defp insert_combat_log!(user, path) do
    %CombatLogFile{}
    |> CombatLogFile.changeset(%{
      user_id: user.id,
      file_path: path,
      source: :live,
      head_sha256: String.duplicate("a", 64),
      last_parsed_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp insert_encounter!(combat_log_file, attrs) do
    %Encounter{}
    |> Encounter.changeset(
      Map.merge(
        %{
          combat_log_file_id: combat_log_file.id,
          wow_encounter_id: "test-encounter",
          name: "Test Encounter"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp insert_dim_encounter!(combat_log_file, attrs) do
    %DimEncounter{}
    |> DimEncounter.changeset(
      Map.merge(
        %{
          source_file_path: combat_log_file.file_path,
          source_head_sha256: combat_log_file.head_sha256,
          difficulty_id: 15,
          difficulty_name: "Heroic",
          group_size: 20,
          instance_id: "test-instance",
          success: false
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp index_entry(dim, boss, start_time) do
    %{
      source_encounter_key: dim.source_encounter_key,
      boss: boss,
      wow_encounter_id: dim.wow_encounter_id,
      difficulty_id: dim.difficulty_id,
      difficulty_name: dim.difficulty_name,
      instance_id: dim.instance_id,
      start_time: start_time,
      end_time: start_time,
      success: false,
      fight_time_ms: 300_000,
      headline_counts: %{players: 20, deaths: 0, failures: 0, failure_damage: 0, low_damage: 0}
    }
  end

  defp write_document_index!(encounters) do
    path = Path.join(Application.fetch_env!(:we_go_next, :documents_root), "index.json")
    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      Jason.encode!(%{
        schema_version: 1,
        generated_at: "2026-07-08T20:10:00Z",
        encounters: encounters
      })
    )
  end
end
