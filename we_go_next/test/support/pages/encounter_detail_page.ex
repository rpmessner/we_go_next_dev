defmodule WeGoNext.Integration.Pages.EncounterDetailPage do
  @moduledoc """
  Page object for the encounter detail page.
  """
  use Wallaby.DSL

  # Navigation

  def navigate(session, encounter_id) do
    visit(session, "/encounters/#{encounter_id}")
  end

  def ensure_page_loaded(session) do
    wait_for_element(session, Query.css("h1.text-wow-gold"), 10_000)
    session
  end

  def ensure_page_loaded(session, boss_name) do
    session = wait_for_element(session, Query.css("h1.text-wow-gold"), 10_000)
    assert_has(session, Query.css("h1.text-wow-gold", text: boss_name))
    session
  end

  # Tab navigation

  def click_tab(session, tab_name) do
    click(session, Query.css("button[phx-value-tab='#{tab_name}']"))
    Process.sleep(200)
    session
  end

  def click_summary_tab(session), do: click_tab(session, "summary")
  def click_deaths_tab(session), do: click_tab(session, "deaths")
  def click_damage_tab(session), do: click_tab(session, "damage")
  def click_interrupts_tab(session), do: click_tab(session, "interrupts")
  def click_debuffs_tab(session), do: click_tab(session, "debuffs")
  def click_failures_tab(session), do: click_tab(session, "failures")

  def active_tab?(session, tab_name) do
    Browser.has?(session, Query.css("button[phx-value-tab='#{tab_name}'].border-wow-gold"))
  end

  # Content checks

  def has_wipe_banner?(session) do
    Browser.has?(session, Query.css(".bg-red-900\\/30"))
  end

  def has_kill_banner?(session) do
    Browser.has?(session, Query.css(".bg-green-900\\/30")) or
      Browser.has?(session, Query.css(".bg-green-900", text: "KILL"))
  end

  def has_next_pull_focus?(session) do
    Browser.has?(session, Query.css("h3", text: "Next Pull Focus"))
  end

  # Assertions

  def assert_is_wipe(session) do
    ExUnit.Assertions.assert(
      has_wipe_banner?(session),
      "Expected encounter to show as WIPE"
    )

    session
  end

  def assert_is_kill(session) do
    ExUnit.Assertions.assert(
      has_kill_banner?(session),
      "Expected encounter to show as KILL"
    )

    session
  end

  def assert_summary_content_visible(session) do
    has_content =
      has_wipe_banner?(session) or
        has_kill_banner?(session) or
        has_next_pull_focus?(session)

    ExUnit.Assertions.assert(
      has_content,
      "Summary tab should show wipe cause, kill banner, or next pull focus"
    )

    session
  end

  def assert_tab_active(session, tab_name) do
    ExUnit.Assertions.assert(
      active_tab?(session, tab_name),
      "Expected tab '#{tab_name}' to be active"
    )

    session
  end

  def assert_stat_blocks_visible(session, count \\ 5) do
    wait_for_element(session, Query.css(".stat-block", count: count), 10_000)
    session
  end

  # Navigation

  def go_back_to_encounters(session) do
    click(session, Query.css("a", text: "Back to encounters"))
    Process.sleep(300)
    session
  end

  # Private helpers

  defp wait_for_element(session, query, timeout_ms) when timeout_ms <= 0 do
    ExUnit.Assertions.flunk("Timed out waiting for element: #{inspect(query)}")
    session
  end

  defp wait_for_element(session, query, timeout_ms) do
    if Browser.has?(session, query) do
      session
    else
      Process.sleep(200)
      wait_for_element(session, query, timeout_ms - 200)
    end
  end
end
