defmodule WeGoNextWeb.Features.LiveSyncTest do
  @moduledoc """
  Integration test that simulates the live combat log sync workflow:
  1. Import initial log with one encounter
  2. Simulate WoW appending a new encounter to the log file
  3. Click Refresh/Sync to detect the new encounter
  4. Verify the new encounter appears in the dashboard

  This tests Phase 2 and 3 of the Integration Roadmap without needing WoW running.
  """
  use WeGoNextWeb.FeatureCase, async: false

  import Wallaby.Query

  @fixtures_path Path.expand("../fixtures", __DIR__)
  @base_log_fixture Path.join(@fixtures_path, "WoWCombatLog-112725_120000.txt")
  @second_encounter_fixture Path.join(@fixtures_path, "second_encounter.txt")

  setup do
    # Create a temporary copy of the log file that we can modify during the test
    temp_dir = Path.join(System.tmp_dir!(), "we_go_next_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(temp_dir)

    temp_log_path = Path.join(temp_dir, "WoWCombatLog-112725_120000.txt")
    File.cp!(@base_log_fixture, temp_log_path)

    on_exit(fn ->
      # Clean up temp directory
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir, temp_log_path: temp_log_path}
  end

  feature "sync detects new encounter appended to log file", %{session: session, temp_dir: temp_dir, temp_log_path: temp_log_path} do
    # Set up the default user with the temp directory
    user = WeGoNext.Accounts.get_or_create_default_user()
    WeGoNext.Accounts.set_wow_logs_path(user, temp_dir)

    # Step 1: Visit home page and import initial log
    session =
      session
      |> visit("/")
      |> take_screenshot(name: "sync_01_home")

    assert_has(session, css("h1", text: "WoW Raid Diagnostic Tool"))

    # Select the log file
    second_option = find(session, css("select[name='log_path'] option:nth-child(2)"))
    option_value = Wallaby.Element.attr(second_option, "value")
    IO.puts("Initial import - selecting: #{option_value}")

    session =
      session
      |> execute_script("""
        var select = document.querySelector('select[name="log_path"]');
        select.value = '#{option_value}';
        select.dispatchEvent(new Event('change', { bubbles: true }));
      """)

    :timer.sleep(300)

    # Import the log
    session =
      session
      |> click(css("button[type='submit']"))

    # Wait for import to complete
    session = wait_for_encounters(session, 30_000)
    session = take_screenshot(session, name: "sync_02_initial_import")

    # Verify we have exactly 1 encounter (Test Boss)
    encounter_cards = all(session, css(".encounter-card"))
    assert length(encounter_cards) == 1, "Expected 1 encounter after initial import, got #{length(encounter_cards)}"

    # Verify it's the Test Boss encounter
    first_card = hd(encounter_cards)
    card_text = Wallaby.Element.text(first_card)
    assert String.contains?(card_text, "Test Boss"), "Expected Test Boss encounter"
    IO.puts("Initial import: Found 1 encounter - #{card_text}")

    # Step 2: Simulate WoW appending a new encounter to the log file
    IO.puts("Appending second encounter to log file...")
    second_encounter_content = File.read!(@second_encounter_fixture)
    File.write!(temp_log_path, second_encounter_content, [:append])

    # Verify file was modified
    {:ok, %{size: new_size}} = File.stat(temp_log_path)
    IO.puts("Log file size after append: #{new_size} bytes")

    session = take_screenshot(session, name: "sync_03_after_append")

    # Step 3: Click the Refresh button to sync
    IO.puts("Clicking Refresh button...")
    session =
      session
      |> click(css("button", text: "Refresh"))

    # Wait for the sync to complete
    :timer.sleep(2000)
    session = take_screenshot(session, name: "sync_04_after_refresh")

    # Step 4: Verify the new encounter appears
    # Wait for the second encounter to appear
    session = wait_for_element(session, css(".encounter-card", count: 2), 10_000)

    encounter_cards = all(session, css(".encounter-card"))
    assert length(encounter_cards) == 2, "Expected 2 encounters after sync, got #{length(encounter_cards)}"

    # Get the text from both cards
    card_texts = Enum.map(encounter_cards, &Wallaby.Element.text/1)
    IO.puts("After sync: #{length(encounter_cards)} encounters")
    Enum.each(card_texts, &IO.puts("  - #{&1}"))

    # Verify we have both encounters
    has_test_boss = Enum.any?(card_texts, &String.contains?(&1, "Test Boss"))
    has_second_boss = Enum.any?(card_texts, &String.contains?(&1, "Second Boss"))

    assert has_test_boss, "Expected Test Boss encounter to still be present"
    assert has_second_boss, "Expected Second Boss encounter after sync"

    # Verify the second encounter shows as a KILL (success=1 in fixture)
    second_boss_text = Enum.find(card_texts, &String.contains?(&1, "Second Boss"))
    assert String.contains?(second_boss_text, "KILL"), "Second Boss should show as KILL"

    session = take_screenshot(session, name: "sync_05_verified")

    # Step 5: Click on the new encounter and verify details
    second_encounter_card = Enum.find(encounter_cards, fn card ->
      String.contains?(Wallaby.Element.text(card), "Second Boss")
    end)

    Wallaby.Element.click(second_encounter_card)
    :timer.sleep(1000)

    session = take_screenshot(session, name: "sync_06_second_boss_detail")

    # Verify we're on the encounter detail page
    session = wait_for_element(session, css("h1.text-wow-gold"), 10_000)
    assert_has(session, css("h1.text-wow-gold", text: "Second Boss"))

    # Verify it's a kill
    assert has?(session, css(".bg-green-900", text: "KILL"))

    IO.puts("Live sync test completed successfully!")
    session
  end

  feature "multiple syncs detect multiple new encounters", %{session: session, temp_dir: temp_dir, temp_log_path: temp_log_path} do
    # Set up user
    user = WeGoNext.Accounts.get_or_create_default_user()
    WeGoNext.Accounts.set_wow_logs_path(user, temp_dir)

    IO.puts("Multi-sync test: temp_dir = #{temp_dir}")
    IO.puts("Multi-sync test: temp_log_path = #{temp_log_path}")
    IO.puts("Multi-sync test: file exists? #{File.exists?(temp_log_path)}")

    # Import initial log
    session =
      session
      |> visit("/")
      |> take_screenshot(name: "multi_01_home")

    # Wait a moment for the select to populate
    :timer.sleep(500)

    second_option = find(session, css("select[name='log_path'] option:nth-child(2)"))
    option_value = Wallaby.Element.attr(second_option, "value")
    IO.puts("Multi-sync test: selecting #{option_value}")

    session =
      session
      |> execute_script("""
        var select = document.querySelector('select[name="log_path"]');
        select.value = '#{option_value}';
        select.dispatchEvent(new Event('change', { bubbles: true }));
      """)

    :timer.sleep(300)
    session = click(session, css("button[type='submit']"))
    session = wait_for_encounters(session, 30_000)

    # Verify initial state: 1 encounter
    assert length(all(session, css(".encounter-card"))) == 1

    # First append: Add second encounter
    IO.puts("First append: Adding Second Boss...")
    second_encounter_content = File.read!(@second_encounter_fixture)
    File.write!(temp_log_path, second_encounter_content, [:append])

    session = click(session, css("button", text: "Refresh"))
    :timer.sleep(2000)
    session = wait_for_element(session, css(".encounter-card", count: 2), 10_000)
    assert length(all(session, css(".encounter-card"))) == 2
    IO.puts("After first sync: 2 encounters")

    # Second append: Add a third encounter (reuse second encounter fixture with different name)
    IO.puts("Second append: Adding Third Boss...")
    third_encounter = """
    11/27/2025 12:10:00.000-5  ENCOUNTER_START,2889,"Third Boss",15,20,2652
    11/27/2025 12:10:05.000-5  SPELL_DAMAGE,Creature-0-0-0-0-33333-00003333,"Third Boss",0x10a48,0x0,Player-0-0-0-0-00001-000AAAAA,"TestPlayer1",0x512,0x0,888888,"Shadow Strike",0x20,Player-0-0-0-0-00001-000AAAAA,0000000000000000,40000,35000,0,20,0,nil,nil,nil,nil,nil,nil,40000,-1,0,nil
    11/27/2025 12:10:30.000-5  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,Player-0-0-0-0-00001-000AAAAA,"TestPlayer1",0x512,0x0,-1
    11/27/2025 12:10:35.000-5  ENCOUNTER_END,2889,"Third Boss",15,20,0,35000
    """
    File.write!(temp_log_path, third_encounter, [:append])

    session = click(session, css("button", text: "Refresh"))
    :timer.sleep(2000)
    session = wait_for_element(session, css(".encounter-card", count: 3), 10_000)

    encounter_cards = all(session, css(".encounter-card"))
    assert length(encounter_cards) == 3, "Expected 3 encounters after second sync"

    card_texts = Enum.map(encounter_cards, &Wallaby.Element.text/1)
    IO.puts("After second sync: #{length(encounter_cards)} encounters")
    Enum.each(card_texts, &IO.puts("  - #{&1}"))

    # Verify all three bosses are present
    assert Enum.any?(card_texts, &String.contains?(&1, "Test Boss"))
    assert Enum.any?(card_texts, &String.contains?(&1, "Second Boss"))
    assert Enum.any?(card_texts, &String.contains?(&1, "Third Boss"))

    # Verify Third Boss shows as WIPE (success=0)
    third_boss_text = Enum.find(card_texts, &String.contains?(&1, "Third Boss"))
    assert String.contains?(third_boss_text, "WIPE"), "Third Boss should show as WIPE"

    session = take_screenshot(session, name: "multi_sync_final")
    IO.puts("Multiple syncs test completed successfully!")
    session
  end

  # Helper functions

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
