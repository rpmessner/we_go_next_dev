defmodule WeGoNextWeb.Components.Tabs.SummaryTab do
  @moduledoc """
  Summary tab component for encounter detail view.

  Displays the between-pull analysis summary including:
  - Wipe cause or kill banner
  - Deaths breakdown
  - Critical failures
  - Missed interrupts
  - Players needing coaching
  - Recommendations for next pull
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents

  attr :summary, :any, required: true
  attr :player_classes, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Wipe cause banner (only for wipes) --%>
      <div :if={@summary.wipe_cause} class="bg-red-900/30 border border-red-800 rounded-lg p-4">
        <h3 class="text-red-400 font-medium mb-1">Wipe Cause</h3>
        <p class="text-zinc-200">{@summary.wipe_cause}</p>
      </div>

      <%!-- Kill banner (for successful kills) --%>
      <div :if={@summary.result == :kill} class="bg-green-900/30 border border-green-800 rounded-lg p-4">
        <h3 class="text-green-400 font-medium">Boss Defeated!</h3>
        <p class="text-zinc-400 text-sm">Fight duration: {@summary.duration_str}</p>
      </div>

      <%!-- Deaths summary --%>
      <.deaths_summary :if={@summary.deaths_summary.total > 0} summary={@summary} />

      <%!-- Critical failures --%>
      <.critical_failures :if={@summary.critical_failures != []} summary={@summary} player_classes={@player_classes} />

      <%!-- No failures message --%>
      <div :if={@summary.critical_failures == [] && @summary.result == :wipe} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <p class="text-zinc-400">
          No tracked mechanic failures detected. Consider tracking mechanics from the Damage Taken tab.
        </p>
      </div>

      <%!-- Missed interrupts --%>
      <.missed_interrupts :if={@summary.missed_interrupts != []} missed_interrupts={@summary.missed_interrupts} />

      <%!-- Players needing coaching --%>
      <.problem_players :if={@summary.problem_players != []} problem_players={@summary.problem_players} player_classes={@player_classes} />

      <%!-- Recommendations --%>
      <.recommendations :if={@summary.recommendations != []} recommendations={@summary.recommendations} />

      <%!-- No recommendations message --%>
      <div :if={@summary.recommendations == [] && @summary.result == :wipe} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <h3 class="text-green-400 font-medium mb-2">Next Pull Focus</h3>
        <p class="text-zinc-400">No specific issues detected. Keep up the good work!</p>
      </div>
    </div>
    """
  end

  # Sub-components

  attr :summary, :any, required: true

  defp deaths_summary(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-medium text-zinc-400 mb-3">
        Deaths ({@summary.deaths_summary.total})
      </h3>
      <div class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <div class="flex items-center gap-4 mb-3">
          <div>
            <span class="text-zinc-500 text-sm">First death:</span>
            <span class="text-zinc-200 ml-2">{@summary.deaths_summary.first_death_player}</span>
            <span class="text-zinc-500 ml-1">at {format_time(@summary.deaths_summary.first_death_time)}</span>
          </div>
        </div>
        <div class="flex flex-wrap gap-2">
          <div :for={{cause, count} <- @summary.deaths_summary.deaths_by_cause |> Enum.take(5)} class="inline-flex items-center px-2 py-1 rounded text-xs bg-zinc-700">
            <span class="text-red-400">{cause}</span>
            <span class="text-zinc-500 ml-1">({count})</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :summary, :any, required: true
  attr :player_classes, :map, required: true

  defp critical_failures(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-medium text-zinc-400 mb-3">Critical Issues</h3>
      <div class="space-y-3">
        <div :for={failure <- @summary.critical_failures} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
          <div class="flex justify-between items-start mb-2">
            <span class={[
              "font-medium",
              mechanic_type_color(failure.mechanic_type)
            ]}>
              <.wowhead_link spell_id={failure.spell_id} name={failure.spell_name} />
            </span>
            <span class={[
              "text-xs px-2 py-1 rounded",
              severity_badge_color(failure.severity)
            ]}>
              {String.upcase(to_string(failure.severity))}
            </span>
          </div>
          <p class="text-sm text-zinc-400 mb-2">
            {failure.failure_count} failure(s)
            <span :if={failure.total_damage > 0} class="text-zinc-500">
              &bull; {format_number(failure.total_damage)} damage
            </span>
          </p>
          <div :if={failure.players_involved != []} class="flex flex-wrap gap-1">
            <span :for={player <- failure.players_involved} class="text-xs px-2 py-0.5 bg-zinc-700 rounded">
              <.player_name name={player} player_classes={@player_classes} />
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :missed_interrupts, :list, required: true

  defp missed_interrupts(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-medium text-yellow-400 mb-3">Missed Interrupts</h3>
      <div class="bg-zinc-800 rounded-lg overflow-hidden">
        <table class="w-full">
          <thead class="bg-zinc-750">
            <tr>
              <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Spell</th>
              <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Missed</th>
              <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">First At</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-700">
            <tr :for={missed <- @missed_interrupts} class="hover:bg-zinc-750">
              <td class="px-4 py-2 text-yellow-400">
                <.wowhead_link spell_id={missed.spell_id} name={missed.spell_name} />
              </td>
              <td class="px-4 py-2 text-right text-zinc-300">{missed.missed_count}</td>
              <td class="px-4 py-2 text-zinc-500 font-mono text-sm">{format_time(missed.first_miss_at)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :problem_players, :list, required: true
  attr :player_classes, :map, required: true

  defp problem_players(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-medium text-zinc-400 mb-3">Players Needing Attention</h3>
      <div class="bg-zinc-800 rounded-lg overflow-hidden">
        <table class="w-full">
          <thead class="bg-zinc-750">
            <tr>
              <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Player</th>
              <th class="text-center text-xs font-medium text-zinc-400 px-4 py-2">Status</th>
              <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Issues</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-700">
            <tr :for={player <- @problem_players} class="hover:bg-zinc-750">
              <td class="px-4 py-2">
                <.player_name name={player.name} player_classes={@player_classes} />
              </td>
              <td class="px-4 py-2 text-center">
                <span :if={player.died} class="text-xs px-2 py-0.5 bg-red-900 text-red-300 rounded">DIED</span>
                <span :if={player.failure_count > 0 && !player.died} class="text-xs px-2 py-0.5 bg-yellow-900 text-yellow-300 rounded">
                  {player.failure_count} fail(s)
                </span>
              </td>
              <td class="px-4 py-2 text-zinc-500 text-sm">
                {Enum.join(player.failed_mechanics, ", ")}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :recommendations, :list, required: true

  defp recommendations(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-medium text-green-400 mb-3">Next Pull Focus</h3>
      <div class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <ol class="space-y-2">
          <li :for={{rec, idx} <- Enum.with_index(@recommendations, 1)} class="flex gap-3">
            <span class="text-zinc-500 font-mono">{idx}.</span>
            <span class="text-zinc-200">{rec}</span>
          </li>
        </ol>
      </div>
    </div>
    """
  end
end
