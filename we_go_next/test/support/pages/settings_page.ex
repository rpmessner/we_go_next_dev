defmodule WeGoNext.Integration.Pages.SettingsPage do
  @moduledoc """
  Page object for the settings page.
  """
  use Wallaby.DSL

  # Navigation

  def navigate(session) do
    visit(session, "/settings")
  end

  def ensure_page_loaded(session) do
    assert_has(session, Query.css("h1", text: "Settings"))
    session
  end

  # Path configuration

  def fill_in_logs_path(session, path) do
    fill_in(session, Query.text_field("path"), with: path)
  end

  def save_path(session) do
    click(session, Query.button("Save"))
  end

  def path_valid?(session) do
    Browser.has?(session, Query.css("p.text-green-400", text: "Folder found"))
  end

  # File watching

  def click_watch_most_recent(session) do
    click(session, Query.button("Watch Most Recent Log"))
  end

  def select_log_file(session, log_path) do
    session
    |> Browser.execute_script("""
      var select = document.querySelector('select[name="log_path"]');
      select.value = '#{log_path}';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    """)

    Process.sleep(300)
    session
  end

  def click_import_and_watch(session) do
    click(session, Query.button("Import & Watch Selected"))
  end

  def click_stop_watching(session) do
    click(session, Query.button("Stop Watching"))
  end

  def watching?(session) do
    Browser.has?(session, Query.css(".animate-ping")) or
      Browser.has?(session, Query.css("p", text: "Watching for new encounters"))
  end

  # Assertions

  def assert_watching(session) do
    ExUnit.Assertions.assert(
      watching?(session),
      "Expected watching indicator to be visible"
    )

    session
  end

  def assert_not_watching(session) do
    ExUnit.Assertions.refute(
      watching?(session),
      "Expected watching indicator to NOT be visible"
    )

    session
  end

  def assert_path_valid(session) do
    ExUnit.Assertions.assert(
      path_valid?(session),
      "Expected path to be valid"
    )

    session
  end

  # Navigation

  def go_back_to_encounters(session) do
    click(session, Query.css("a", text: "Back to encounters"))
    Process.sleep(300)
    session
  end
end
