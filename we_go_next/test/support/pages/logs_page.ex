defmodule WeGoNext.Integration.Pages.LogsPage do
  @moduledoc """
  Page object for the imported-logs management page (`/logs`): reimport,
  publish toggles, current-log switching, and Warcraft Logs linking.

  Importing new logs happens on the home page — see
  `WeGoNext.Integration.Pages.HomePage`.
  """
  use Wallaby.DSL

  # Navigation

  def navigate(session) do
    visit(session, "/logs")
  end

  def ensure_page_loaded(session) do
    session
    |> assert_has(Query.css("h1", text: "Imported Logs"))

    session
  end

  # Imported log actions

  def click_reimport(session) do
    Browser.accept_confirm(session, fn sess ->
      click(sess, Query.button("Reimport"))
    end)

    session
  end

  def has_reimport_button?(session) do
    Browser.has?(session, Query.button("Reimport"))
  end

  def assert_imported_logs_visible(session) do
    session
    |> assert_has(Query.css("h3", text: "Imported Logs"))

    session
  end

  def click_purge(session) do
    session
    |> Browser.accept_confirm(fn sess ->
      click(sess, Query.css("button[phx-click='purge_log']"))
    end)
  end

  def has_purge_button?(session) do
    Browser.has?(session, Query.css("button[phx-click='purge_log']"))
  end

  # Waits for a started import/reimport to finish: the imported log row (with
  # its Reimport action) must render, and the import worker must go idle.
  def wait_for_import_complete(session, timeout_ms \\ 30_000)

  def wait_for_import_complete(_session, timeout_ms) when timeout_ms <= 0 do
    ExUnit.Assertions.flunk("Timed out waiting for import to complete")
  end

  def wait_for_import_complete(session, timeout_ms) do
    if has_reimport_button?(session) and WeGoNext.ImportWorker.active_imports() == %{} do
      session
    else
      Process.sleep(500)
      wait_for_import_complete(session, timeout_ms - 500)
    end
  end
end
