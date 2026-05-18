defmodule WeGoNextWeb.Components.ImportedLogsSwitcher do
  @moduledoc """
  Component for switching between multiple imported combat log files.

  Only displayed when there are 2+ imported logs. Shows each log with
  encounter count and highlights the currently loaded one.
  """
  use Phoenix.Component

  attr(:imported_logs, :list, required: true)
  attr(:combat_log_file, :any, default: nil)

  def render(assigns) do
    ~H"""
    <div :if={length(@imported_logs) > 1} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
      <h3 class="text-sm font-medium text-zinc-400 mb-3">Switch Log File</h3>
      <div class="space-y-2">
        <%= for clf <- @imported_logs do %>
          <.log_button clf={clf} is_current={current?(@combat_log_file, clf)} />
        <% end %>
      </div>
    </div>
    """
  end

  attr(:clf, :map, required: true)
  attr(:is_current, :boolean, required: true)

  defp log_button(assigns) do
    ~H"""
    <button
      phx-click={if @is_current, do: nil, else: "load_imported"}
      phx-value-file_id={@clf.id}
      disabled={@is_current}
      class={[
        "w-full text-left px-3 py-2 rounded transition-colors flex items-center justify-between",
        if(@is_current,
          do: "bg-wow-gold/20 border border-wow-gold/50 cursor-default",
          else: "bg-zinc-900 hover:bg-zinc-700 cursor-pointer"
        )
      ]}
    >
      <div>
        <span class={if @is_current, do: "text-wow-gold font-medium", else: "text-zinc-200"}>
          {Path.basename(@clf.file_path)}
        </span>
        <span class="text-zinc-500 text-sm ml-2">
          ({@clf.encounter_count} encounters)
        </span>
      </div>
      <span :if={@is_current} class="text-xs text-wow-gold px-2 py-0.5 bg-wow-gold/10 rounded">
        Current
      </span>
    </button>
    """
  end

  defp current?(nil, _clf), do: false
  defp current?(combat_log_file, clf), do: combat_log_file.id == clf.id
end
