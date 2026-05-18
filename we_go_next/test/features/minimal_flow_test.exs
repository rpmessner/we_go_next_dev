defmodule WeGoNextWeb.Features.MinimalFlowTest do
  @moduledoc """
  End-to-end integration test for the core user flow:
  1. Home page loads
  2. User selects and imports a combat log
  3. Encounters appear in the list

  Legacy encounter analysis detail pages were pruned in favor of gold-tier views.
  This test validates the remaining import and encounter-list workflow.
  """
  use WeGoNextWeb.FeatureCase, async: false

  feature "complete flow: home -> import log -> view encounter list", %{session: session} do
    setup_user_with_fixtures()

    session
    |> HomePage.navigate()
    |> HomePage.ensure_page_loaded()
    |> take_screenshot(name: "flow_01_home_page")
    |> HomePage.select_log_file()
    |> take_screenshot(name: "flow_02_log_selected")
    |> HomePage.click_import()
    |> take_screenshot(name: "flow_03_importing")
    |> HomePage.wait_for_encounters()
    |> take_screenshot(name: "flow_04_encounters_loaded")
    |> HomePage.assert_encounter_count(1)
    |> HomePage.assert_encounter_present("Test Boss")
    |> HomePage.assert_encounter_shows_wipe("Test Boss")

    IO.puts("Minimal flow test completed successfully!")
  end
end
