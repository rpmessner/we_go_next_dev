defmodule WeGoNext.Integration.Pages.HomePage do
  @moduledoc """
  Page object for the home page (encounter list).
  """
  use Wallaby.DSL

  # Navigation

  def navigate(session) do
    visit(session, "/")
  end

  def ensure_page_loaded(session) do
    session
    |> assert_has(Query.css("h1", text: "WoW Raid Diagnostic Tool"))

    session
  end

  # Log file selection

  def select_log_file(session, option_index \\ 2) do
    option = find(session, Query.css("select[name='log_path'] option:nth-child(#{option_index})"))
    option_value = Wallaby.Element.attr(option, "value")

    session
    |> Browser.execute_script("""
      var select = document.querySelector('select[name="log_path"]');
      select.value = '#{option_value}';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    """)

    Process.sleep(300)
    session
  end

  def get_selected_log_path(session) do
    option = find(session, Query.css("select[name='log_path'] option:nth-child(2)"))
    Wallaby.Element.attr(option, "value")
  end

  def click_import(session) do
    click(session, Query.css("button[type='submit']"))
  end

  def import_button_enabled?(session) do
    button = find(session, Query.css("button[type='submit']"))
    disabled = Wallaby.Element.attr(button, "disabled")
    disabled != "true" and disabled != "disabled"
  end

  def click_refresh(session) do
    click(session, Query.css("button", text: "Refresh"))
  end

  def click_reimport(session) do
    Browser.accept_confirm(session, fn sess ->
      click(sess, Query.button("Reimport"))
    end)

    session
  end

  # Encounter list

  def wait_for_encounters(session, timeout_ms \\ 30_000)

  def wait_for_encounters(_session, timeout_ms) when timeout_ms <= 0 do
    ExUnit.Assertions.flunk("Timed out waiting for encounters to load")
  end

  def wait_for_encounters(session, timeout_ms) do
    if Browser.has?(session, Query.css(".encounter-card")) do
      wait_for_import_worker_idle()
      session
    else
      Process.sleep(500)
      wait_for_encounters(session, timeout_ms - 500)
    end
  end

  def wait_for_encounter_count(session, expected_count, timeout_ms \\ 10_000)

  def wait_for_encounter_count(session, expected_count, timeout_ms) when timeout_ms <= 0 do
    actual = encounter_count(session)

    ExUnit.Assertions.flunk("Timed out waiting for #{expected_count} encounters, got #{actual}")
  end

  def wait_for_encounter_count(session, expected_count, timeout_ms) do
    if encounter_count(session) >= expected_count do
      wait_for_import_worker_idle()
      session
    else
      Process.sleep(500)
      wait_for_encounter_count(session, expected_count, timeout_ms - 500)
    end
  end

  def encounter_count(session) do
    session
    |> Browser.all(Query.css(".encounter-card"))
    |> length()
  end

  def encounter_cards(session) do
    Browser.all(session, Query.css(".encounter-card"))
  end

  def encounter_texts(session) do
    session
    |> encounter_cards()
    |> Enum.map(&Wallaby.Element.text/1)
  end

  def has_encounter?(session, boss_name) do
    session
    |> encounter_texts()
    |> Enum.any?(&String.contains?(&1, boss_name))
  end

  # Assertions

  def assert_encounter_present(session, boss_name) do
    ExUnit.Assertions.assert(
      has_encounter?(session, boss_name),
      "Expected encounter '#{boss_name}' to be present"
    )

    session
  end

  def assert_encounter_count(session, expected) do
    actual = encounter_count(session)

    ExUnit.Assertions.assert(
      actual == expected,
      "Expected #{expected} encounters, got #{actual}"
    )

    session
  end

  def assert_encounter_shows_wipe(session, boss_name) do
    card_text =
      session
      |> encounter_texts()
      |> Enum.find(&String.contains?(&1, boss_name))

    ExUnit.Assertions.assert(
      card_text && String.contains?(card_text, "WIPE"),
      "Expected #{boss_name} to show as WIPE"
    )

    session
  end

  def assert_encounter_shows_kill(session, boss_name) do
    card_text =
      session
      |> encounter_texts()
      |> Enum.find(&String.contains?(&1, boss_name))

    ExUnit.Assertions.assert(
      card_text && String.contains?(card_text, "KILL"),
      "Expected #{boss_name} to show as KILL"
    )

    session
  end

  # Log status

  def get_import_button_text(session) do
    button = find(session, Query.css("form[phx-submit='import_log'] button[type='submit']"))
    Wallaby.Element.text(button)
  end

  def assert_import_button_text(session, expected_text) do
    actual = get_import_button_text(session)

    ExUnit.Assertions.assert(
      actual == expected_text,
      "Expected import button to say '#{expected_text}', got '#{actual}'"
    )

    session
  end

  def assert_log_shows_complete(session) do
    session
    |> Browser.execute_script(
      """
        var select = document.querySelector('select[name="log_path"]');
        return select.options[select.selectedIndex].text;
      """,
      fn option_text ->
        ExUnit.Assertions.assert(
          is_binary(option_text) and String.contains?(option_text, "(complete)"),
          "Expected selected log to show '(complete)', got: #{inspect(option_text)}"
        )
      end
    )

    session
  end

  def assert_log_shows_incomplete(session) do
    session
    |> Browser.execute_script(
      """
        var select = document.querySelector('select[name="log_path"]');
        return select.options[select.selectedIndex].text;
      """,
      fn option_text ->
        ExUnit.Assertions.assert(
          is_binary(option_text) and String.contains?(option_text, "(incomplete)"),
          "Expected selected log to show '(incomplete)', got: #{inspect(option_text)}"
        )
      end
    )

    session
  end

  def assert_imported_logs_visible(session) do
    session
    |> assert_has(Query.css("h3", text: "Imported Logs"))

    session
  end

  def has_reimport_button?(session) do
    Browser.has?(session, Query.button("Reimport"))
  end

  def click_purge(session) do
    # Accept the confirmation dialog
    session
    |> Browser.accept_confirm(fn sess ->
      click(sess, Query.css("button[phx-click='purge_log']"))
    end)
  end

  def has_purge_button?(session) do
    Browser.has?(session, Query.css("button[phx-click='purge_log']"))
  end

  # Navigation to other pages

  def go_to_settings(session) do
    click(session, Query.link("Settings"))
  end

  defp wait_for_import_worker_idle(timeout_ms \\ 30_000)

  defp wait_for_import_worker_idle(timeout_ms) when timeout_ms <= 0 do
    ExUnit.Assertions.flunk("Timed out waiting for import worker to finish document generation")
  end

  defp wait_for_import_worker_idle(timeout_ms) do
    case WeGoNext.ImportWorker.active_imports() do
      active when active == %{} ->
        :ok

      _active ->
        Process.sleep(500)
        wait_for_import_worker_idle(timeout_ms - 500)
    end
  end
end
