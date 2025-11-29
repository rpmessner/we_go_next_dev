defmodule WeGoNextWeb.Components.Tabs.FailuresTab do
  @moduledoc """
  Failures tab component for encounter detail view.

  Displays mechanic failures detected by the FailureAnalyzer:
  - Summary of total failures
  - Failures grouped by mechanic
  - Failures grouped by player
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents

  attr :stats, :map, required: true
  attr :player_classes, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div :if={@stats.failures == []} class="text-center py-12">
        <div class="text-green-400 text-lg font-medium mb-2">No mechanic failures!</div>
        <p class="text-zinc-400 text-sm">
          Either no mechanics are being tracked, or everyone handled them correctly.
        </p>
        <p class="text-zinc-500 text-xs mt-2">
          Track mechanics from the "Damage Taken" or "Interrupts" tabs.
        </p>
      </div>

      <div :if={@stats.failures != []}>
        <%!-- Summary --%>
        <div class="bg-red-900/30 border border-red-800 rounded-lg p-4 mb-6">
          <h3 class="text-red-400 font-medium mb-2">
            {@stats.summary.total_failures} Failure(s) Detected
          </h3>
          <p class="text-zinc-400 text-sm">
            {@stats.summary.players_with_failures} player(s) failed {@stats.summary.mechanics_failed} tracked mechanic(s)
          </p>
        </div>

        <%!-- By Mechanic --%>
        <.failures_by_mechanic stats={@stats} player_classes={@player_classes} />

        <%!-- By Player --%>
        <.failures_by_player stats={@stats} player_classes={@player_classes} />
      </div>
    </div>
    """
  end

  # Sub-components

  attr :stats, :map, required: true
  attr :player_classes, :map, required: true

  defp failures_by_mechanic(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-medium text-zinc-400 mb-3">Failures by Mechanic</h3>
      <div class="space-y-3">
        <div :for={{spell_name, failures} <- sorted_by_mechanic(@stats)} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
          <div class="flex items-center justify-between mb-2">
            <span class={[
              "font-medium",
              failure_type_color(List.first(failures))
            ]}>
              <.wowhead_link spell_id={List.first(failures).spell_id} name={spell_name} />
            </span>
            <span class="text-red-400 font-mono">{length(failures)} failure(s)</span>
          </div>
          <div class="flex flex-wrap gap-2">
            <span
              :for={failure <- failures}
              class="inline-flex items-center px-2 py-1 rounded text-xs bg-zinc-700"
            >
              <.player_name name={failure.player_name} player_classes={@player_classes} />
              <span :if={failure.hit_count > 0} class="ml-1 text-zinc-400">
                ({failure.hit_count} hits)
              </span>
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :stats, :map, required: true
  attr :player_classes, :map, required: true

  defp failures_by_player(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-medium text-zinc-400 mb-3">Failures by Player</h3>
      <div class="bg-zinc-800 rounded-lg overflow-hidden">
        <table class="w-full">
          <thead class="bg-zinc-750">
            <tr>
              <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Player</th>
              <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Failures</th>
              <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Mechanics Failed</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-700">
            <tr :for={{player, failures} <- sorted_by_player(@stats)} class="hover:bg-zinc-750">
              <td class="px-4 py-2">
                <.player_name name={player} player_classes={@player_classes} />
              </td>
              <td class="px-4 py-2 text-right text-red-400 font-medium">{length(failures)}</td>
              <td class="px-4 py-2 text-zinc-400 text-sm">
                {failures |> Enum.map(& &1.spell_name) |> Enum.uniq() |> Enum.join(", ")}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # Helper functions

  defp sorted_by_mechanic(stats) do
    stats.by_mechanic
    |> Enum.sort_by(fn {_, failures} -> -length(failures) end)
  end

  defp sorted_by_player(stats) do
    stats.by_player
    |> Enum.sort_by(fn {_, failures} -> -length(failures) end)
  end

  defp failure_type_color(%{mechanic_type: "avoidable"}), do: "text-red-400"
  defp failure_type_color(%{mechanic_type: "interrupt"}), do: "text-yellow-400"
  defp failure_type_color(%{mechanic_type: "soak"}), do: "text-blue-400"
  defp failure_type_color(%{mechanic_type: "spread"}), do: "text-purple-400"
  defp failure_type_color(_), do: "text-zinc-200"
end
