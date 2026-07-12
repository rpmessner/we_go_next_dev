defmodule WeGoNextWeb.LogLiveIndexTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.{Accounts, CombatLogFile, FileWatcher, WarcraftLogs}
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Repo

  setup do
    Repo.delete_all(Encounter)
    Repo.delete_all(CombatLogFile)
    FileWatcher.stop_watching()
    on_exit(fn -> FileWatcher.stop_watching() end)

    :ok
  end

  test "renders a reimport action on each imported log row", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    first_log = insert_combat_log!(user, "/tmp/wgn-logs-row-one.log")
    second_log = insert_combat_log!(user, "/tmp/wgn-logs-row-two.log")

    insert_encounter!(first_log, %{start_time: ~U[2026-04-12 20:00:00Z]})
    insert_encounter!(second_log, %{start_time: ~U[2026-04-19 20:00:00Z]})

    html =
      conn
      |> get(~p"/logs")
      |> html_response(200)

    assert html =~ "Imported Logs"
    assert html =~ "wgn-logs-row-one.log"
    assert html =~ "wgn-logs-row-two.log"
    assert html =~ "First pull Apr 12, 2026"
    assert html =~ "First pull Apr 19, 2026"
    assert html =~ "Reimport"
    refute html =~ "Force Reimport Log"

    # Newest raid night first, regardless of parse order.
    {pos_two, _} = :binary.match(html, "wgn-logs-row-two.log")
    {pos_one, _} = :binary.match(html, "wgn-logs-row-one.log")
    assert pos_two < pos_one
  end

  test "toggles publish setting on imported log rows", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    log = insert_combat_log!(user, "/tmp/wgn-publish-toggle.log")
    insert_encounter!(log, %{start_time: ~U[2026-04-12 20:00:00Z]})

    html =
      conn
      |> get(~p"/logs")
      |> html_response(200)

    assert html =~ "Publish"
    assert html =~ ~s(phx-click="toggle_publish_enabled")
    refute Repo.get!(CombatLogFile, log.id).publish_enabled

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, user: user, combat_log_file: nil}
    }

    assert {:noreply, socket} =
             WeGoNextWeb.LogLive.Index.handle_event(
               "toggle_publish_enabled",
               %{"file_id" => to_string(log.id)},
               socket
             )

    assert Repo.get!(CombatLogFile, log.id).publish_enabled

    assert {:noreply, _socket} =
             WeGoNextWeb.LogLive.Index.handle_event(
               "toggle_publish_enabled",
               %{"file_id" => to_string(log.id)},
               socket
             )

    refute Repo.get!(CombatLogFile, log.id).publish_enabled
  end

  test "names a raid night locally and shows an appropriate default", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    log = insert_combat_log!(user, "/tmp/WoWCombatLog-071226_105733.txt")

    {:ok, view, html} = Phoenix.LiveViewTest.live(conn, ~p"/logs")

    assert html =~ "Raid Night — Jul 12, 2026"

    html =
      view
      |> Phoenix.LiveViewTest.form("#raid-night-name-#{log.id}", %{
        "raid_night" => %{"name" => "Sunday Mythic Progression"}
      })
      |> Phoenix.LiveViewTest.render_submit()

    assert html =~ "Sunday Mythic Progression"
    assert Repo.get!(CombatLogFile, log.id).raid_night_name == "Sunday Mythic Progression"
  end

  test "toggles live log watching and stops the active watcher", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    log = insert_combat_log!(user, "/tmp/wgn-watch-toggle.log")
    insert_encounter!(log, %{start_time: ~U[2026-04-12 20:00:00Z]})

    FileWatcher.watch(log)
    assert %CombatLogFile{id: id} = FileWatcher.current_file()
    assert id == log.id

    html = conn |> get(~p"/logs") |> html_response(200)
    assert html =~ "Watch"
    assert html =~ ~s(phx-click="toggle_watch_enabled")

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, user: user, combat_log_file: log}
    }

    assert {:noreply, _socket} =
             WeGoNextWeb.LogLive.Index.handle_event(
               "toggle_watch_enabled",
               %{"file_id" => to_string(log.id)},
               socket
             )

    refute Repo.get!(CombatLogFile, log.id).watch_enabled
    assert FileWatcher.current_file() == nil
  end

  test "renders watch control only for the newest live log", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    older = insert_combat_log!(user, "/tmp/WoWCombatLog-older.log")
    newer = insert_combat_log!(user, "/tmp/WoWCombatLog-newer.log")

    insert_encounter!(older, %{start_time: ~U[2026-04-12 20:00:00Z]})
    insert_encounter!(newer, %{start_time: ~U[2026-04-19 20:00:00Z]})

    html = conn |> get(~p"/logs") |> html_response(200)

    assert length(Regex.scan(~r/phx-click="toggle_watch_enabled"/, html)) == 1
  end

  test "rejects a forged watch event for an older live log" do
    user = Accounts.get_or_create_default_user()
    older = insert_combat_log!(user, "/tmp/WoWCombatLog-forged-older.log")
    _newer = insert_combat_log!(user, "/tmp/WoWCombatLog-forged-newer.log")

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, user: user, combat_log_file: nil}
    }

    assert {:noreply, socket} =
             WeGoNextWeb.LogLive.Index.handle_event(
               "toggle_watch_enabled",
               %{"file_id" => to_string(older.id)},
               socket
             )

    refute Repo.get!(CombatLogFile, older.id).watch_enabled
    assert Phoenix.Flash.get(socket.assigns.flash, :error) == "Failed to update watch setting"
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
      |> get(~p"/logs")
      |> html_response(200)

    assert html =~ "Warcraft Logs report URL"
    assert html =~ "WCL report abc123 fight 17"

    updated = Repo.get!(CombatLogFile, log.id)
    assert updated.warcraft_logs_report_url =~ "/reports/abc123"
    assert updated.warcraft_logs_report_code == "abc123"
    assert updated.warcraft_logs_fight_id == 17
    assert updated.warcraft_logs_linked_at
  end

  test "does not render the import selector on the logs page", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    log = insert_combat_log!(user, "/tmp/wgn-logs-no-import.log")
    insert_encounter!(log, %{start_time: ~U[2026-04-12 20:00:00Z]})

    html =
      conn
      |> get(~p"/logs")
      |> html_response(200)

    refute html =~ "Import Combat Log"
    refute html =~ ~s(phx-submit="import_log")
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
end
