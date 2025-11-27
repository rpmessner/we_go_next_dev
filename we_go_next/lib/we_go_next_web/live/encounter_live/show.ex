defmodule WeGoNextWeb.EncounterLive.Show do
  use WeGoNextWeb, :live_view

  alias WeGoNext.{EncounterStore, Encounter, Criteria}
  alias WeGoNext.Criteria.MechanicCriteria
  alias WeGoNext.Analyzers.{DeathAnalyzer, DamageTakenAnalyzer, InterruptAnalyzer, DebuffAnalyzer, FailureAnalyzer}

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

    # Load criteria for this boss
    criteria_by_spell = Criteria.criteria_by_spell_id(encounter.id)

    socket
    |> assign(:deaths, DeathAnalyzer.analyze(encounter))
    |> assign(:damage_stats, DamageTakenAnalyzer.analyze(encounter))
    |> assign(:interrupt_stats, InterruptAnalyzer.analyze(encounter))
    |> assign(:debuff_stats, DebuffAnalyzer.analyze(encounter))
    |> assign(:failure_stats, FailureAnalyzer.analyze(encounter))
    |> assign(:criteria_by_spell, criteria_by_spell)
    |> assign(:show_criteria_modal, false)
    |> assign(:modal_spell_id, nil)
    |> assign(:modal_spell_name, nil)
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_atom(tab))}
  end

  @impl true
  def handle_event("open_track_modal", %{"spell-id" => spell_id, "spell-name" => spell_name}, socket) do
    {:noreply,
     socket
     |> assign(:show_criteria_modal, true)
     |> assign(:modal_spell_id, String.to_integer(spell_id))
     |> assign(:modal_spell_name, spell_name)}
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_criteria_modal, false)
     |> assign(:modal_spell_id, nil)
     |> assign(:modal_spell_name, nil)}
  end

  @impl true
  def handle_event("create_criteria", %{"mechanic_type" => mechanic_type}, socket) do
    encounter = socket.assigns.encounter
    spell_id = socket.assigns.modal_spell_id
    spell_name = socket.assigns.modal_spell_name

    attrs = %{
      spell_id: spell_id,
      spell_name: spell_name,
      mechanic_type: mechanic_type,
      boss_encounter_id: encounter.id,
      boss_name: encounter.name,
      threshold: default_threshold(mechanic_type),
      active: true
    }

    case Criteria.create_criteria(attrs) do
      {:ok, _criteria} ->
        # Reload criteria
        criteria_by_spell = Criteria.criteria_by_spell_id(encounter.id)

        {:noreply,
         socket
         |> assign(:criteria_by_spell, criteria_by_spell)
         |> assign(:show_criteria_modal, false)
         |> assign(:modal_spell_id, nil)
         |> assign(:modal_spell_name, nil)
         |> put_flash(:info, "#{spell_name} marked as #{MechanicCriteria.type_label(mechanic_type)}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create criteria")}
    end
  end

  @impl true
  def handle_event("remove_criteria", %{"spell-id" => spell_id_str}, socket) do
    spell_id = String.to_integer(spell_id_str)
    encounter = socket.assigns.encounter

    # Find and delete criteria for this spell
    case Criteria.get_criteria_for_spell(spell_id, encounter.id) do
      [criteria | _] ->
        Criteria.delete_criteria(criteria)
        criteria_by_spell = Criteria.criteria_by_spell_id(encounter.id)

        {:noreply,
         socket
         |> assign(:criteria_by_spell, criteria_by_spell)
         |> put_flash(:info, "Criteria removed")}

      [] ->
        {:noreply, socket}
    end
  end

  defp default_threshold("avoidable"), do: %{"max_hits" => 0}
  defp default_threshold("interrupt"), do: %{"must_interrupt" => true}
  defp default_threshold(_), do: %{}

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
      <div class="grid grid-cols-5 gap-4">
        <div class="stat-block">
          <div class="stat-value text-wow-death">{length(@deaths)}</div>
          <div class="stat-label">Deaths</div>
        </div>
        <div class={[
          "stat-block",
          if(@failure_stats.summary.total_failures > 0, do: "ring-2 ring-red-500/50", else: "")
        ]}>
          <div class={[
            "stat-value",
            if(@failure_stats.summary.total_failures > 0, do: "text-red-400", else: "text-green-400")
          ]}>
            {@failure_stats.summary.total_failures}
          </div>
          <div class="stat-label">Failures</div>
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
          <div class="stat-value">{map_size(@criteria_by_spell)}</div>
          <div class="stat-label">Tracked</div>
        </div>
      </div>

      <%!-- Tabs --%>
      <div class="border-b border-zinc-700">
        <nav class="flex gap-4" aria-label="Tabs">
          <.tab_button tab={:failures} active={@active_tab} count={@failure_stats.summary.total_failures} highlight={@failure_stats.summary.total_failures > 0}>
            Failures
          </.tab_button>
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
        <.failures_tab :if={@active_tab == :failures} stats={@failure_stats} />
        <.deaths_tab :if={@active_tab == :deaths} deaths={@deaths} />
        <.damage_tab :if={@active_tab == :damage} stats={@damage_stats} encounter={@encounter} criteria_by_spell={@criteria_by_spell} />
        <.interrupts_tab :if={@active_tab == :interrupts} stats={@interrupt_stats} criteria_by_spell={@criteria_by_spell} />
        <.debuffs_tab :if={@active_tab == :debuffs} stats={@debuff_stats} />
      </div>

      <%!-- Criteria selection modal --%>
      <.criteria_modal
        :if={@show_criteria_modal}
        spell_name={@modal_spell_name}
        spell_id={@modal_spell_id}
      />
    </div>
    """
  end

  # Criteria selection modal component
  attr :spell_name, :string, required: true
  attr :spell_id, :integer, required: true

  defp criteria_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center" phx-click="close_modal">
      <div class="bg-zinc-800 rounded-lg p-6 max-w-md w-full mx-4 border border-zinc-600" phx-click-away="close_modal">
        <h3 class="text-lg font-semibold text-wow-gold mb-2">Track Mechanic</h3>
        <p class="text-zinc-400 mb-4">
          Mark <span class="text-zinc-200 font-medium">{@spell_name}</span> as:
        </p>

        <div class="space-y-2">
          <button
            phx-click="create_criteria"
            phx-value-mechanic_type="avoidable"
            class="w-full text-left px-4 py-3 rounded bg-zinc-700 hover:bg-zinc-600 transition-colors"
          >
            <span class="text-red-400 font-medium">Avoidable Damage</span>
            <p class="text-sm text-zinc-400">Damage players should avoid (standing in fire)</p>
          </button>

          <button
            phx-click="create_criteria"
            phx-value-mechanic_type="interrupt"
            class="w-full text-left px-4 py-3 rounded bg-zinc-700 hover:bg-zinc-600 transition-colors"
          >
            <span class="text-yellow-400 font-medium">Must Interrupt</span>
            <p class="text-sm text-zinc-400">Casts that must be kicked</p>
          </button>

          <button
            phx-click="create_criteria"
            phx-value-mechanic_type="soak"
            class="w-full text-left px-4 py-3 rounded bg-zinc-700 hover:bg-zinc-600 transition-colors"
          >
            <span class="text-blue-400 font-medium">Soak Mechanic</span>
            <p class="text-sm text-zinc-400">Damage that needs to be shared</p>
          </button>

          <button
            phx-click="create_criteria"
            phx-value-mechanic_type="spread"
            class="w-full text-left px-4 py-3 rounded bg-zinc-700 hover:bg-zinc-600 transition-colors"
          >
            <span class="text-purple-400 font-medium">Spread Out</span>
            <p class="text-sm text-zinc-400">Players need to spread apart</p>
          </button>
        </div>

        <button
          phx-click="close_modal"
          class="mt-4 w-full px-4 py-2 text-zinc-400 hover:text-zinc-200 transition-colors"
        >
          Cancel
        </button>
      </div>
    </div>
    """
  end

  # Tab button component
  attr :tab, :atom, required: true
  attr :active, :atom, required: true
  attr :count, :any, default: nil
  attr :highlight, :boolean, default: false
  slot :inner_block, required: true

  defp tab_button(assigns) do
    ~H"""
    <button
      phx-click="switch_tab"
      phx-value-tab={@tab}
      class={[
        "pb-3 px-1 text-sm font-medium border-b-2 transition-colors",
        cond do
          @active == @tab -> "border-wow-gold text-wow-gold"
          @highlight -> "border-transparent text-red-400 hover:text-red-300 hover:border-red-600"
          true -> "border-transparent text-zinc-400 hover:text-zinc-200 hover:border-zinc-600"
        end
      ]}
    >
      {render_slot(@inner_block)}
      <span :if={@count} class={["ml-1", if(@highlight && @count > 0, do: "text-red-400", else: "text-zinc-500")]}>
        ({@count})
      </span>
    </button>
    """
  end

  # Failures tab
  attr :stats, :map, required: true

  defp failures_tab(assigns) do
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
        <div>
          <h3 class="text-sm font-medium text-zinc-400 mb-3">Failures by Mechanic</h3>
          <div class="space-y-3">
            <div :for={{spell_name, failures} <- sorted_by_mechanic(@stats)} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
              <div class="flex items-center justify-between mb-2">
                <span class={[
                  "font-medium",
                  failure_type_color(List.first(failures))
                ]}>
                  {spell_name}
                </span>
                <span class="text-red-400 font-mono">{length(failures)} failure(s)</span>
              </div>
              <div class="flex flex-wrap gap-2">
                <span
                  :for={failure <- failures}
                  class="inline-flex items-center px-2 py-1 rounded text-xs bg-zinc-700"
                >
                  <span class="text-zinc-200">{failure.player_name}</span>
                  <span :if={failure.hit_count > 0} class="ml-1 text-zinc-400">
                    ({failure.hit_count} hits)
                  </span>
                </span>
              </div>
            </div>
          </div>
        </div>

        <%!-- By Player --%>
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
                  <td class="px-4 py-2 text-zinc-200">{player}</td>
                  <td class="px-4 py-2 text-right text-red-400 font-medium">{length(failures)}</td>
                  <td class="px-4 py-2 text-zinc-400 text-sm">
                    {failures |> Enum.map(& &1.spell_name) |> Enum.uniq() |> Enum.join(", ")}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
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
  attr :criteria_by_spell, :map, required: true

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
                <th class="text-center text-xs font-medium text-zinc-400 px-4 py-2">Track</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={ability <- top_avoidable_abilities(@stats)} class="hover:bg-zinc-750">
                <td class="px-4 py-2">
                  <span class={[
                    if(Map.has_key?(@criteria_by_spell, ability.ability_id),
                      do: criteria_color(@criteria_by_spell, ability.ability_id),
                      else: "text-zinc-200")
                  ]}>
                    {ability.name}
                  </span>
                  <span :if={criteria = get_criteria(@criteria_by_spell, ability.ability_id)} class="ml-2 text-xs">
                    ({MechanicCriteria.type_label(criteria.mechanic_type)})
                  </span>
                </td>
                <td class="px-4 py-2 text-right text-zinc-400">{format_number(ability.total)}</td>
                <td class="px-4 py-2 text-right text-zinc-500">{ability.hits}</td>
                <td class="px-4 py-2 text-right text-zinc-500">{ability.players}</td>
                <td class="px-4 py-2 text-center">
                  <%= if ability.ability_id && Map.has_key?(@criteria_by_spell, ability.ability_id) do %>
                    <button
                      phx-click="remove_criteria"
                      phx-value-spell-id={ability.ability_id}
                      class="text-xs text-red-400 hover:text-red-300"
                      title="Remove tracking"
                    >
                      ✕
                    </button>
                  <% else %>
                    <%= if ability.ability_id do %>
                      <button
                        phx-click="open_track_modal"
                        phx-value-spell-id={ability.ability_id}
                        phx-value-spell-name={ability.name}
                        class="text-xs text-wow-gold hover:text-yellow-400"
                        title="Track this ability"
                      >
                        + Track
                      </button>
                    <% else %>
                      <span class="text-xs text-zinc-600">-</span>
                    <% end %>
                  <% end %>
                </td>
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
  attr :criteria_by_spell, :map, required: true

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
    |> Enum.map(fn {name, %{total: total, hits: hits, ability_id: ability_id, players: players}} ->
      %{name: name, total: total, hits: hits, ability_id: ability_id, players: players}
    end)
  end

  defp sorted_players(stats) do
    stats.all
    |> Enum.sort_by(& &1.total, :desc)
    |> Enum.map(fn player ->
      %{
        name: player.player_name,
        total: player.total,
        is_tank: player.role == :tank
      }
    end)
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

  # Criteria helper functions

  defp get_criteria(criteria_by_spell, spell_id) when is_integer(spell_id) do
    case Map.get(criteria_by_spell, spell_id) do
      [criteria | _] -> criteria
      _ -> nil
    end
  end

  defp get_criteria(_, _), do: nil

  defp criteria_color(criteria_by_spell, spell_id) when is_integer(spell_id) do
    case get_criteria(criteria_by_spell, spell_id) do
      nil -> "text-zinc-200"
      criteria -> MechanicCriteria.type_color(criteria.mechanic_type)
    end
  end

  defp criteria_color(_, _), do: "text-zinc-200"

  # Failure helper functions

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
