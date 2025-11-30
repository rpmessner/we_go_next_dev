defmodule WeGoNextWeb.Components.LogSelector do
  @moduledoc """
  Component for selecting and importing WoW combat log files.

  Displays:
  - Log file dropdown with import status indicators
  - Import/Resume/Reimport button with confirmation
  - Progress bar during import
  - Current log info with refresh button
  - Purge button for removing imported data
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents, only: [format_size: 1]

  attr :user, :map, required: true
  attr :log_files, :list, required: true
  attr :selected_log, :string, default: nil
  attr :imported_logs, :list, required: true
  attr :loading, :boolean, required: true
  attr :syncing, :boolean, required: true
  attr :confirm_reimport, :boolean, required: true
  attr :import_progress, :map, default: nil
  attr :log_path, :string, default: nil
  attr :combat_log_file, :any, default: nil
  attr :error, :string, default: nil

  def render(assigns) do
    ~H"""
    <div class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
      <%= if @user.wow_logs_path && @log_files != [] do %>
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
                  {log.filename} ({format_size(log.size)})
                  {log_status_indicator(log.full_path, @imported_logs)}
                </option>
              <% end %>
            </select>
            <.import_buttons
              loading={@loading}
              selected_log={@selected_log}
              imported_logs={@imported_logs}
              confirm_reimport={@confirm_reimport}
            />
          </form>

          <p :if={@confirm_reimport} class="text-sm text-yellow-500 mt-2">
            This log has already been fully imported. Click "Confirm Reimport" to import again.
          </p>

          <.progress_bar :if={@import_progress} progress={@import_progress} />
        </div>

        <.current_log_info
          :if={@log_path}
          log_path={@log_path}
          combat_log_file={@combat_log_file}
          imported_logs={@imported_logs}
          log_files={@log_files}
          syncing={@syncing}
        />
      <% else %>
        <.empty_state user={@user} />
      <% end %>

      <p :if={@error} class="mt-2 text-sm text-red-400">{@error}</p>
    </div>
    """
  end

  # Sub-components

  attr :loading, :boolean, required: true
  attr :selected_log, :string, default: nil
  attr :imported_logs, :list, required: true
  attr :confirm_reimport, :boolean, required: true

  defp import_buttons(assigns) do
    ~H"""
    <%= if @confirm_reimport do %>
      <button
        type="submit"
        disabled={@loading}
        class="px-4 py-2 bg-red-600 text-white font-semibold rounded hover:bg-red-500 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        Confirm Reimport
      </button>
      <button
        type="button"
        phx-click="cancel_reimport"
        class="px-3 py-2 text-zinc-400 hover:text-zinc-200"
      >
        Cancel
      </button>
    <% else %>
      <button
        type="submit"
        disabled={@loading || !@selected_log}
        class={[
          "px-4 py-2 font-semibold rounded disabled:opacity-50 disabled:cursor-not-allowed",
          import_button_class(@selected_log, @imported_logs)
        ]}
      >
        {import_button_label(@loading, @selected_log, @imported_logs)}
      </button>
      <button
        :if={imported?(@selected_log, @imported_logs)}
        type="button"
        phx-click="purge_log"
        phx-value-path={@selected_log}
        disabled={@loading}
        data-confirm="Delete all encounters from this log? This cannot be undone."
        class="px-3 py-2 text-red-400 hover:text-red-300 hover:bg-red-900/30 rounded disabled:opacity-50"
        title="Purge encounters"
      >
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
        </svg>
      </button>
    <% end %>
    """
  end

  attr :progress, :map, required: true

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

  attr :log_path, :string, required: true
  attr :combat_log_file, :any, required: true
  attr :imported_logs, :list, required: true
  attr :log_files, :list, required: true
  attr :syncing, :boolean, required: true

  defp current_log_info(assigns) do
    ~H"""
    <div class="flex items-center justify-between border-t border-zinc-700 pt-3 mt-3">
      <div>
        <p class="text-sm text-zinc-400">Currently loaded:</p>
        <p class="text-zinc-200">{Path.basename(@log_path)}</p>
        <p :if={@combat_log_file} class="text-xs text-zinc-500 mt-1">
          {encounter_count(@combat_log_file, @imported_logs)} encounters imported
        </p>
      </div>
      <button
        :if={not dead_log?(@log_path, @log_files)}
        phx-click="sync_log"
        disabled={@syncing}
        class="px-4 py-2 bg-zinc-700 text-zinc-200 font-medium rounded hover:bg-zinc-600 disabled:opacity-50"
      >
        {if @syncing, do: "Refreshing...", else: "Refresh"}
      </button>
    </div>
    """
  end

  attr :user, :map, required: true

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

  defp log_status_indicator(file_path, imported_logs) do
    cond do
      partially_imported?(file_path, imported_logs) -> " ⚠ (incomplete)"
      complete_log?(file_path, imported_logs) -> " ✓ (complete)"
      imported?(file_path, imported_logs) -> " ✓"
      true -> ""
    end
  end

  defp import_button_class(selected_log, imported_logs) do
    cond do
      partially_imported?(selected_log, imported_logs) -> "bg-yellow-600 text-white hover:bg-yellow-500"
      complete_log?(selected_log, imported_logs) -> "bg-zinc-600 text-zinc-300 hover:bg-zinc-500"
      true -> "bg-wow-gold text-zinc-900 hover:bg-yellow-400"
    end
  end

  defp import_button_label(loading, selected_log, imported_logs) do
    cond do
      loading -> "Importing..."
      partially_imported?(selected_log, imported_logs) -> "Resume"
      complete_log?(selected_log, imported_logs) -> "Reimport"
      true -> "Import"
    end
  end

  defp imported?(file_path, imported_logs) do
    Enum.any?(imported_logs, &(&1.file_path == file_path))
  end

  defp complete_log?(file_path, imported_logs) do
    case Enum.find(imported_logs, &(&1.file_path == file_path)) do
      nil ->
        false

      log ->
        parsed = log.last_parsed_byte || 0
        parsed > 0 and not partially_imported?(file_path, imported_logs)
    end
  end

  defp partially_imported?(file_path, imported_logs) do
    case Enum.find(imported_logs, &(&1.file_path == file_path)) do
      nil ->
        false

      log ->
        case File.stat(file_path) do
          {:ok, %{size: disk_size}} ->
            parsed = log.last_parsed_byte || 0
            parsed > 0 and (disk_size - parsed) > 100

          {:error, _} ->
            false
        end
    end
  end

  defp dead_log?(file_path, log_files) when is_list(log_files) do
    case log_files do
      [] -> false
      logs ->
        newest = hd(logs)
        newest.full_path != file_path
    end
  end

  defp dead_log?(_, _), do: false

  defp encounter_count(%{id: id}, imported_logs) do
    case Enum.find(imported_logs, &(&1.id == id)) do
      nil -> 0
      log -> log.encounter_count
    end
  end

  defp encounter_count(_, _), do: 0
end
