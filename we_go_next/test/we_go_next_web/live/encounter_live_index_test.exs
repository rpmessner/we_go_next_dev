defmodule WeGoNextWeb.EncounterLiveIndexTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.{Accounts, CombatLogFile, FileWatcher, WarcraftLogs}
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

  test "renders a reimport action on each imported log row", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    first_log = insert_combat_log!(user, "/tmp/wgn-home-row-one.log")
    second_log = insert_combat_log!(user, "/tmp/wgn-home-row-two.log")

    insert_encounter!(first_log, %{start_time: ~U[2026-04-12 20:00:00Z]})
    insert_encounter!(second_log, %{start_time: ~U[2026-04-19 20:00:00Z]})

    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert html =~ "Imported Logs"
    assert html =~ "wgn-home-row-one.log"
    assert html =~ "wgn-home-row-two.log"
    assert html =~ "First pull Apr 12, 2026"
    assert html =~ "First pull Apr 19, 2026"
    assert html =~ "Reimport"
    refute html =~ "Force Reimport Log"
  end

  test "renders a Warcraft Logs report URL association for an imported log", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    log = insert_combat_log!(user, "/tmp/wgn-wcl-linked.log")
    insert_encounter!(log, %{start_time: ~U[2026-04-12 20:00:00Z]})

    assert {:ok, _log} =
             WarcraftLogs.associate_report(
               log,
               "https://www.warcraftlogs.com/reports/abc123#fight=17&type=damage-done"
             )

    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert html =~ "Warcraft Logs report URL"
    assert html =~ "WCL report abc123 fight 17"

    updated = Repo.get!(CombatLogFile, log.id)
    assert updated.warcraft_logs_report_url =~ "/reports/abc123"
    assert updated.warcraft_logs_report_code == "abc123"
    assert updated.warcraft_logs_fight_id == 17
    assert updated.warcraft_logs_linked_at
  end

  test "import dropdown only contains unimported discovered logs", %{conn: conn} do
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

    assert html =~ ~s(value="#{unimported_path}")
    assert html =~ "log date Jan 02, 2026"
    refute html =~ ~s(<option value="#{imported_path}")
    refute html =~ "modified"
    refute html =~ "Currently loaded:"
    refute html =~ "✓ (complete)"
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

    FileWatcher.watch(log)
    FileWatcher.current_file()

    write_document_index!([
      %{
        source_encounter_key: "vorasius-source-key",
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
