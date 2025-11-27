defmodule WeGoNextWeb.EncounterLive.Show do
  use WeGoNextWeb, :live_view

  alias WeGoNext.{EncounterStore, Encounter}
  alias WeGoNext.Analyzers.{DeathAnalyzer, DamageTakenAnalyzer, InterruptAnalyzer, DebuffAnalyzer}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    id = String.to_integer(id)
    encounter = EncounterStore.get_encounter(id)

    if encounter do
      {:ok,
       socket
       |> assign(:page_title, encounter.name)
       |> assign(:encounter_id, id)
       |> assign(:encounter, encounter)
       |> assign(:active_tab, :deaths)
       |> load_analysis()}
    else
      {:ok,
       socket
       |> put_flash(:error, "Encounter not found")
       |> push_navigate(to: ~p"/")}
    end
  end

  defp load_analysis(socket) do
    encounter = socket.assigns.encounter

    socket
    |> assign(:deaths, DeathAnalyzer.analyze(encounter))
    |> assign(:damage_stats, DamageTakenAnalyzer.analyze(encounter))
    |> assign(:interrupt_stats, InterruptAnalyzer.analyze(encounter))
    |> assign(:debuff_stats, DebuffAnalyzer.analyze(encounter))
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_atom(tab))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.back navigate={~p"/"}>Back to encounters</.back>

      <%!-- Encounter header --%>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-wow-gold">{@encounter.name}</h1>
          <p class="text-zinc-400">
            {@encounter.difficulty_name} &bull; {format_duration(@encounter)}
          </p>
        </div>
        <span class={[
          "inline-flex items-center px-3 py-1.5 rounded text-sm font-medium",
          if(@encounter.success, do: "bg-green-900 text-green-300", else: "bg-red-900 text-red-300")
        ]}>
          {if @encounter.success, do: "KILL", else: "WIPE"}
        </span>
      </div>

      <%!-- Quick stats --%>
      <div class="grid grid-cols-4 gap-4">
        <div class="stat-block">
          <div class="stat-value text-wow-death">{length(@deaths)}</div>
          <div class="stat-label">Deaths</div>
        </div>
        <div class="stat-block">
          <div class="stat-value">{total_interrupts(@interrupt_stats)}</div>
          <div class="stat-label">Interrupts</div>
        </div>
        <div class="stat-block">
          <div class="stat-value text-red-400">{length(@interrupt_stats.missed_casts)}</div>
          <div class="stat-label">Missed Kicks</div>
        </div>
        <div class="stat-block">
          <div class="stat-value">{map_size(@debuff_stats.by_spell)}</div>
          <div class="stat-label">Unique Debuffs</div>
        </div>
      </div>

      <%!-- Tabs --%>
      <div class="border-b border-zinc-700">
        <nav class="flex gap-4" aria-label="Tabs">
          <.tab_button tab={:deaths} active={@active_tab} count={length(@deaths)}>
            Deaths
          </.tab_button>
          <.tab_button tab={:damage} active={@active_tab} count={nil}>
            Damage Taken
          </.tab_button>
          <.tab_button tab={:interrupts} active={@active_tab} count={total_interrupts(@interrupt_stats)}>
            Interrupts
          </.tab_button>
          <.tab_button tab={:debuffs} active={@active_tab} count={map_size(@debuff_stats.by_spell)}>
            Debuffs
          </.tab_button>
        </nav>
      </div>

      <%!-- Tab content --%>
      <div class="min-h-[400px]">
        <.deaths_tab :if={@active_tab == :deaths} deaths={@deaths} />
        <.damage_tab :if={@active_tab == :damage} stats={@damage_stats} encounter={@encounter} />
        <.interrupts_tab :if={@active_tab == :interrupts} stats={@interrupt_stats} />
        <.debuffs_tab :if={@active_tab == :debuffs} stats={@debuff_stats} />
      </div>
    </div>
    """
  end

  # Tab button component
  attr :tab, :atom, required: true
  attr :active, :atom, required: true
  attr :count, :any, default: nil
  slot :inner_block, required: true

  defp tab_button(assigns) do
    ~H"""
    <button
      phx-click="switch_tab"
      phx-value-tab={@tab}
      class={[
        "pb-3 px-1 text-sm font-medium border-b-2 transition-colors",
        if(@active == @tab,
          do: "border-wow-gold text-wow-gold",
          else: "border-transparent text-zinc-400 hover:text-zinc-200 hover:border-zinc-600")
      ]}
    >
      {render_slot(@inner_block)}
      <span :if={@count} class="ml-1 text-zinc-500">({@count})</span>
    </button>
    """
  end

  # Deaths tab
  attr :deaths, :list, required: true

  defp deaths_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div :if={@deaths == []} class="text-zinc-500 text-center py-8">
        No deaths in this encounter
      </div>
      <div :for={death <- @deaths} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <div class="flex items-center justify-between mb-2">
          <div class="flex items-center gap-3">
            <span class="text-wow-death font-mono">{format_time(death.time_into_fight)}</span>
            <span class="font-semibold text-zinc-100">{death.player_name}</span>
          </div>
          <span :if={death.killing_blow} class="text-sm text-zinc-400">
            {death.killing_blow.ability} ({format_number(death.killing_blow.amount)})
          </span>
        </div>
        <div :if={death.killing_blow} class="text-sm text-zinc-400 mb-2">
          Killed by <span class="text-zinc-300">{death.killing_blow.source}</span>
          <span :if={death.killing_blow.overkill > 0} class="text-red-400 ml-2">
            ({format_number(death.killing_blow.overkill)} overkill)
          </span>
        </div>
        <div :if={death.recap != []} class="mt-3 pt-3 border-t border-zinc-700">
          <div class="text-xs text-zinc-500 mb-2">Last damage taken:</div>
          <div class="space-y-1">
            <div :for={event <- Enum.take(death.recap, 5)} class="text-sm flex justify-between">
              <span class="text-zinc-400">{event.ability_name}</span>
              <span class="text-zinc-500">
                {format_number(event.amount)} from {event.source_name}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Damage taken tab
  attr :stats, :map, required: true
  attr :encounter, :any, required: true

  defp damage_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Top avoidable abilities --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Top Damaging Abilities (Non-Tank)</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Ability</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Total</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Hits</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Players</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={ability <- top_avoidable_abilities(@stats)} class="hover:bg-zinc-750">
                <td class="px-4 py-2 text-zinc-200">{ability.name}</td>
                <td class="px-4 py-2 text-right text-zinc-400">{format_number(ability.total)}</td>
                <td class="px-4 py-2 text-right text-zinc-500">{ability.hits}</td>
                <td class="px-4 py-2 text-right text-zinc-500">{ability.players}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Player damage breakdown --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Damage Taken by Player</h3>
        <div class="grid grid-cols-2 gap-4">
          <div :for={player <- sorted_players(@stats)} class="bg-zinc-800 rounded-lg p-3">
            <div class="flex justify-between items-center mb-2">
              <span class={[
                "font-medium",
                if(player.is_tank, do: "text-wow-tank", else: "text-zinc-200")
              ]}>
                {player.name}
                <span :if={player.is_tank} class="text-xs text-zinc-500 ml-1">(Tank)</span>
              </span>
              <span class="text-zinc-400">{format_number(player.total)}</span>
            </div>
            <div class="text-xs text-zinc-500">
              DTPS: {format_number(trunc(player.total / max(1, fight_seconds(@encounter))))}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Interrupts tab
  attr :stats, :map, required: true

  defp interrupts_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- By player --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Interrupts by Player</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Player</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Total</th>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Spells Interrupted</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={{name, data} <- sorted_interrupters(@stats)} class="hover:bg-zinc-750">
                <td class="px-4 py-2 text-zinc-200">{name}</td>
                <td class="px-4 py-2 text-right text-green-400 font-medium">{data.total_interrupts}</td>
                <td class="px-4 py-2 text-zinc-400 text-sm">
                  {data.spells_interrupted |> Map.keys() |> Enum.join(", ")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Missed interrupts --%>
      <div :if={@stats.missed_casts != []}>
        <h3 class="text-sm font-medium text-red-400 mb-3">
          Missed Interrupts ({length(@stats.missed_casts)})
        </h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Time</th>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Spell</th>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Caster</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={cast <- Enum.take(@stats.missed_casts, 20)} class="hover:bg-zinc-750">
                <td class="px-4 py-2 text-zinc-500 font-mono text-sm">
                  {format_timestamp(cast.timestamp)}
                </td>
                <td class="px-4 py-2 text-red-400">{cast.spell_name}</td>
                <td class="px-4 py-2 text-zinc-400">{cast.caster_name}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Debuffs tab
  attr :stats, :map, required: true

  defp debuffs_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Top debuffs by application count --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Most Applied Debuffs</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Debuff</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Applications</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Players Hit</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={debuff <- top_debuffs(@stats)} class="hover:bg-zinc-750">
                <td class="px-4 py-2 text-wow-epic">{debuff.name}</td>
                <td class="px-4 py-2 text-right text-zinc-400">{debuff.count}</td>
                <td class="px-4 py-2 text-right text-zinc-500">{debuff.players}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Players with most debuffs --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Players with Most Debuffs</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Player</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Debuffs</th>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Types</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={{name, data} <- players_by_debuffs(@stats)} class="hover:bg-zinc-750">
                <td class="px-4 py-2 text-zinc-200">{name}</td>
                <td class="px-4 py-2 text-right text-zinc-400">{length(data.debuffs)}</td>
                <td class="px-4 py-2 text-zinc-500 text-sm">
                  {data.debuffs |> Enum.map(& &1.spell_name) |> Enum.uniq() |> Enum.take(3) |> Enum.join(", ")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp format_duration(%Encounter{fight_time_ms: ms}) when is_integer(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_duration(_), do: "0:00"

  defp format_time(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_number(num) when is_integer(num) and num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  defp format_number(num) when is_integer(num) and num >= 1000 do
    "#{Float.round(num / 1000, 0) |> trunc()}k"
  end

  defp format_number(num) when is_number(num), do: to_string(trunc(num))
  defp format_number(_), do: "0"

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%M:%S")
  end

  defp total_interrupts(stats) do
    stats.by_player
    |> Map.values()
    |> Enum.map(& &1.total_interrupts)
    |> Enum.sum()
  end

  defp fight_seconds(%Encounter{fight_time_ms: ms}) when is_integer(ms), do: div(ms, 1000)
  defp fight_seconds(_), do: 1

  defp top_avoidable_abilities(stats) do
    DamageTakenAnalyzer.top_avoidable_abilities(stats, 10)
    |> Enum.map(fn {name, total, hits, players} ->
      %{name: name, total: total, hits: hits, players: players}
    end)
  end

  defp sorted_players(stats) do
    stats.all
    |> Enum.sort_by(& &1.total, :desc)
  end

  defp sorted_interrupters(stats) do
    stats.by_player
    |> Enum.sort_by(fn {_, data} -> data.total_interrupts end, :desc)
  end

  defp top_debuffs(stats) do
    stats.by_spell
    |> Enum.map(fn {name, data} ->
      %{name: name, count: data.count, players: map_size(data.players)}
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(15)
  end

  defp players_by_debuffs(stats) do
    stats.by_player
    |> Enum.sort_by(fn {_, data} -> length(data.debuffs) end, :desc)
    |> Enum.take(10)
  end
end
