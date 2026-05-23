defmodule WeGoNextWeb.Components.LogSelector do
  @moduledoc """
  Component for selecting and importing WoW combat log files.

  Displays:
  - Unimported log file dropdown
  - Import button
  - Progress bar during import
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents, only: [format_size: 1]

  attr(:user, :map, required: true)
  attr(:log_files, :list, required: true)
  attr(:selected_log, :string, default: nil)
  attr(:loading, :boolean, required: true)
  attr(:import_progress, :map, default: nil)
  attr(:error, :string, default: nil)

  def render(assigns) do
    ~H"""
    <div class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
      <%= if @user.wow_logs_path do %>
        <div class="mb-3">
          <label class="block text-sm font-medium text-zinc-400 mb-2">
            Import Combat Log
          </label>
          <form phx-change="select_log" phx-submit="import_log" class="flex gap-2">
            <select
              name="log_path"
              disabled={@loading}
              class="flex-1 bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold disabled:opacity-50"
            >
              <option value="">Choose a log file...</option>
              <%= for log <- @log_files do %>
                <option value={log.full_path} selected={@selected_log == log.full_path}>
                  {log.filename} ({format_size(log.size)}) - modified {format_log_date(log.modified)}
                </option>
              <% end %>
            </select>
            <button
              type="submit"
              disabled={@loading || !@selected_log}
              class="px-4 py-2 bg-wow-gold text-zinc-900 font-semibold rounded hover:bg-yellow-400 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {if @loading, do: "Importing...", else: "Import"}
            </button>
          </form>

          <p :if={@log_files == []} class="mt-2 text-sm text-zinc-500">
            All discovered combat logs have already been imported. Use Reimport on an imported log row to parse it again.
          </p>

          <.progress_bar :if={@import_progress} progress={@import_progress} />
        </div>
      <% else %>
        <.empty_state user={@user} />
      <% end %>

      <p :if={@error} class="mt-2 text-sm text-red-400">{@error}</p>
    </div>
    """
  end

  # Sub-components

  attr(:progress, :map, required: true)

  defp progress_bar(assigns) do
    ~H"""
    <div class="mt-3">
      <div class="flex items-center justify-between text-sm text-zinc-400 mb-1">
        <span>
          <%= case @progress.status do %>
            <% :parsing -> %>
              Parsing log file...
            <% :saving -> %>
              Saving to database...
          <% end %>
        </span>
        <span>{@progress.percent}%</span>
      </div>
      <div class="w-full bg-zinc-700 rounded-full h-2.5">
        <div
          class="bg-wow-gold h-2.5 rounded-full transition-all duration-300"
          style={"width: #{@progress.percent}%"}
        >
        </div>
      </div>
      <p class="text-xs text-zinc-500 mt-1">
        {if @progress.encounters_found > 0, do: "#{@progress.encounters_found} encounters found", else: "Scanning for encounters..."}
      </p>
    </div>
    """
  end

  attr(:user, :map, required: true)

  defp empty_state(assigns) do
    ~H"""
    <div class="text-center py-4">
      <p class="text-zinc-400 mb-3">
        <%= if @user.wow_logs_path do %>
          No combat log files found in the configured folder.
        <% else %>
          Configure your WoW Logs folder to get started.
        <% end %>
      </p>
      <.link
        navigate="/settings"
        class="inline-flex items-center px-4 py-2 bg-wow-gold text-zinc-900 font-semibold rounded hover:bg-yellow-400"
      >
        Configure WoW Folder
      </.link>
    </div>
    """
  end

  # Helper functions
  defp format_log_date(nil), do: "unknown"

  defp format_log_date(%NaiveDateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_log_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
end
