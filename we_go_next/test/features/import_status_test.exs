defmodule WeGoNext.Features.ImportStatusTest do
  use WeGoNextWeb.FeatureCase, async: false

  @moduletag :feature

  describe "import status indicators" do
    test "shows 'Import' button for new log files", %{session: session} do
      setup_user_with_fixtures()

      session
      |> HomePage.navigate()
      |> HomePage.ensure_page_loaded()
      |> HomePage.select_log_file()
      |> HomePage.assert_import_button_text("Import")
    end

    test "moves imported logs to the imported logs list with reimport action", %{session: session} do
      setup_user_with_fixtures()

      session
      |> HomePage.navigate()
      |> HomePage.ensure_page_loaded()
      |> HomePage.select_log_file()
      |> HomePage.click_import()
      |> HomePage.wait_for_encounters()

      session
      |> HomePage.assert_imported_logs_visible()

      assert HomePage.has_reimport_button?(session)
    end

    test "does not expose purge controls after import", %{session: session} do
      setup_user_with_fixtures()

      session
      |> HomePage.navigate()
      |> HomePage.ensure_page_loaded()
      |> HomePage.select_log_file()

      # No purge button before import
      refute HomePage.has_purge_button?(session)

      session
      |> HomePage.click_import()
      |> HomePage.wait_for_encounters()

      refute HomePage.has_purge_button?(session)
    end

    test "reimport action reparses an imported log", %{session: session} do
      setup_user_with_fixtures()

      session
      |> HomePage.navigate()
      |> HomePage.ensure_page_loaded()
      |> HomePage.select_log_file()
      |> HomePage.click_import()
      |> HomePage.wait_for_encounters()

      # Verify we have encounters
      assert HomePage.encounter_count(session) > 0

      session
      |> HomePage.click_reimport()
      |> HomePage.wait_for_encounters()

      assert HomePage.encounter_count(session) > 0
    end
  end
end
