defmodule WeGoNextWeb.Features.EncounterListTest do
  @moduledoc """
  Tests for the encounter list functionality on the home page.
  """
  use WeGoNextWeb.FeatureCase, async: false

  @wow_logs_path "/mnt/g/World of Warcraft/_retail_/Logs"

  feature "user can select and load a combat log", %{session: session} do
    setup_user_with_path(@wow_logs_path)

    session
    |> HomePage.navigate()
    |> HomePage.ensure_page_loaded()
    |> take_screenshot(name: "01_initial_page")

    # Verify import button is initially disabled
    refute HomePage.import_button_enabled?(session)
    IO.puts("Button disabled BEFORE select: true")

    session
    |> HomePage.select_log_file()
    |> take_screenshot(name: "02_after_select")

    # Verify button is now enabled
    assert HomePage.import_button_enabled?(session)
    IO.puts("Button disabled AFTER select: nil")

    take_screenshot(session, name: "03_final_state")
  end
end
