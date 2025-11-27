defmodule WeGoNextWeb.Features.EncounterListTest do
  use WeGoNextWeb.FeatureCase, async: false

  import Wallaby.Query

  @wow_logs_path "/mnt/g/World of Warcraft/_retail_/Logs"

  feature "user can select and load a combat log", %{session: session} do
    # Set up the default user with the wow logs path
    user = WeGoNext.Accounts.get_or_create_default_user()

    if user.wow_logs_path != @wow_logs_path do
      WeGoNext.Accounts.set_wow_logs_path(user, @wow_logs_path)
    end

    session =
      session
      |> visit("/")
      |> take_screenshot(name: "01_initial_page")

    # Check if the page loads
    assert_has(session, css("h1", text: "WoW Raid Diagnostic Tool"))

    session =
      session
      |> take_screenshot(name: "02_page_loaded")

    # Check if the select dropdown exists
    assert has?(session, css("select[name='log_path']"))

    session =
      session
      |> take_screenshot(name: "03_has_select")

    # Get the options from the select to see what's available
    options_html = session
      |> find(css("select[name='log_path']"))
      |> Wallaby.Element.attr("innerHTML")
    IO.puts("Select options HTML: #{options_html}")

    # Check button is initially disabled
    button_before = find(session, css("button[type='submit']"))
    disabled_before = Wallaby.Element.attr(button_before, "disabled")
    IO.inspect(disabled_before, label: "Button disabled BEFORE select")

    # Use Wallaby's built-in select function to choose an option
    # We need to find a log file - let's get the value from the second option
    second_option = session
      |> find(css("select[name='log_path'] option:nth-child(2)"))

    option_value = Wallaby.Element.attr(second_option, "value")
    IO.puts("Selecting option with value: #{option_value}")

    # Now select it using JavaScript since Wallaby's select can be tricky
    session =
      session
      |> execute_script("""
        var select = document.querySelector('select[name="log_path"]');
        select.value = '#{option_value}';
        select.dispatchEvent(new Event('change', { bubbles: true }));
      """)
      |> take_screenshot(name: "04_after_js_select")

    # Wait a moment for LiveView to process
    :timer.sleep(500)

    session =
      session
      |> take_screenshot(name: "05_after_wait")

    # Check button state after selection
    button_after = find(session, css("button[type='submit']"))
    disabled_after = Wallaby.Element.attr(button_after, "disabled")
    IO.inspect(disabled_after, label: "Button disabled AFTER select")

    session
    |> take_screenshot(name: "06_final_state")

    # The button should now be enabled (disabled attr should be nil or "false")
    assert disabled_after != "true" and disabled_after != "disabled",
           "Button should be enabled after selecting a log file, but disabled=#{inspect(disabled_after)}"
  end
end
