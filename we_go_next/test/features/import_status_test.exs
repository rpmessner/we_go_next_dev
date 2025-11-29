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

    test "shows 'Reimport' button and '(complete)' after full import", %{session: session} do
      setup_user_with_fixtures()

      session
      |> HomePage.navigate()
      |> HomePage.ensure_page_loaded()
      |> HomePage.select_log_file()
      |> HomePage.click_import()
      |> HomePage.wait_for_encounters()

      # After import completes, button should say "Reimport" and log should show "(complete)"
      session
      |> HomePage.assert_import_button_text("Reimport")
      |> HomePage.assert_log_shows_complete()
    end

    test "shows purge button after import", %{session: session} do
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

      # Purge button appears after import
      assert HomePage.has_purge_button?(session)
    end

    test "purge removes encounters and resets to 'Import' button", %{session: session} do
      setup_user_with_fixtures()

      session
      |> HomePage.navigate()
      |> HomePage.ensure_page_loaded()
      |> HomePage.select_log_file()
      |> HomePage.click_import()
      |> HomePage.wait_for_encounters()

      # Verify we have encounters
      assert HomePage.encounter_count(session) > 0

      # Purge the log
      session
      |> HomePage.click_purge()

      # Wait for purge to complete
      Process.sleep(500)

      # Button should be back to "Import" and no encounters
      session
      |> HomePage.assert_import_button_text("Import")
      |> HomePage.assert_encounter_count(0)

      # Purge button should be gone
      refute HomePage.has_purge_button?(session)
    end
  end
end
