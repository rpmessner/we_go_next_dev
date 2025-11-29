defmodule WeGoNextWeb.EncounterLive.Show do
  use WeGoNextWeb, :live_view

  alias WeGoNext.{EncounterStore, Encounter, Criteria, Accounts, Preferences, WowClass}
  alias WeGoNext.Criteria.MechanicCriteria
  alias WeGoNext.Analyzers.{DeathAnalyzer, DamageTakenAnalyzer, DamageDoneAnalyzer, InterruptAnalyzer, DebuffAnalyzer, FailureAnalyzer, PullSummary, AnalysisCache, PlayerInfoAnalyzer}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    id = String.to_integer(id)
    user = Accounts.get_or_create_default_user()

    # First check if we have cached analysis - if so, skip expensive parsing
    case load_encounter_with_analysis(id) do
      {:ok, encounter, analysis} ->
        criteria_by_spell = Criteria.criteria_by_spell_id(encounter.id)

        {:ok,
         socket
         |> assign(:page_title, encounter.name)
         |> assign(:encounter_id, id)
         |> assign(:encounter, encounter)
         |> assign(:user, user)
         |> assign(:active_tab, :summary)
         |> assign(:show_player_debuffs, false)
         |> assign(:hidden_spell_ids, Preferences.hidden_spell_ids(encounter.id))
         |> assign(:force_shown_spell_ids, Preferences.force_shown_spell_ids(encounter.id))
         |> assign(:deaths, analysis.deaths)
         |> assign(:damage_stats, analysis.damage_stats)
         |> assign(:damage_done, analysis.damage_done)
         |> assign(:interrupt_stats, analysis.interrupt_stats)
         |> assign(:debuff_stats, analysis.debuff_stats)
         |> assign(:failure_stats, analysis.failure_stats)
         |> assign(:summary, analysis.summary)
         |> assign(:player_classes, analysis.player_classes || %{})
         |> assign(:criteria_by_spell, criteria_by_spell)
         |> assign(:show_criteria_modal, false)
         |> assign(:modal_spell_id, nil)
         |> assign(:modal_spell_name, nil)}

      :not_found ->
        {:ok,
         socket
         |> put_flash(:error, "Encounter not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  # Load encounter - use lightweight version if analysis is cached, full parse otherwise
  defp load_encounter_with_analysis(id) do
    case EncounterStore.get_encounter_record(id) do
      nil ->
        :not_found

      record ->
        cached_analysis = AnalysisCache.from_cache(record.analysis)

        if cached_analysis do
          # Analysis is cached - use lightweight encounter (no parsing!)
          encounter = EncounterStore.get_encounter_lightweight(id)
          {:ok, encounter, cached_analysis}
        else
          # No cached analysis - must parse and compute
          encounter = EncounterStore.get_encounter(id)
          analysis = compute_and_cache_analysis(encounter)
          {:ok, encounter, analysis}
        end
    end
  end

  # Compute analysis fresh and cache it for next time
  defp compute_and_cache_analysis(encounter) do
    deaths = DeathAnalyzer.analyze(encounter)
    damage_stats = DamageTakenAnalyzer.analyze(encounter)
    interrupt_stats = InterruptAnalyzer.analyze(encounter)
    debuff_stats = DebuffAnalyzer.analyze(encounter)
    failure_stats = FailureAnalyzer.analyze(encounter)

    # Extract player class information from COMBATANT_INFO events
    player_classes = PlayerInfoAnalyzer.player_classes_by_name(encounter)

    # Get tank GUIDs from damage taken analysis for role detection
    tank_guids = damage_stats.tanks
      |> Enum.map(& &1.player_guid)
      |> MapSet.new()

    # Analyze damage done (need tank_guids for role detection)
    damage_done_raw = DamageDoneAnalyzer.analyze(encounter, tank_guids: tank_guids)
    damage_done_annotated = DamageDoneAnalyzer.annotate_with_deaths(damage_done_raw, deaths)
    underperformers = DamageDoneAnalyzer.identify_underperformers(damage_done_raw, deaths)
    damage_done = Map.put(damage_done_annotated, :underperformers, underperformers)

    summary = PullSummary.summarize(encounter,
      deaths: deaths,
      damage_stats: damage_stats,
      damage_done: damage_done,
      interrupt_stats: interrupt_stats,
      debuff_stats: debuff_stats,
      failure_stats: failure_stats
    )

    # Save to database for future loads
    save_analysis_to_db(encounter.id, deaths, damage_stats, damage_done, interrupt_stats, debuff_stats, failure_stats, summary, player_classes)

    %{
      deaths: deaths,
      damage_stats: damage_stats,
      damage_done: damage_done,
      interrupt_stats: interrupt_stats,
      debuff_stats: debuff_stats,
      failure_stats: failure_stats,
      summary: summary,
      player_classes: player_classes
    }
  end

  defp save_analysis_to_db(encounter_id, deaths, damage_stats, damage_done, interrupt_stats, debuff_stats, failure_stats, summary, player_classes) do
    # Use AnalysisCache.serialize to convert to storable format
    analysis_data = AnalysisCache.serialize(%{
      deaths: deaths,
      damage_stats: damage_stats,
      damage_done: damage_done,
      interrupt_stats: interrupt_stats,
      debuff_stats: debuff_stats,
      failure_stats: failure_stats,
      summary: summary,
      player_classes: player_classes
    })

    # Update the encounter record in DB
    import Ecto.Query
    from(e in WeGoNext.Encounters.Encounter, where: e.id == ^encounter_id)
    |> WeGoNext.Repo.update_all(set: [analysis: analysis_data])
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

  def handle_event("toggle_player_debuffs", _, socket) do
    {:noreply, assign(socket, :show_player_debuffs, !socket.assigns.show_player_debuffs)}
  end

  def handle_event("toggle_spell_visibility", %{"spell-id" => spell_id_str, "spell-name" => spell_name}, socket) do
    spell_id = String.to_integer(spell_id_str)
    encounter = socket.assigns.encounter

    case Preferences.toggle_spell_visibility(encounter.id, spell_id, spell_name) do
      {:ok, _pref} ->
        hidden_spell_ids = Preferences.hidden_spell_ids(encounter.id)
        {:noreply, assign(socket, :hidden_spell_ids, hidden_spell_ids)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update spell visibility")}
    end
  end

  def handle_event("toggle_force_show", %{"spell-id" => spell_id_str, "spell-name" => spell_name}, socket) do
    spell_id = String.to_integer(spell_id_str)
    encounter = socket.assigns.encounter

    case Preferences.toggle_force_show(encounter.id, spell_id, spell_name) do
      {:ok, _pref} ->
        force_shown_spell_ids = Preferences.force_shown_spell_ids(encounter.id)
        {:noreply, assign(socket, :force_shown_spell_ids, force_shown_spell_ids)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update spell pin status")}
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
          <.tab_button tab={:summary} active={@active_tab} count={nil} highlight={false}>
            Summary
          </.tab_button>
          <.tab_button tab={:failures} active={@active_tab} count={@failure_stats.summary.total_failures} highlight={@failure_stats.summary.total_failures > 0}>
            Failures
          </.tab_button>
          <.tab_button tab={:deaths} active={@active_tab} count={length(@deaths)}>
            Deaths
          </.tab_button>
          <.tab_button tab={:damage} active={@active_tab} count={nil}>
            Damage Taken
          </.tab_button>
          <.tab_button tab={:damage_done} active={@active_tab} count={nil}>
            Damage Done
          </.tab_button>
          <.tab_button tab={:interrupts} active={@active_tab} count={total_interrupts(@interrupt_stats)}>
            Interrupts
          </.tab_button>
          <.tab_button tab={:debuffs} active={@active_tab} count={length(filtered_debuffs(@debuff_stats, @hidden_spell_ids, @force_shown_spell_ids, @show_player_debuffs))}>
            Debuffs
          </.tab_button>
        </nav>
      </div>

      <%!-- Tab content --%>
      <div class="min-h-[400px]">
        <.summary_tab :if={@active_tab == :summary} summary={@summary} player_classes={@player_classes} />
        <.failures_tab :if={@active_tab == :failures} stats={@failure_stats} player_classes={@player_classes} />
        <.deaths_tab :if={@active_tab == :deaths} deaths={@deaths} player_classes={@player_classes} />
        <.damage_tab :if={@active_tab == :damage} stats={@damage_stats} encounter={@encounter} criteria_by_spell={@criteria_by_spell} />
        <.damage_done_tab :if={@active_tab == :damage_done} stats={@damage_done} player_classes={@player_classes} />
        <.interrupts_tab :if={@active_tab == :interrupts} stats={@interrupt_stats} criteria_by_spell={@criteria_by_spell} player_classes={@player_classes} />
        <.debuffs_tab
          :if={@active_tab == :debuffs}
          stats={@debuff_stats}
          show_player_debuffs={@show_player_debuffs}
          hidden_spell_ids={@hidden_spell_ids}
          force_shown_spell_ids={@force_shown_spell_ids}
          is_admin={@user.is_admin}
          player_classes={@player_classes}
        />
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

  # Summary tab - pull summary for between-pull analysis
  attr :summary, :any, required: true
  attr :player_classes, :map, required: true

  defp summary_tab(assigns) do
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
      <div :if={@summary.deaths_summary.total > 0}>
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

      <%!-- Critical failures --%>
      <div :if={@summary.critical_failures != []}>
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

      <%!-- No failures message --%>
      <div :if={@summary.critical_failures == [] && @summary.result == :wipe} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <p class="text-zinc-400">
          No tracked mechanic failures detected. Consider tracking mechanics from the Damage Taken tab.
        </p>
      </div>

      <%!-- Missed interrupts --%>
      <div :if={@summary.missed_interrupts != []}>
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
              <tr :for={missed <- @summary.missed_interrupts} class="hover:bg-zinc-750">
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

      <%!-- Players needing coaching --%>
      <div :if={@summary.problem_players != []}>
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
              <tr :for={player <- @summary.problem_players} class="hover:bg-zinc-750">
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

      <%!-- Recommendations --%>
      <div :if={@summary.recommendations != []}>
        <h3 class="text-sm font-medium text-green-400 mb-3">Next Pull Focus</h3>
        <div class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
          <ol class="space-y-2">
            <li :for={{rec, idx} <- Enum.with_index(@summary.recommendations, 1)} class="flex gap-3">
              <span class="text-zinc-500 font-mono">{idx}.</span>
              <span class="text-zinc-200">{rec}</span>
            </li>
          </ol>
        </div>
      </div>

      <%!-- No recommendations message --%>
      <div :if={@summary.recommendations == [] && @summary.result == :wipe} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <h3 class="text-green-400 font-medium mb-2">Next Pull Focus</h3>
        <p class="text-zinc-400">No specific issues detected. Keep up the good work!</p>
      </div>
    </div>
    """
  end

  defp mechanic_type_color("avoidable"), do: "text-red-400"
  defp mechanic_type_color("interrupt"), do: "text-yellow-400"
  defp mechanic_type_color("soak"), do: "text-blue-400"
  defp mechanic_type_color("spread"), do: "text-purple-400"
  defp mechanic_type_color(_), do: "text-zinc-200"

  defp severity_badge_color(:critical), do: "bg-red-900 text-red-300"
  defp severity_badge_color(:high), do: "bg-orange-900 text-orange-300"
  defp severity_badge_color(:medium), do: "bg-yellow-900 text-yellow-300"
  defp severity_badge_color(:low), do: "bg-zinc-700 text-zinc-300"
  defp severity_badge_color(_), do: "bg-zinc-700 text-zinc-300"

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
  attr :player_classes, :map, required: true

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
      </div>
    </div>
    """
  end

  # Deaths tab
  attr :deaths, :list, required: true
  attr :player_classes, :map, required: true

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
            <span class="font-semibold">
              <.player_name name={death.player_name} player_classes={@player_classes} />
            </span>
          </div>
          <span :if={death.killing_blow} class="text-sm text-zinc-400">
            <.wowhead_link spell_id={death.killing_blow[:ability_id]} name={death.killing_blow.ability} />
            ({format_number(death.killing_blow.amount)})
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
              <span class="text-zinc-400">
                <.wowhead_link spell_id={event.ability_id} name={event.ability_name} />
              </span>
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
                    <.wowhead_link spell_id={ability.ability_id} name={ability.name} />
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

  # Damage done tab - simple DPS breakdown with underperformer detection
  attr :stats, :map, required: true
  attr :player_classes, :map, required: true

  defp damage_done_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Underperformers alert --%>
      <div :if={@stats.underperformers != []} class="bg-yellow-900/30 border border-yellow-800 rounded-lg p-4">
        <h3 class="text-yellow-400 font-medium mb-2">Low DPS (Not Due to Death)</h3>
        <p class="text-zinc-400 text-sm mb-3">
          These players have significantly lower DPS than the group median and didn't die.
        </p>
        <div class="space-y-2">
          <div :for={u <- @stats.underperformers} class="flex items-center gap-4 text-sm">
            <span class="font-medium">
              <.player_name name={u.player_name} player_classes={@player_classes} />
            </span>
            <span class="text-zinc-500">
              {format_dps(u.dps)} DPS
              <span class="text-yellow-500">({Float.round(u.percent_of_median, 0)}% of median)</span>
            </span>
          </div>
        </div>
      </div>

      <%!-- DPS/Healers section --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">DPS/Healers</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Player</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">DPS</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Total</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={player <- @stats.dps_healers} class={["hover:bg-zinc-750", Map.get(player, :death_time) && "opacity-60"]}>
                <td class="px-4 py-2">
                  <.player_name name={player.player_name} player_classes={@player_classes} />
                </td>
                <td class="px-4 py-2 text-right text-wow-gold font-medium">{format_dps(player.dps)}</td>
                <td class="px-4 py-2 text-right text-zinc-400">{format_damage_total(player.total)}</td>
                <td class="px-4 py-2 text-right">
                  <%= if Map.get(player, :death_time) do %>
                    <span class="text-red-400 text-sm">Died at {format_seconds(Map.get(player, :death_time))}</span>
                  <% else %>
                    <span class="text-green-400 text-sm">Survived</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Tanks section --%>
      <div :if={@stats.tanks != []}>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Tanks</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Player</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">DPS</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Total</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={player <- @stats.tanks} class={["hover:bg-zinc-750", Map.get(player, :death_time) && "opacity-60"]}>
                <td class="px-4 py-2">
                  <.player_name name={player.player_name} player_classes={@player_classes} />
                </td>
                <td class="px-4 py-2 text-right text-wow-gold font-medium">{format_dps(player.dps)}</td>
                <td class="px-4 py-2 text-right text-zinc-400">{format_damage_total(player.total)}</td>
                <td class="px-4 py-2 text-right">
                  <%= if Map.get(player, :death_time) do %>
                    <span class="text-red-400 text-sm">Died at {format_seconds(Map.get(player, :death_time))}</span>
                  <% else %>
                    <span class="text-green-400 text-sm">Survived</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Fight info --%>
      <div class="text-xs text-zinc-500">
        Fight duration: {format_seconds(@stats.fight_duration)}
      </div>
    </div>
    """
  end

  # Interrupts tab
  attr :stats, :map, required: true
  attr :criteria_by_spell, :map, required: true
  attr :player_classes, :map, required: true

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
              <tr :for={{_guid, data} <- sorted_interrupters(@stats)} class="hover:bg-zinc-750">
                <td class="px-4 py-2">
                  <.player_name name={data.player_name} player_classes={@player_classes} />
                </td>
                <td class="px-4 py-2 text-right text-green-400 font-medium">{data.total_interrupts}</td>
                <td class="px-4 py-2 text-zinc-400 text-sm">
                  {data.by_spell |> Map.keys() |> Enum.join(", ")}
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
                <td class="px-4 py-2 text-red-400">
                  <.wowhead_link spell_id={cast.spell_id} name={cast.spell_name} />
                </td>
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
  attr :show_player_debuffs, :boolean, required: true
  attr :hidden_spell_ids, :any, required: true
  attr :force_shown_spell_ids, :any, required: true
  attr :is_admin, :boolean, required: true
  attr :player_classes, :map, required: true

  defp debuffs_tab(assigns) do
    # Use shared helper for filtering
    debuffs = filtered_debuffs(assigns.stats, assigns.hidden_spell_ids, assigns.force_shown_spell_ids, assigns.show_player_debuffs)
    assigns = assign(assigns, :filtered_debuffs, debuffs)

    ~H"""
    <div class="space-y-6" id="debuffs-tab" phx-hook="WowheadTooltips">
      <%!-- Filters panel --%>
      <div class="bg-zinc-800 rounded-lg p-4">
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-medium text-zinc-300">Filters</h3>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              checked={@show_player_debuffs}
              phx-click="toggle_player_debuffs"
              class="rounded border-zinc-600 bg-zinc-700 text-blue-500 focus:ring-blue-500 focus:ring-offset-zinc-800"
            />
            <span class="text-sm text-zinc-400">Show player-applied debuffs</span>
          </label>
        </div>
      </div>

      <%!-- Top debuffs by application count --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Boss Mechanics (Debuffs)</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Debuff</th>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Source</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Applications</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Players Hit</th>
                <th :if={@is_admin} class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr
                :for={debuff <- @filtered_debuffs}
                class="hover:bg-zinc-750"
              >
                <td class="px-4 py-2">
                  <span :if={MapSet.member?(@force_shown_spell_ids, debuff.spell_id)} class="text-blue-400 mr-1" title="Pinned - always shown">
                    📌
                  </span>
                  <a
                    href={"https://www.wowhead.com/spell=#{debuff.spell_id}"}
                    target="_blank"
                    rel="noopener"
                  >
                    {debuff.name}
                  </a>
                </td>
                <td class="px-4 py-2 text-zinc-500 text-sm">{debuff.source_name}</td>
                <td class="px-4 py-2 text-right text-zinc-400">{debuff.count}</td>
                <td class="px-4 py-2 text-right text-zinc-500">{debuff.players}</td>
                <td :if={@is_admin} class="px-4 py-2 text-right space-x-2">
                  <%!-- Pin button - only show for non-NPC sourced debuffs that need pinning --%>
                  <button
                    :if={not DebuffAnalyzer.npc_source?(debuff.source_guid)}
                    phx-click="toggle_force_show"
                    phx-value-spell-id={debuff.spell_id}
                    phx-value-spell-name={debuff.name}
                    class={[
                      "text-xs",
                      if(MapSet.member?(@force_shown_spell_ids, debuff.spell_id),
                        do: "text-blue-400 hover:text-blue-300",
                        else: "text-zinc-500 hover:text-blue-400")
                    ]}
                    title={if MapSet.member?(@force_shown_spell_ids, debuff.spell_id), do: "Unpin this debuff", else: "Pin this debuff (always show)"}
                  >
                    {if MapSet.member?(@force_shown_spell_ids, debuff.spell_id), do: "Unpin", else: "Pin"}
                  </button>
                  <button
                    phx-click="toggle_spell_visibility"
                    phx-value-spell-id={debuff.spell_id}
                    phx-value-spell-name={debuff.name}
                    class="text-xs text-zinc-500 hover:text-red-400"
                    title="Hide this debuff"
                  >
                    Hide
                  </button>
                </td>
              </tr>
              <tr :if={@filtered_debuffs == []} class="hover:bg-zinc-750">
                <td colspan={if @is_admin, do: 5, else: 4} class="px-4 py-4 text-center text-zinc-500">
                  No debuffs to display. Try enabling "Show player-applied debuffs" above.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Pinned debuffs (admin only) --%>
      <div :if={@is_admin && MapSet.size(@force_shown_spell_ids) > 0}>
        <h3 class="text-sm font-medium text-blue-400 mb-3">📌 Pinned Debuffs ({MapSet.size(@force_shown_spell_ids)})</h3>
        <p class="text-xs text-zinc-500 mb-2">These debuffs are always shown, even when "Show player-applied debuffs" is off.</p>
        <div class="bg-zinc-800/50 rounded-lg p-3">
          <div class="flex flex-wrap gap-2">
            <%= for debuff <- pinned_debuffs(@stats, @force_shown_spell_ids) do %>
              <button
                phx-click="toggle_force_show"
                phx-value-spell-id={debuff.spell_id}
                phx-value-spell-name={debuff.name}
                class="inline-flex items-center gap-1 px-2 py-1 bg-blue-900/30 border border-blue-800 rounded text-xs text-blue-300 hover:bg-blue-800/30"
              >
                {debuff.name}
                <span class="text-zinc-500">×</span>
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Hidden debuffs (admin only) --%>
      <div :if={@is_admin && MapSet.size(@hidden_spell_ids) > 0}>
        <h3 class="text-sm font-medium text-zinc-500 mb-3">Hidden Debuffs ({MapSet.size(@hidden_spell_ids)})</h3>
        <div class="bg-zinc-800/50 rounded-lg p-3">
          <div class="flex flex-wrap gap-2">
            <%= for debuff <- hidden_debuffs(@stats, @hidden_spell_ids) do %>
              <button
                phx-click="toggle_spell_visibility"
                phx-value-spell-id={debuff.spell_id}
                phx-value-spell-name={debuff.name}
                class="inline-flex items-center gap-1 px-2 py-1 bg-zinc-700 rounded text-xs text-zinc-400 hover:bg-zinc-600"
              >
                {debuff.name}
                <span class="text-green-400">+</span>
              </button>
            <% end %>
          </div>
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
              <tr :for={{name, data} <- players_by_debuffs(@stats, @hidden_spell_ids, @show_player_debuffs)} class="hover:bg-zinc-750">
                <td class="px-4 py-2">
                  <.player_name name={name} player_classes={@player_classes} />
                </td>
                <td class="px-4 py-2 text-right text-zinc-400">{data.count}</td>
                <td class="px-4 py-2 text-zinc-500 text-sm">
                  {data.spells |> Enum.take(3) |> Enum.join(", ")}
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

  # Wowhead spell link component
  attr :spell_id, :integer, required: true
  attr :name, :string, required: true
  attr :class, :string, default: nil

  defp wowhead_link(assigns) do
    ~H"""
    <a
      :if={@spell_id}
      href={"https://www.wowhead.com/spell=#{@spell_id}"}
      target="_blank"
      rel="noopener noreferrer"
      class={[@class || "text-inherit hover:text-blue-400 hover:underline"]}
      title={"View #{@name} on Wowhead"}
    >
      {@name}
    </a>
    <span :if={!@spell_id}>{@name}</span>
    """
  end

  # Player name component with class coloring
  attr :name, :string, required: true
  attr :player_classes, :map, required: true
  attr :class, :string, default: nil

  defp player_name(assigns) do
    # Strip realm suffix for lookup (player_classes uses short names like "Zeddigos",
    # but other analyzers use full names like "Zeddigos-WyrmrestAccord-US")
    short_name = assigns.name |> String.split("-") |> List.first()
    class_id = Map.get(assigns.player_classes, short_name)
    color = if class_id, do: WowClass.class_color(class_id), else: nil

    assigns = assign(assigns, :color, color)

    ~H"""
    <span style={@color && "color: #{@color}"} class={@class}>
      {@name}
    </span>
    """
  end

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

  defp format_dps(dps) when is_float(dps) do
    cond do
      dps >= 1_000_000 -> "#{Float.round(dps / 1_000_000, 1)}M"
      dps >= 1000 -> "#{Float.round(dps / 1000, 1)}k"
      true -> "#{Float.round(dps, 0) |> trunc()}"
    end
  end
  defp format_dps(dps) when is_integer(dps), do: format_dps(dps / 1)
  defp format_dps(_), do: "0"

  defp format_damage_total(num) when is_integer(num) and num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end
  defp format_damage_total(num) when is_integer(num) and num >= 1000 do
    "#{Float.round(num / 1000, 0) |> trunc()}k"
  end
  defp format_damage_total(num) when is_number(num), do: to_string(trunc(num))
  defp format_damage_total(_), do: "0"

  defp format_seconds(seconds) when is_number(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end
  defp format_seconds(_), do: "0:00"

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
      %{
        name: name,
        count: data.total_applications,
        players: data.players_affected,
        spell_id: data.spell_id,
        # Handle cached data that might not have source_guid/source_name
        source_guid: Map.get(data, :source_guid),
        source_name: Map.get(data, :source_name, "Unknown")
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(25)
  end

  # Filter debuffs based on hidden spells, force-shown spells, and show_player_debuffs toggle
  defp filtered_debuffs(stats, hidden_spell_ids, force_shown_spell_ids, show_player_debuffs) do
    top_debuffs(stats)
    |> Enum.reject(fn debuff ->
      MapSet.member?(hidden_spell_ids, debuff.spell_id)
    end)
    |> Enum.filter(fn debuff ->
      cond do
        # Force-shown debuffs always appear (overrides player-applied classification)
        MapSet.member?(force_shown_spell_ids, debuff.spell_id) -> true
        # When toggle is on, show all non-hidden debuffs
        show_player_debuffs -> true
        # Otherwise only show NPC-sourced debuffs
        true -> DebuffAnalyzer.npc_source?(debuff.source_guid)
      end
    end)
  end

  defp hidden_debuffs(stats, hidden_spell_ids) do
    stats.by_spell
    |> Enum.filter(fn {_name, data} ->
      MapSet.member?(hidden_spell_ids, data.spell_id)
    end)
    |> Enum.map(fn {name, data} ->
      %{name: name, spell_id: data.spell_id}
    end)
  end

  defp pinned_debuffs(stats, force_shown_spell_ids) do
    stats.by_spell
    |> Enum.filter(fn {_name, data} ->
      MapSet.member?(force_shown_spell_ids, data.spell_id)
    end)
    |> Enum.map(fn {name, data} ->
      %{name: name, spell_id: data.spell_id}
    end)
  end

  defp players_by_debuffs(stats, hidden_spell_ids, show_player_debuffs) do
    # Build a lookup from spell_name to spell metadata for filtering
    spell_lookup =
      stats.by_spell
      |> Enum.map(fn {name, data} ->
        {name, %{spell_id: Map.get(data, :spell_id), source_guid: Map.get(data, :source_guid)}}
      end)
      |> Map.new()

    stats.by_player
    |> Enum.map(fn {name, data} ->
      # Get the player's spells - handle both struct (by_spell) and cached map (spells) formats
      player_spells = get_player_spells(data)

      # Filter spells for this player using the same logic as the main list
      filtered_spells = Enum.filter(player_spells, fn spell_name ->
        case Map.get(spell_lookup, spell_name) do
          nil -> false
          %{spell_id: spell_id, source_guid: source_guid} ->
            not MapSet.member?(hidden_spell_ids, spell_id) and
              (show_player_debuffs or DebuffAnalyzer.npc_source?(source_guid))
        end
      end)
      player_name = Map.get(data, :player_name) || name
      {player_name, %{spells: filtered_spells, count: length(filtered_spells)}}
    end)
    |> Enum.reject(fn {_, data} -> data.spells == [] end)
    |> Enum.sort_by(fn {_, data} -> data.count end, :desc)
    |> Enum.take(10)
  end

  # Get player spells from either fresh analysis (by_spell map) or cached data (spells list)
  defp get_player_spells(data) do
    cond do
      # Fresh analysis - PlayerStats struct with by_spell map
      Map.has_key?(data, :by_spell) -> Map.keys(data.by_spell)
      # Cached data - map with spells list
      Map.has_key?(data, :spells) -> data.spells
      true -> []
    end
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
