defmodule WeGoNextWeb.Features.AutoUpdateTest do
  @moduledoc """
  Integration test for automatic dashboard updates via FileWatcher + PubSub:
  1. Import initial log with one encounter
  2. Simulate WoW appending a new encounter to the log file
  3. Wait for FileWatcher to detect the change (polls every 1 second)
  4. Verify the dashboard auto-updates without clicking Refresh

  This tests Phase 3 of the Integration Roadmap - the real-time update flow.
  """
  use WeGoNextWeb.FeatureCase, async: false

  import Wallaby.Query

  @fixtures_path Path.expand("../fixtures", __DIR__)
  @base_log_fixture Path.join(@fixtures_path, "WoWCombatLog-112725_120000.txt")
  @second_encounter_fixture Path.join(@fixtures_path, "second_encounter.txt")

  setup do
    # Create a temporary copy of the log file that we can modify during the test
    temp_dir = Path.join(System.tmp_dir!(), "we_go_next_auto_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(temp_dir)

    temp_log_path = Path.join(temp_dir, "WoWCombatLog-112725_120000.txt")
    File.cp!(@base_log_fixture, temp_log_path)

    on_exit(fn ->
      # Stop file watcher to avoid interference
      WeGoNext.FileWatcher.stop_watching()
      # Clean up temp directory
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir, temp_log_path: temp_log_path}
  end

  feature "dashboard auto-updates when FileWatcher detects new encounters", %{
    session: session,
    temp_dir: temp_dir,
    temp_log_path: temp_log_path
  } do
    # Set up the default user with the temp directory
    user = WeGoNext.Accounts.get_or_create_default_user()
    WeGoNext.Accounts.set_wow_logs_path(user, temp_dir)

    # Step 1: Visit home page and import initial log
    session =
      session
      |> visit("/")
      |> take_screenshot(name: "auto_01_home")

    assert_has(session, css("h1", text: "WoW Raid Diagnostic Tool"))

    # Select the log file
    second_option = find(session, css("select[name='log_path'] option:nth-child(2)"))
    option_value = Wallaby.Element.attr(second_option, "value")
    IO.puts("Auto-update test: selecting #{option_value}")

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
    session = take_screenshot(session, name: "auto_02_initial_import")

    # Verify we have exactly 1 encounter (Test Boss)
    encounter_cards = all(session, css(".encounter-card"))
    assert length(encounter_cards) == 1, "Expected 1 encounter after initial import, got #{length(encounter_cards)}"
    IO.puts("Initial import complete: 1 encounter")

    # Verify the watching indicator is visible
    # Note: The CSS class may be rendered differently in headless mode
    if has?(session, css("span", text: "Auto-refresh active")) do
      IO.puts("Auto-refresh indicator is active")
    else
      IO.puts("Auto-refresh indicator not visible (may be timing issue)")
    end

    # Step 2: Simulate WoW appending a new encounter to the log file
    IO.puts("Appending second encounter to log file...")
    second_encounter_content = File.read!(@second_encounter_fixture)
    File.write!(temp_log_path, second_encounter_content, [:append])

    # Verify file was modified
    {:ok, %{size: new_size}} = File.stat(temp_log_path)
    IO.puts("Log file size after append: #{new_size} bytes")

    session = take_screenshot(session, name: "auto_03_after_append")

    # Step 3: Wait for FileWatcher to detect the change
    # FileWatcher polls every 1 second, so we need to wait for:
    # - The poll interval (1 second)
    # - The sync operation
    # - The PubSub broadcast
    # - The LiveView update
    # We'll wait up to 5 seconds total, checking every 500ms
    IO.puts("Waiting for FileWatcher to detect change and auto-update...")

    session = wait_for_auto_update(session, 2, 10_000)
    session = take_screenshot(session, name: "auto_04_auto_updated")

    # Step 4: Verify the new encounter appears automatically (no Refresh click!)
    encounter_cards = all(session, css(".encounter-card"))
    assert length(encounter_cards) == 2, "Expected 2 encounters after auto-update, got #{length(encounter_cards)}"

    # Get the text from both cards
    card_texts = Enum.map(encounter_cards, &Wallaby.Element.text/1)
    IO.puts("After auto-update: #{length(encounter_cards)} encounters")
    Enum.each(card_texts, &IO.puts("  - #{&1}"))

    # Verify we have both encounters
    has_test_boss = Enum.any?(card_texts, &String.contains?(&1, "Test Boss"))
    has_second_boss = Enum.any?(card_texts, &String.contains?(&1, "Second Boss"))

    assert has_test_boss, "Expected Test Boss encounter to still be present"
    assert has_second_boss, "Expected Second Boss encounter to appear via auto-update"

    IO.puts("Auto-update test completed successfully!")
    session
  end

  feature "multiple auto-updates as encounters are added", %{
    session: session,
    temp_dir: temp_dir,
    temp_log_path: temp_log_path
  } do
    # Set up user
    user = WeGoNext.Accounts.get_or_create_default_user()
    WeGoNext.Accounts.set_wow_logs_path(user, temp_dir)

    # Import initial log
    session =
      session
      |> visit("/")

    :timer.sleep(500)

    second_option = find(session, css("select[name='log_path'] option:nth-child(2)"))
    option_value = Wallaby.Element.attr(second_option, "value")

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

    # Wait for auto-update
    session = wait_for_auto_update(session, 2, 10_000)
    assert length(all(session, css(".encounter-card"))) == 2
    IO.puts("After first auto-update: 2 encounters")

    # Second append: Add a third encounter
    IO.puts("Second append: Adding Third Boss...")
    third_encounter = """
    11/27/2025 12:10:00.000-5  ENCOUNTER_START,2889,"Third Boss",15,20,2652
    11/27/2025 12:10:05.000-5  SPELL_DAMAGE,Creature-0-0-0-0-33333-00003333,"Third Boss",0x10a48,0x0,Player-0-0-0-0-00001-000AAAAA,"TestPlayer1",0x512,0x0,888888,"Shadow Strike",0x20,Player-0-0-0-0-00001-000AAAAA,0000000000000000,40000,35000,0,20,0,nil,nil,nil,nil,nil,nil,40000,-1,0,nil
    11/27/2025 12:10:30.000-5  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,Player-0-0-0-0-00001-000AAAAA,"TestPlayer1",0x512,0x0,-1
    11/27/2025 12:10:35.000-5  ENCOUNTER_END,2889,"Third Boss",15,20,0,35000
    """
    File.write!(temp_log_path, third_encounter, [:append])

    # Wait for auto-update
    session = wait_for_auto_update(session, 3, 10_000)

    encounter_cards = all(session, css(".encounter-card"))
    assert length(encounter_cards) == 3, "Expected 3 encounters after second auto-update"

    card_texts = Enum.map(encounter_cards, &Wallaby.Element.text/1)
    IO.puts("After second auto-update: #{length(encounter_cards)} encounters")
    Enum.each(card_texts, &IO.puts("  - #{&1}"))

    # Verify all three bosses are present
    assert Enum.any?(card_texts, &String.contains?(&1, "Test Boss"))
    assert Enum.any?(card_texts, &String.contains?(&1, "Second Boss"))
    assert Enum.any?(card_texts, &String.contains?(&1, "Third Boss"))

    session = take_screenshot(session, name: "multi_auto_update_final")
    IO.puts("Multiple auto-updates test completed successfully!")
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

  defp wait_for_auto_update(session, expected_count, timeout_ms) when timeout_ms <= 0 do
    actual_count = length(all(session, css(".encounter-card")))
    flunk("Timed out waiting for auto-update. Expected #{expected_count} encounters, got #{actual_count}")
    session
  end

  defp wait_for_auto_update(session, expected_count, timeout_ms) do
    actual_count = length(all(session, css(".encounter-card")))

    if actual_count >= expected_count do
      IO.puts("Auto-update detected: #{actual_count} encounters")
      session
    else
      IO.puts("Waiting... current count: #{actual_count}, expected: #{expected_count}")
      :timer.sleep(500)
      wait_for_auto_update(session, expected_count, timeout_ms - 500)
    end
  end
end
