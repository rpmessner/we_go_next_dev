defmodule WeGoNextWeb.SettingsLiveTest do
  use WeGoNextWeb.ConnCase, async: false

  alias WeGoNext.Accounts
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
end
