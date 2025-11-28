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

  import Wallaby.Query

  # Use the test fixtures directory with a small log file
  @fixtures_path Path.expand("../fixtures", __DIR__)

  feature "complete flow: home -> import log -> view encounter summary", %{session: session} do
    # Set up the default user with the test fixtures path
    user = WeGoNext.Accounts.get_or_create_default_user()

    if user.wow_logs_path != @fixtures_path do
      WeGoNext.Accounts.set_wow_logs_path(user, @fixtures_path)
    end

    # Step 1: Visit home page
    session =
      session
      |> visit("/")
      |> take_screenshot(name: "flow_01_home_page")

    # Verify the page loads correctly
    assert_has(session, css("h1", text: "WoW Raid Diagnostic Tool"))
    assert_has(session, css("select[name='log_path']"))

    # Step 2: Select a log file
    second_option =
      session
      |> find(css("select[name='log_path'] option:nth-child(2)"))

    option_value = Wallaby.Element.attr(second_option, "value")
    IO.puts("Selecting log file: #{option_value}")

    # Use JavaScript to select the option (more reliable with LiveView)
    session =
      session
      |> execute_script("""
        var select = document.querySelector('select[name="log_path"]');
        select.value = '#{option_value}';
        select.dispatchEvent(new Event('change', { bubbles: true }));
      """)

    # Wait for LiveView to process
    :timer.sleep(300)
    session = take_screenshot(session, name: "flow_02_log_selected")

    # Verify button is enabled
    button = find(session, css("button[type='submit']"))
    disabled = Wallaby.Element.attr(button, "disabled")
    assert disabled != "true" and disabled != "disabled"

    # Step 3: Import the log file
    session =
      session
      |> click(css("button[type='submit']"))
      |> take_screenshot(name: "flow_03_importing")

    # Wait for import to complete (this can take a few seconds for large files)
    # Poll for encounters to appear
    session = wait_for_encounters(session, 30_000)
    session = take_screenshot(session, name: "flow_04_encounters_loaded")

    # Verify encounters are displayed
    assert_has(session, css(".encounter-card"))

    # Verify we have at least one encounter
    encounter_cards = all(session, css(".encounter-card"))
    assert length(encounter_cards) > 0, "Expected at least one encounter to be imported"
    IO.puts("Found #{length(encounter_cards)} encounters")

    # Step 4: Click the first encounter
    first_encounter = hd(encounter_cards)
    encounter_name = Wallaby.Element.text(first_encounter)
    IO.puts("Clicking encounter: #{encounter_name}")

    # Click the encounter card element directly
    Wallaby.Element.click(first_encounter)

    # Wait for navigation - LiveView needs time to process
    :timer.sleep(1000)
    session = take_screenshot(session, name: "flow_05_encounter_detail")

    # Debug: Get current URL
    current_url = Wallaby.Browser.current_url(session)
    IO.puts("Current URL: #{current_url}")

    # Step 5: Verify encounter detail page
    # Wait for the page to fully render by looking for the h1
    session = wait_for_element(session, css("h1.text-wow-gold"), 10_000)
    assert_has(session, css("h1.text-wow-gold"))

    # Wait for stat blocks to render
    session = wait_for_element(session, css(".stat-block", count: 5), 10_000)

    # Take another screenshot after waiting
    session = take_screenshot(session, name: "flow_05b_after_wait")

    # Should have the Summary tab active by default
    assert_has(session, css("button[phx-value-tab='summary']"))

    # Verify Summary tab content is visible (look for key elements)
    # The Summary tab shows either wipe cause or kill banner
    has_wipe_cause = has?(session, css(".bg-red-900\\/30"))
    has_kill_banner = has?(session, css(".bg-green-900\\/30"))
    has_next_pull_focus = has?(session, css("h3", text: "Next Pull Focus"))

    assert has_wipe_cause or has_kill_banner or has_next_pull_focus,
           "Summary tab should show wipe cause, kill banner, or next pull focus"

    session = take_screenshot(session, name: "flow_06_summary_verified")

    # Step 6: Verify other tabs are accessible
    session =
      session
      |> click(css("button[phx-value-tab='deaths']"))

    :timer.sleep(200)
    session = take_screenshot(session, name: "flow_07_deaths_tab")

    # Deaths tab should be visible now
    assert_has(session, css("button[phx-value-tab='deaths'].border-wow-gold"))

    # Step 7: Navigate back to home
    session =
      session
      |> click(css("a", text: "Back to encounters"))

    :timer.sleep(300)
    session = take_screenshot(session, name: "flow_08_back_to_home")

    # Verify we're back on the home page
    assert_has(session, css("h1", text: "WoW Raid Diagnostic Tool"))
    assert_has(session, css(".encounter-card"))

    IO.puts("Minimal flow test completed successfully!")
    session
  end

  # Helper to wait for encounters to appear with timeout
  defp wait_for_encounters(session, timeout_ms) when timeout_ms <= 0 do
    flunk("Timed out waiting for encounters to load")
    session
  end

  defp wait_for_encounters(session, timeout_ms) do
    if has?(session, css(".encounter-card")) do
      session
    else
      :timer.sleep(500)
      wait_for_encounters(session, timeout_ms - 500)
    end
  end

  # Helper to wait for a specific element with timeout
  defp wait_for_element(session, query, timeout_ms) when timeout_ms <= 0 do
    flunk("Timed out waiting for element: #{inspect(query)}")
    session
  end

  defp wait_for_element(session, query, timeout_ms) do
    if has?(session, query) do
      session
    else
      :timer.sleep(200)
      wait_for_element(session, query, timeout_ms - 200)
    end
  end
end
