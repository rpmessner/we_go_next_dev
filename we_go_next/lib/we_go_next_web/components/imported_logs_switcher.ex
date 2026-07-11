defmodule WeGoNextWeb.Components.ImportedLogsSwitcher do
  @moduledoc """
  Component for switching between multiple imported combat log files.

  Shows imported logs with load and reimport actions.
  """
  use Phoenix.Component

  attr(:imported_logs, :list, required: true)
  attr(:combat_log_file, :any, default: nil)

  def render(assigns) do
    ~H"""
    <div :if={@imported_logs != []} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
      <h3 class="text-sm font-medium text-zinc-400 mb-3">Imported Logs</h3>
      <div class="space-y-2">
        <.log_row
          :for={clf <- @imported_logs}
          clf={clf}
          is_current={current?(@combat_log_file, clf)}
        />
      </div>
    </div>
    """
  end

  attr(:clf, :map, required: true)
  attr(:is_current, :boolean, required: true)

  defp log_row(assigns) do
    ~H"""
    <div class={[
      "rounded px-3 py-2 transition-colors",
      if(@is_current,
        do: "bg-wow-gold/20 border border-wow-gold/50",
        else: "bg-zinc-900"
      )
    ]}>
      <div class="flex items-center gap-2">
        <button
          phx-click={if @is_current, do: nil, else: "load_imported"}
          phx-value-file_id={@clf.id}
          disabled={@is_current}
          class={[
            "min-w-0 flex-1 text-left",
            if(@is_current, do: "cursor-default", else: "cursor-pointer hover:text-wow-gold")
          ]}
        >
          <span class={if @is_current, do: "text-wow-gold font-medium", else: "text-zinc-200"}>
            {Path.basename(@clf.file_path)}
          </span>
          <span class="text-zinc-500 text-sm ml-2">
            ({@clf.encounter_count} encounters)
          </span>
          <span :if={@clf.first_encounter_start_at} class="text-zinc-500 text-sm ml-2">
            First pull {format_log_date(@clf.first_encounter_start_at)}
          </span>
        </button>

        <span :if={@is_current} class="text-xs text-wow-gold px-2 py-0.5 bg-wow-gold/10 rounded">
          Current
        </span>

        <label class="flex items-center gap-1 rounded bg-zinc-800 px-2 py-1 text-xs font-semibold text-zinc-300">
          <input
            type="checkbox"
            class="rounded border-zinc-600 bg-zinc-950 text-wow-gold focus:ring-wow-gold"
            checked={@clf.publish_enabled}
            phx-click="toggle_publish_enabled"
            phx-value-file_id={@clf.id}
          />
          Publish
        </label>

        <button
          type="button"
          phx-click="reimport_log"
          phx-value-path={@clf.file_path}
          data-confirm="Reimport this log? Existing encounters for this log will be replaced before parsing."
          class="rounded bg-zinc-700 px-2 py-1 text-xs font-semibold text-zinc-100 hover:bg-zinc-600"
        >
          Reimport
        </button>
      </div>

      <form phx-submit="save_warcraft_logs_url" class="mt-2 flex gap-2">
        <input type="hidden" name="file_id" value={@clf.id} />
        <input
          type="url"
          name="url"
          value={@clf.warcraft_logs_report_url || ""}
          class="min-w-0 flex-1 rounded border border-zinc-700 bg-zinc-950 px-2 py-1 text-xs text-zinc-100 placeholder-zinc-500 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
          placeholder="Warcraft Logs report URL"
        />
        <button
          type="submit"
          class="rounded bg-zinc-700 px-2 py-1 text-xs font-semibold text-zinc-100 hover:bg-zinc-600"
        >
          Link WCL
        </button>
        <button
          :if={@clf.warcraft_logs_report_url}
          type="button"
          phx-click="clear_warcraft_logs_url"
          phx-value-file_id={@clf.id}
          class="rounded bg-zinc-800 px-2 py-1 text-xs font-semibold text-zinc-300 hover:bg-zinc-700"
        >
          Clear
        </button>
      </form>

      <div :if={@clf.warcraft_logs_report_code} class="mt-1 text-xs text-zinc-500">
        WCL report {@clf.warcraft_logs_report_code}{if @clf.warcraft_logs_fight_id, do: " fight #{@clf.warcraft_logs_fight_id}", else: ""}
      </div>
    </div>
    """
  end

  defp current?(nil, _clf), do: false
  defp current?(combat_log_file, clf), do: combat_log_file.id == clf.id

  defp format_log_date(nil), do: "Unknown"

  defp format_log_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
end
