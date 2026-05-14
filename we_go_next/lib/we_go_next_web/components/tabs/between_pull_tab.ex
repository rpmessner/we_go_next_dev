defmodule WeGoNextWeb.Components.Tabs.BetweenPullTab do
  @moduledoc """
  Between-pull dashboard: group diagnosis + personal report card.

  Designed for glanceability on a second monitor between pulls.
  Left column: what killed us (group). Right column: how did I do (personal).
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents

  attr :summary, :any, required: true
  attr :deaths, :list, required: true
  attr :failure_stats, :map, required: true
  attr :interrupt_stats, :map, required: true
  attr :damage_done, :map, required: true
  attr :player_classes, :map, required: true
  attr :character_name, :string, default: nil

  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-5 gap-6">
      <%!-- Left: Group Diagnosis --%>
      <div class="lg:col-span-3 space-y-4 stagger-children">
        <.result_banner summary={@summary} />
        <.group_deaths summary={@summary} player_classes={@player_classes} />
        <.group_failures summary={@summary} player_classes={@player_classes} />
        <.group_interrupts summary={@summary} />
        <.group_recommendations summary={@summary} />
      </div>

      <%!-- Right: Personal Report Card --%>
      <div class="lg:col-span-2 animate-fade-in">
        <.personal_report
          deaths={@deaths}
          failure_stats={@failure_stats}
          interrupt_stats={@interrupt_stats}
          damage_done={@damage_done}
          player_classes={@player_classes}
          character_name={@character_name}
        />
      </div>
    </div>
    """
  end

  # ── Group Diagnosis ──

  defp result_banner(assigns) do
    ~H"""
    <div :if={@summary.result == :wipe && @summary.wipe_cause} class="result-wipe animate-fade-in-up">
      <div class="flex items-center justify-between">
        <div>
          <h3 class="text-red-400 font-display font-bold text-2xl uppercase tracking-wide">Wipe</h3>
          <p class="text-zinc-300 text-sm mt-1">{@summary.wipe_cause}</p>
        </div>
        <span class="text-zinc-500 font-mono text-base">{@summary.duration_str}</span>
      </div>
    </div>
    <div :if={@summary.result == :kill} class="result-kill animate-fade-in-up">
      <div class="flex items-center justify-between">
        <h3 class="text-green-400 font-display font-bold text-2xl uppercase tracking-wide">Kill!</h3>
        <span class="text-zinc-500 font-mono text-base">{@summary.duration_str}</span>
      </div>
    </div>
    """
  end

  defp group_deaths(assigns) do
    deaths_summary = assigns.summary.deaths_summary

    assigns =
      assigns
      |> assign(:deaths_summary, deaths_summary)
      |> assign(:has_deaths, deaths_summary.total > 0)

    ~H"""
    <div :if={@has_deaths} class="bg-zinc-800/70 rounded-lg p-4 border border-zinc-700/50">
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-display font-semibold text-zinc-400 uppercase tracking-wide">Deaths</h3>
        <span class="text-red-400 font-mono font-bold text-2xl">{@deaths_summary.total}</span>
      </div>

      <div :if={@deaths_summary.first_death_player} class="text-sm mb-2">
        <span class="text-zinc-500">First:</span>
        <.player_name name={@deaths_summary.first_death_player} player_classes={@player_classes} />
        <span class="text-zinc-500 font-mono ml-1">at {format_time(@deaths_summary.first_death_time)}</span>
      </div>

      <div class="flex flex-wrap gap-1.5">
        <div
          :for={{cause, count} <- @deaths_summary.deaths_by_cause |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.take(5)}
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs bg-zinc-700"
        >
          <span class="text-red-400">{cause}</span>
          <span class="text-zinc-500">{count}</span>
        </div>
      </div>
    </div>
    """
  end

  defp group_failures(assigns) do
    ~H"""
    <div :if={@summary.critical_failures != []} class="bg-zinc-800/70 rounded-lg p-4 border border-zinc-700/50">
      <h3 class="text-sm font-display font-semibold text-zinc-400 uppercase tracking-wide mb-3">Mechanic Failures</h3>
      <div class="space-y-2">
        <div :for={failure <- @summary.critical_failures} class="flex items-start justify-between">
          <div>
            <span class={["text-sm font-medium", mechanic_type_color(failure.mechanic_type)]}>
              <.wowhead_link spell_id={failure.spell_id} name={failure.spell_name} />
            </span>
            <div :if={failure.players_involved != []} class="flex flex-wrap gap-1 mt-1">
              <span :for={player <- failure.players_involved} class="text-xs text-zinc-400">
                <.player_name name={player} player_classes={@player_classes} />
              </span>
            </div>
          </div>
          <div class="text-right shrink-0 ml-2">
            <span class={["text-xs px-1.5 py-0.5 rounded", severity_badge_color(failure.severity)]}>
              {failure.failure_count}x
            </span>
          </div>
        </div>
      </div>
    </div>

    <div :if={@summary.critical_failures == [] && @summary.result == :wipe} class="bg-zinc-800/50 rounded-lg p-3 border border-zinc-700/30 border-dashed">
      <p class="text-zinc-500 text-sm">
        No tracked failures. Mark mechanics in the Damage Taken tab.
      </p>
    </div>
    """
  end

  defp group_interrupts(assigns) do
    ~H"""
    <div :if={@summary.missed_interrupts != []} class="bg-zinc-800/70 rounded-lg p-4 border border-zinc-700/50">
      <h3 class="text-sm font-display font-semibold text-yellow-400 uppercase tracking-wide mb-3">Missed Interrupts</h3>
      <div class="space-y-1.5">
        <div :for={missed <- @summary.missed_interrupts} class="flex items-center justify-between text-sm">
          <span class="text-yellow-400">
            <.wowhead_link spell_id={missed.spell_id} name={missed.spell_name} />
          </span>
          <span class="text-zinc-500 font-mono text-xs">
            {missed.missed_count}x missed
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp group_recommendations(assigns) do
    ~H"""
    <div :if={@summary.recommendations != []} class="bg-zinc-800/70 rounded-lg p-4 border border-zinc-700/50">
      <h3 class="text-sm font-display font-semibold text-green-400 uppercase tracking-wide mb-2">Next Pull</h3>
      <ol class="space-y-1">
        <li :for={{rec, idx} <- Enum.with_index(@summary.recommendations, 1)} class="flex gap-2 text-sm">
          <span class="text-zinc-500 font-mono">{idx}.</span>
          <span class="text-zinc-300">{rec}</span>
        </li>
      </ol>
    </div>
    """
  end

  # ── Personal Report Card ──

  attr :deaths, :list, required: true
  attr :failure_stats, :map, required: true
  attr :interrupt_stats, :map, required: true
  attr :damage_done, :map, required: true
  attr :player_classes, :map, required: true
  attr :character_name, :string, default: nil

  defp personal_report(%{character_name: nil} = assigns) do
    ~H"""
    <div class="bg-zinc-800 rounded-lg p-4 border border-zinc-700 border-dashed">
      <p class="text-zinc-500 text-sm">
        Set your character name in
        <a href="/settings" class="text-wow-gold hover:underline">Settings</a>
        for a personal report card.
      </p>
    </div>
    """
  end

  defp personal_report(%{character_name: ""} = assigns) do
    ~H"""
    <div class="bg-zinc-800 rounded-lg p-4 border border-zinc-700 border-dashed">
      <p class="text-zinc-500 text-sm">
        Set your character name in
        <a href="/settings" class="text-wow-gold hover:underline">Settings</a>
        for a personal report card.
      </p>
    </div>
    """
  end

  defp personal_report(assigns) do
    my_deaths = filter_my_deaths(assigns.deaths, assigns.character_name)
    my_failures = filter_my_failures(assigns.failure_stats, assigns.character_name)
    my_interrupts = filter_my_interrupts(assigns.interrupt_stats, assigns.character_name)
    {my_dps, my_rank, dps_count} = find_my_dps(assigns.damage_done, assigns.character_name)

    assigns =
      assigns
      |> assign(:my_deaths, my_deaths)
      |> assign(:my_failures, my_failures)
      |> assign(:my_interrupts, my_interrupts)
      |> assign(:my_dps, my_dps)
      |> assign(:my_rank, my_rank)
      |> assign(:dps_count, dps_count)

    ~H"""
    <div class="glass-card rounded-lg overflow-hidden">
      <%!-- Header --%>
      <div class="px-4 py-3 bg-zinc-900/50 border-b border-zinc-700/30">
        <h3 class="font-display font-bold text-lg">
          <.player_name name={@character_name} player_classes={@player_classes} />
        </h3>
      </div>

      <div class="p-4 space-y-4">
        <%!-- Status badges --%>
        <div class="flex flex-wrap gap-2">
          <span :if={@my_deaths == []} class="text-xs font-display font-semibold uppercase tracking-wide px-2.5 py-1 rounded bg-green-900/50 text-green-400 border border-green-800/50 animate-pulse-once">
            Survived
          </span>
          <span :if={@my_deaths != []} class="text-xs font-display font-semibold uppercase tracking-wide px-2.5 py-1 rounded bg-red-900/50 text-red-400 border border-red-800/50 animate-pulse-once">
            Died ({length(@my_deaths)})
          </span>
          <span :if={@my_failures != []} class="text-xs font-display font-semibold uppercase tracking-wide px-2.5 py-1 rounded bg-orange-900/50 text-orange-400 border border-orange-800/50">
            {length(@my_failures)} fail(s)
          </span>
          <span :if={@my_interrupts} class="text-xs font-display font-semibold uppercase tracking-wide px-2.5 py-1 rounded bg-blue-900/50 text-blue-400 border border-blue-800/50">
            {@my_interrupts.total_interrupts} kick(s)
          </span>
        </div>

        <%!-- Deaths detail --%>
        <div :if={@my_deaths != []} class="space-y-1.5">
          <h4 class="text-xs font-display font-semibold text-zinc-500 uppercase tracking-wider">Deaths</h4>
          <div :for={death <- @my_deaths} class="text-sm">
            <span class="text-red-400">{death.killing_blow.ability}</span>
            <span class="text-zinc-500"> from </span>
            <span class="text-zinc-300">{death.killing_blow.source}</span>
            <span class="text-zinc-600 font-mono text-xs ml-1">
              at {format_time(death.time_into_fight)}
            </span>
          </div>
        </div>

        <%!-- Failures detail --%>
        <div :if={@my_failures != []} class="space-y-1.5">
          <h4 class="text-xs font-display font-semibold text-zinc-500 uppercase tracking-wider">Failures</h4>
          <div :for={failure <- @my_failures} class="text-sm">
            <span class={mechanic_type_color(failure.mechanic_type)}>
              {failure.spell_name}
            </span>
            <span class="text-zinc-500 text-xs ml-1">{failure.reason}</span>
          </div>
        </div>

        <%!-- Kicks detail --%>
        <div :if={@my_interrupts && @my_interrupts.total_interrupts > 0} class="space-y-1.5">
          <h4 class="text-xs font-display font-semibold text-zinc-500 uppercase tracking-wider">Interrupts</h4>
          <div class="text-sm text-zinc-300">
            <span class="text-green-400 font-mono font-bold">{@my_interrupts.total_interrupts}</span>
            <span class="text-zinc-500"> kick(s): </span>
            <span class="text-zinc-400">
              {Enum.map_join(@my_interrupts.by_spell, ", ", fn {spell, count} -> "#{spell} (#{count})" end)}
            </span>
          </div>
        </div>

        <%!-- DPS --%>
        <div :if={@my_dps} class="space-y-1.5">
          <h4 class="text-xs font-display font-semibold text-zinc-500 uppercase tracking-wider">DPS</h4>
          <div class="flex items-baseline gap-2">
            <span class="text-2xl font-mono font-bold text-zinc-100">{format_dps(@my_dps)}</span>
            <span :if={@my_rank && @dps_count > 0} class="text-sm font-mono text-zinc-500">
              #{@my_rank} of {@dps_count}
            </span>
          </div>
        </div>

        <%!-- Clean run --%>
        <div :if={@my_deaths == [] && @my_failures == []} class="text-sm font-display font-semibold text-green-400 bg-green-900/20 rounded px-3 py-2 border border-green-800/30">
          Clean pull — no deaths or failures.
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ──

  defp match_character?(player_name, character_name) when is_binary(player_name) and is_binary(character_name) do
    # Player names in combat log include realm: "Mittwoch-WyrmrestAccord"
    # Match against just the character name portion
    String.starts_with?(player_name, character_name <> "-") or player_name == character_name
  end

  defp match_character?(_, _), do: false

  defp filter_my_deaths(deaths, character_name) do
    Enum.filter(deaths, fn death ->
      match_character?(death.player_name, character_name)
    end)
  end

  defp filter_my_failures(failure_stats, character_name) do
    failure_stats
    |> Map.get(:by_player, %{})
    |> Enum.flat_map(fn {name, failures} ->
      if match_character?(name, character_name), do: failures, else: []
    end)
  end

  defp filter_my_interrupts(interrupt_stats, character_name) do
    interrupt_stats
    |> Map.get(:by_player, %{})
    |> Enum.find_value(fn {_guid, data} ->
      if match_character?(data.player_name, character_name), do: data
    end)
  end

  defp find_my_dps(damage_done, character_name) do
    dps_list = Map.get(damage_done, :dps_healers, [])

    case Enum.find_index(dps_list, fn p -> match_character?(p.player_name, character_name) end) do
      nil ->
        {nil, nil, length(dps_list)}

      idx ->
        player = Enum.at(dps_list, idx)
        {player.dps, idx + 1, length(dps_list)}
    end
  end
end
