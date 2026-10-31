defmodule WeGoNextWeb.PageStateTest do
  use WeGoNextWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias WeGoNext.{Accounts, CombatLogFile, FileWatcher, Repo}
  alias WeGoNext.FileIngest.Operation

  setup do
    FileWatcher.stop_watching()
    on_exit(fn -> WeGoNext.FileWatcherCleanup.stop() end)
    user = Accounts.get_or_create_default_user()
    Repo.delete_all(Operation)
    {:ok, user} = Accounts.set_wow_logs_path(user, System.tmp_dir!())
    %{user: user}
  end

  test "open Settings follows watch start and stop without remounting", %{conn: conn, user: user} do
    log =
      Repo.insert!(%CombatLogFile{
        user_id: user.id,
        file_path: "/tmp/pages-watch.log",
        source: :live
      })

    {:ok, view, _} = live(conn, "/settings")
    assert :ok = FileWatcher.watch(log)
    assert render(view) =~ "pages-watch.log"
    assert :ok = FileWatcher.stop_watching(log)
    refute render(view) =~ "pages-watch.log"
  end

  test "all open pages follow a watch change from Logs", %{conn: conn, user: user} do
    log =
      Repo.insert!(%CombatLogFile{
        user_id: user.id,
        file_path: "/tmp/WoWCombatLog-103126_200000.txt",
        source: :live
      })

    {:ok, encounters, _} = live(conn, "/")
    {:ok, logs, _} = live(conn, "/logs")
    {:ok, settings, _} = live(conn, "/settings")
    logs |> element("#watch-log-#{log.id}") |> render_click()
    assert has_element?(encounters, "#watch-newest-log[checked]")
    assert render(settings) =~ "WoWCombatLog-103126_200000.txt"
    settings |> element("button[phx-click=toggle_watch_enabled]") |> render_click()
    refute has_element?(logs, "#watch-log-#{log.id}[checked]")
    refute has_element?(encounters, "#watch-newest-log[checked]")
    assert has_element?(settings, "#settings-watched-log", "None")
    assert has_element?(settings, "#settings-displayed-log", "WoWCombatLog-103126_200000.txt")
  end

  test "Encounter list reconciles the imported selector after a lost completion", %{
    conn: conn,
    user: user
  } do
    receipt = receipt!(user, "importing", nil, 60)
    {:ok, view, _} = live(conn, "/")
    Repo.insert!(%CombatLogFile{user_id: user.id, file_path: receipt.path, source: :live})
    receipt |> Ecto.Changeset.change(status: "complete", encounters: 1) |> Repo.update!()
    send(view.pid, :reconcile_import)
    assert render(view) =~ "Re-import"
    assert has_element?(view, "option[value='/tmp/pages-import.log'][selected]")
  end

  test "Logs reconciles the current selection after a lost completion", %{conn: conn, user: user} do
    receipt = receipt!(user, "importing", nil, 60)
    {:ok, view, _} = live(conn, "/logs")
    log = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: receipt.path, source: :live})
    FileWatcher.display(log)
    receipt |> Ecto.Changeset.change(status: "complete", encounters: 1) |> Repo.update!()
    send(view.pid, :reconcile_import)
    assert render(view) =~ "Current"
  end

  test "Logs load modes recover from a failed selection without keeping its error", %{
    conn: conn,
    user: user
  } do
    log =
      Repo.insert!(%CombatLogFile{
        user_id: user.id,
        file_path: "/tmp/pages-load.log",
        source: :live
      })

    {:ok, view, _} = live(conn, "/logs")
    assert has_element?(view, "[data-load-state=idle]")
    render_click(view, "load_imported", %{"file_id" => "-1"})
    assert render_async(view) =~ "Failed to load"
    assert has_element?(view, "[data-load-state=failed]")

    :sys.suspend(FileWatcher)

    try do
      html = render_click(view, "load_imported", %{"file_id" => to_string(log.id)})
      assert html =~ ~s(data-load-state="loading")
      refute html =~ "Failed to load"
    after
      :sys.resume(FileWatcher)
    end

    assert render_async(view) =~ "Loaded 0 encounters from database"
    assert has_element?(view, "[data-load-state=idle]")
    refute render(view) =~ "Failed to load"
  end

  test "Settings path modes remain mutually exclusive", %{conn: conn} do
    {:ok, view, _} = live(conn, "/settings")
    assert render(view) =~ "✓ Folder found"
    html = render_change(view, "validate_path", %{"path" => "/not/a/real/wgn-folder"})
    assert html =~ "Folder not found"
    refute html =~ "✓ Folder found"
    html = render_change(view, "validate_path", %{"path" => ""})
    refute html =~ "Folder not found"
    refute html =~ "✓ Folder found"
    assert has_element?(view, "form[phx-submit=save_path] button[disabled]")
  end

  for path <- ["/", "/logs"] do
    test "#{path} observes an import started in another tab", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, unquote(path))
      refute html =~ "0%"
      receipt = receipt!(user, "importing", nil, 60)

      Phoenix.PubSub.broadcast(
        WeGoNext.PubSub,
        WeGoNext.ImportWorker.progress_topic(user.id),
        {:import_started, receipt.token}
      )

      assert render(view) =~ "0%"
      refute render(view) =~ "Failed to import"
    end

    test "#{path} reconciles a missed completion and ignores late progress", %{
      conn: conn,
      user: user
    } do
      receipt = receipt!(user, "importing", nil, 60)
      {:ok, view, html} = live(conn, unquote(path))
      assert html =~ "0%"
      send(view.pid, {:import_progress, %{bytes_read: 25, total_bytes: 100, encounters_found: 1}})
      assert render(view) =~ "25%"
      receipt |> Ecto.Changeset.change(status: "complete", encounters: 1) |> Repo.update!()
      send(view.pid, :reconcile_import)
      refute render(view) =~ "25%"
      send(view.pid, {:import_progress, %{bytes_read: 50, total_bytes: 100, encounters_found: 1}})
      refute render(view) =~ "50%"
      refute render(view) =~ "Importing..."
    end

    test "#{path} times out at the receipt deadline even without a completion", %{
      conn: conn,
      user: user
    } do
      receipt = receipt!(user, "importing", nil, 60)
      {:ok, view, html} = live(conn, unquote(path))
      assert html =~ "0%"

      receipt
      |> Ecto.Changeset.change(deadline: DateTime.add(DateTime.utc_now(), -1))
      |> Repo.update!()

      send(view.pid, :reconcile_import)
      assert render(view) =~ "Import timed out"
      refute render(view) =~ "0%"
      refute render(view) =~ "Importing..."
    end

    test "#{path} restores a durable ingest timeout", %{conn: conn, user: user} do
      receipt!(user, "failed", ":ingest_timeout", -1)
      {:ok, view, _} = live(conn, unquote(path))
      assert render(view) =~ "Import timed out"
      refute render(view) =~ "0%"
    end

    test "#{path} restores failed import receipts", %{conn: conn, user: user} do
      Repo.insert!(%Operation{
        user_id: user.id,
        token: Ecto.UUID.generate(),
        path: "/tmp/failed.log",
        status: "failed",
        error: "disk unavailable",
        started_at: DateTime.utc_now(),
        deadline: DateTime.utc_now()
      })

      {:ok, view, _} = live(conn, unquote(path))
      assert render(view) =~ "disk unavailable"
      refute render(view) =~ "Importing..."
    end
  end

  defp receipt!(user, status, error, seconds) do
    Repo.insert!(%Operation{
      user_id: user.id,
      token: Ecto.UUID.generate(),
      path: "/tmp/pages-import.log",
      status: status,
      error: error,
      started_at: DateTime.utc_now(),
      deadline: DateTime.add(DateTime.utc_now(), seconds)
    })
  end
end
