defmodule WeGoNextWeb.Components.ImportedLogsSwitcher do
  @moduledoc """
  Component for switching between multiple imported combat log files.

  Shows imported logs with load and reimport actions.
  """
  use Phoenix.Component
  alias WeGoNext.CombatLogFile

  attr(:imported_logs, :list, required: true)
  attr(:combat_log_file, :any, default: nil)

  def render(assigns) do
    assigns = assign(assigns, :newest_live_log_id, newest_live_log_id(assigns.imported_logs))

    ~H"""
    <div :if={@imported_logs != []} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
      <h3 class="text-sm font-medium text-zinc-400 mb-3">Imported Logs</h3>
      <div class="space-y-2">
      <.log_row
          :for={clf <- @imported_logs}
          clf={clf}
          is_current={current?(@combat_log_file, clf)}
          watchable={clf.id == @newest_live_log_id}
      />
      </div>
    </div>
    """
  end

  attr(:clf, :map, required: true)
  attr(:is_current, :boolean, required: true)
  attr(:watchable, :boolean, required: true)

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

        <label
          :if={@watchable}
          class="flex items-center gap-1 rounded bg-zinc-800 px-2 py-1 text-xs font-semibold text-zinc-300"
        >
          <input
            type="checkbox"
            class="rounded border-zinc-600 bg-zinc-950 text-wow-gold focus:ring-wow-gold"
            checked={@clf.watch_enabled}
            phx-click="toggle_watch_enabled"
            phx-value-file_id={@clf.id}
          />
          Watch
        </label>

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

      <form id={"raid-night-name-#{@clf.id}"} phx-submit="save_raid_night_name" class="mt-2 flex gap-2">
        <input type="hidden" name="file_id" value={@clf.id} />
        <input
          type="text"
          name="raid_night[name]"
          value={@clf.raid_night_name || CombatLogFile.default_raid_night_name(@clf.file_path)}
          maxlength="120"
          aria-label="Raid night name"
          class="min-w-0 flex-1 rounded border border-zinc-700 bg-zinc-950 px-2 py-1 text-xs text-zinc-100 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
        />
        <button type="submit" class="rounded bg-zinc-700 px-2 py-1 text-xs font-semibold text-zinc-100 hover:bg-zinc-600">
          Save name
        </button>
      </form>

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

  defp newest_live_log_id(imported_logs) do
    imported_logs
    |> Enum.filter(&(&1.source == :live))
    |> Enum.max_by(&newest_key/1, fn -> nil end)
    |> case do
      nil -> nil
      log -> log.id
    end
  end

  defp newest_key(%{file_mtime: %DateTime{} = file_mtime, id: id}),
    do: {DateTime.to_unix(file_mtime, :microsecond), id}

  defp newest_key(%{id: id}), do: {-1, id}

  defp format_log_date(nil), do: "Unknown"

  defp format_log_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
end
