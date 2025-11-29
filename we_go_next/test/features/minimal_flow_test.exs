defmodule WeGoNextWeb.Features.MinimalFlowTest do
  @moduledoc """
  End-to-end integration test for the core user flow:
  1. Home page loads
  2. User selects and imports a combat log
  3. Encounters appear in the list
  4. User clicks an encounter
  5. Encounter detail page shows with Summary tab

  This validates Phase 4 of the Integration Roadmap.
  """
  use WeGoNextWeb.FeatureCase, async: false

  feature "complete flow: home -> import log -> view encounter summary", %{session: session} do
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
    |> HomePage.click_first_encounter()
    |> take_screenshot(name: "flow_05_encounter_detail")
    |> EncounterDetailPage.ensure_page_loaded()
    |> EncounterDetailPage.assert_stat_blocks_visible()
    |> take_screenshot(name: "flow_05b_after_wait")
    |> EncounterDetailPage.assert_summary_content_visible()
    |> take_screenshot(name: "flow_06_summary_verified")
    |> EncounterDetailPage.click_deaths_tab()
    |> take_screenshot(name: "flow_07_deaths_tab")
    |> EncounterDetailPage.assert_tab_active("deaths")
    |> EncounterDetailPage.go_back_to_encounters()
    |> take_screenshot(name: "flow_08_back_to_home")
    |> HomePage.ensure_page_loaded()

    IO.puts("Minimal flow test completed successfully!")
  end
end
