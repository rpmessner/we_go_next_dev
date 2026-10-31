defmodule WeGoNextWeb.SettingsLiveTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Accounts
  alias WeGoNext.{CombatLogFile, EncounterStore, FileWatcher, Repo}
  import Phoenix.LiveViewTest

  setup do
    FileWatcher.stop_watching()
    FileWatcher.clear_display()
    on_exit(fn -> WeGoNext.FileWatcherCleanup.stop() end)

    :ok
  end

  test "renders log folder configuration without duplicate import controls", %{conn: conn} do
    html =
      conn
      |> get(~p"/settings")
      |> html_response(200)

    assert html =~ "WoW Combat Logs Folder"
    assert html =~ "Current Configuration"
    refute html =~ "Import Logs"
    refute html =~ "Import Most Recent Log"
    refute html =~ "Import Selected Log"
    refute html =~ "Choose a log file..."
  end

  test "configuration shows the displayed archive rather than the stored last-loaded path", %{
    conn: conn
  } do
    user = Accounts.get_or_create_default_user()
    {:ok, _} = Accounts.set_last_loaded_log(user, "/tmp/WoWCombatLog-081926_205942.txt")
    log = log!(user, "Archive-WoWCombatLog-090626.txt", :warcraftlogs_archive)
    assert {:ok, 0} = EncounterStore.load_from_db(log.id)

    {:ok, view, _} = live(conn, ~p"/settings")

    assert render(view) =~ Path.basename(log.file_path)
    refute render(view) =~ "WoWCombatLog-081926_205942.txt"
    assert has_element?(view, "#settings-displayed-log", Path.basename(log.file_path))
    assert has_element?(view, "#settings-watched-log", "None")
    refute render(view) =~ "Last Loaded Log:"
  end

  test "fresh encounter list default becomes the displayed log in Settings", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    older = log!(user, "Archive-WoWCombatLog-090526.txt", :warcraftlogs_archive)
    newest = log!(user, "Archive-WoWCombatLog-090626.txt", :warcraftlogs_archive)

    for {log, parsed_at} <- [
          {older, ~U[2026-09-05 20:00:00Z]},
          {newest, ~U[2026-09-06 20:00:00Z]}
        ] do
      log |> Ecto.Changeset.change(last_parsed_at: parsed_at) |> Repo.update!()
    end

    assert FileWatcher.displayed_file() == nil
    {:ok, encounters, _} = live(conn, ~p"/")
    assert has_element?(encounters, "option[selected]", Path.basename(newest.file_path))

    {:ok, settings, _} = live(conn, ~p"/settings")
    assert has_element?(settings, "#settings-displayed-log", Path.basename(newest.file_path))
    assert has_element?(settings, "#settings-watched-log", "None")
    assert FileWatcher.displayed_file().id == newest.id
    assert FileWatcher.current_file() == nil
  end

  test "mounting encounters keeps an existing displayed log and an independent watch", %{
    conn: conn
  } do
    user = Accounts.get_or_create_default_user()
    archive = log!(user, "Archive-WoWCombatLog-090626.txt", :warcraftlogs_archive)
    watched = log!(user, "WoWCombatLog-103126_200000.txt", :live)
    assert :ok = FileWatcher.display(archive)
    assert :ok = FileWatcher.watch(watched)

    {:ok, encounters, _} = live(conn, ~p"/")
    assert has_element?(encounters, "option[selected]", Path.basename(archive.file_path))
    {:ok, settings, _} = live(conn, ~p"/settings")
    assert has_element?(settings, "#settings-displayed-log", Path.basename(archive.file_path))
    assert has_element?(settings, "#settings-watched-log", Path.basename(watched.file_path))
    assert FileWatcher.displayed_file().id == archive.id
    assert FileWatcher.current_file().id == watched.id
  end

  test "open Settings follows archive selection and clearing without a watch change", %{
    conn: conn
  } do
    user = Accounts.get_or_create_default_user()
    first = log!(user, "Archive-WoWCombatLog-090626.txt", :warcraftlogs_archive)
    second = log!(user, "Archive-WoWCombatLog-090726.txt", :warcraftlogs_archive)
    {:ok, view, _} = live(conn, ~p"/settings")
    assert has_element?(view, "#settings-displayed-log", "None")

    for log <- [first, second] do
      assert {:ok, 0} = EncounterStore.load_from_db(log.id)
      assert has_element?(view, "#settings-displayed-log", Path.basename(log.file_path))
      assert has_element?(view, "#settings-watched-log", "None")
    end

    assert :ok = FileWatcher.clear_display()
    assert has_element?(view, "#settings-displayed-log", "None")
  end

  test "watch notifications update the watched log without replacing the displayed archive", %{
    conn: conn
  } do
    user = Accounts.get_or_create_default_user()
    archive = log!(user, "Archive-WoWCombatLog-090626.txt", :warcraftlogs_archive)
    watched = log!(user, "WoWCombatLog-103126_200000.txt", :live)
    assert :ok = FileWatcher.display(archive)
    {:ok, view, _} = live(conn, ~p"/settings")

    assert :ok = FileWatcher.watch(watched)
    assert has_element?(view, "#settings-watched-log", Path.basename(watched.file_path))
    assert has_element?(view, "#settings-displayed-log", Path.basename(archive.file_path))

    assert :ok = FileWatcher.stop_watching()
    assert has_element?(view, "#settings-watched-log", "None")
    assert has_element?(view, "#settings-displayed-log", Path.basename(archive.file_path))
  end

  test "watch notifications refresh the displayed file after archival renames it", %{conn: conn} do
    user = Accounts.get_or_create_default_user()
    log = log!(user, "WoWCombatLog-090626_200000.txt", :live)
    assert :ok = FileWatcher.display(log)
    {:ok, view, _} = live(conn, ~p"/settings")

    log
    |> Ecto.Changeset.change(
      file_path: "/tmp/Archive-WoWCombatLog-090626.txt",
      source: :warcraftlogs_archive
    )
    |> Repo.update!()

    Phoenix.PubSub.broadcast(WeGoNext.PubSub, "encounters", {:watch_stopped, log.id, :refresh})
    assert has_element?(view, "#settings-displayed-log", "Archive-WoWCombatLog-090626.txt")
  end

  test "renders saved Warcraft Logs credentials without rendering the key", %{conn: conn} do
    user = Accounts.get_or_create_default_user()

    assert {:ok, _user} =
             Accounts.set_warcraft_logs_credentials(user, "Local WCL Client", "secret-api-key")

    html =
      conn
      |> get(~p"/settings")
      |> html_response(200)

    assert html =~ "Warcraft Logs Credentials"
    assert html =~ "Configured"
    assert html =~ "Local WCL Client"
    assert html =~ "key saved"
    refute html =~ "secret-api-key"
  end

  defp log!(user, filename, source) do
    Repo.insert!(%CombatLogFile{
      user_id: user.id,
      file_path: Path.join(System.tmp_dir!(), filename),
      source: source
    })
  end
end
