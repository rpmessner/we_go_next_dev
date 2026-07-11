defmodule WeGoNextWeb.Features.LiveSyncTest do
  @moduledoc """
  Integration test that simulates the live combat log sync workflow:
  1. Import initial log with one encounter from the home page
  2. Simulate WoW appending a new encounter to the log file
  3. Reimport the log (from the logs page) to detect the new encounter
  4. Verify the new encounter appears in the dashboard

  This tests Phase 2 and 3 of the Integration Roadmap without needing WoW running.
  """
  use WeGoNextWeb.FeatureCase, async: false

  @fixtures_path Path.expand("../fixtures", __DIR__)
  @base_log_fixture Path.join(@fixtures_path, "combat_log_base.txt")
  @second_encounter_fixture Path.join(@fixtures_path, "second_encounter.txt")

  setup do
    # Create a temporary copy of the log file that we can modify during the test
    temp_dir = Path.join(System.tmp_dir!(), "we_go_next_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(temp_dir)

    temp_log_path = Path.join(temp_dir, "WoWCombatLog-112725_120000.txt")
    File.cp!(@base_log_fixture, temp_log_path)

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir, temp_log_path: temp_log_path}
  end

  feature "sync detects new encounter appended to log file", %{
    session: session,
    temp_dir: temp_dir,
    temp_log_path: temp_log_path
  } do
    setup_user_with_path(temp_dir)

    # Step 1: Import initial log
    session
    |> HomePage.navigate()
    |> HomePage.ensure_page_loaded()
    |> take_screenshot(name: "sync_01_home")
    |> HomePage.select_log_file()
    |> HomePage.click_import()
    |> HomePage.wait_for_encounters()
    |> take_screenshot(name: "sync_02_initial_import")
    |> HomePage.assert_encounter_count(1)
    |> HomePage.assert_encounter_present("Test Boss")

    IO.puts("Initial import: Found 1 encounter - Test Boss")

    # Step 2: Simulate WoW appending a new encounter
    IO.puts("Appending second encounter to log file...")
    second_encounter_content = File.read!(@second_encounter_fixture)
    File.write!(temp_log_path, second_encounter_content, [:append])

    {:ok, %{size: new_size}} = File.stat(temp_log_path)
    IO.puts("Log file size after append: #{new_size} bytes")

    take_screenshot(session, name: "sync_03_after_append")

    # Step 3: Reimport (from the logs page) to parse the appended encounter
    IO.puts("Clicking Reimport button...")

    session
    |> LogsPage.navigate()
    |> LogsPage.click_reimport()
    |> LogsPage.wait_for_import_complete()

    take_screenshot(session, name: "sync_04_after_refresh")

    # Step 4: Verify new encounter appears
    session
    |> HomePage.navigate()
    |> HomePage.wait_for_encounter_count(2)
    |> HomePage.assert_encounter_count(2)
    |> HomePage.assert_encounter_present("Test Boss")
    |> HomePage.assert_encounter_present("Second Boss")
    |> HomePage.assert_encounter_shows_kill("Second Boss")

    IO.puts("After sync: 2 encounters")
    take_screenshot(session, name: "sync_05_verified")

    IO.puts("Live sync test completed successfully!")
  end

  feature "multiple syncs detect multiple new encounters", %{
    session: session,
    temp_dir: temp_dir,
    temp_log_path: temp_log_path
  } do
    setup_user_with_path(temp_dir)

    IO.puts("Multi-sync test: temp_dir = #{temp_dir}")

    # Import initial log
    session
    |> HomePage.navigate()
    |> take_screenshot(name: "multi_01_home")

    Process.sleep(500)

    session
    |> HomePage.select_log_file()
    |> HomePage.click_import()
    |> HomePage.wait_for_encounters()
    |> HomePage.assert_encounter_count(1)

    # First append: Add second encounter
    IO.puts("First append: Adding Second Boss...")
    second_encounter_content = File.read!(@second_encounter_fixture)
    File.write!(temp_log_path, second_encounter_content, [:append])

    session
    |> LogsPage.navigate()
    |> LogsPage.click_reimport()
    |> LogsPage.wait_for_import_complete()

    session
    |> HomePage.navigate()
    |> HomePage.wait_for_encounter_count(2)
    |> HomePage.assert_encounter_count(2)

    IO.puts("After first sync: 2 encounters")

    # Second append: Add a third encounter
    IO.puts("Second append: Adding Third Boss...")

    third_encounter = """
    11/27/2025 12:10:00.000-5  ENCOUNTER_START,2889,"Third Boss",15,20,2652
    11/27/2025 12:10:05.000-5  SPELL_DAMAGE,Creature-0-0-0-0-33333-00003333,"Third Boss",0x10a48,0x0,Player-0-0-0-0-00001-000AAAAA,"TestPlayer1",0x512,0x0,888888,"Shadow Strike",0x20,Player-0-0-0-0-00001-000AAAAA,0000000000000000,40000,35000,0,20,0,0,0,0,1,0,0,0,0.0,0.0,2652,0.0,90,40000,40000,-1,32,0,0,0,nil,nil,nil
    11/27/2025 12:10:30.000-5  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,Player-0-0-0-0-00001-000AAAAA,"TestPlayer1",0x512,0x0,0
    11/27/2025 12:10:35.000-5  ENCOUNTER_END,2889,"Third Boss",15,20,0,35000
    """

    File.write!(temp_log_path, third_encounter, [:append])

    session
    |> LogsPage.navigate()
    |> LogsPage.click_reimport()
    |> LogsPage.wait_for_import_complete()

    session
    |> HomePage.navigate()
    |> HomePage.wait_for_encounter_count(3)
    |> HomePage.assert_encounter_count(3)
    |> HomePage.assert_encounter_present("Test Boss")
    |> HomePage.assert_encounter_present("Second Boss")
    |> HomePage.assert_encounter_present("Third Boss")
    |> HomePage.assert_encounter_shows_wipe("Third Boss")

    IO.puts("After second sync: 3 encounters")
    take_screenshot(session, name: "multi_sync_final")
    IO.puts("Multiple syncs test completed successfully!")
  end
end
