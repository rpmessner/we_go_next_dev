defmodule WeGoNextWeb.SettingsLiveTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.FileWatcher

  setup do
    FileWatcher.stop_watching()
    on_exit(fn -> FileWatcher.stop_watching() end)

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
end
