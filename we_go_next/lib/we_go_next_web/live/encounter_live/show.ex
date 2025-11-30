defmodule WeGoNextWeb.EncounterLive.Show do
  @moduledoc """
  LiveView for displaying encounter detail with analysis tabs.

  This is the main view for the between-pull diagnostic dashboard.
  It loads encounter data, computes analysis (with caching), and
  renders tabs for different analysis perspectives.
  """
  use WeGoNextWeb, :live_view

  alias WeGoNext.{EncounterStore, Criteria, Accounts, Preferences}
  alias WeGoNext.Criteria.MechanicCriteria
  alias WeGoNext.Analyzers.{AnalysisCache, DebuffAnalyzer}

  # ============================================================================
  # Mount & Data Loading
  # ============================================================================

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    id = String.to_integer(id)
    user = Accounts.get_or_create_default_user()

    # First check if we have cached analysis - if so, skip expensive parsing
    case load_encounter_with_analysis(id) do
      {:ok, encounter, analysis} ->
        criteria_by_spell = Criteria.criteria_by_spell_id(encounter.id, encounter.difficulty_id)

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
  # Delegates to AnalysisCache.compute/1 which runs all analyzers and serializes
  defp compute_and_cache_analysis(encounter) do
    # Compute and serialize analysis (runs all analyzers)
    serialized = AnalysisCache.compute(encounter)

    # Save to database for future loads
    save_analysis_to_db(encounter.id, serialized)

    # Deserialize back to atom-keyed maps for UI consumption
    AnalysisCache.from_cache(serialized)
  end

  defp save_analysis_to_db(encounter_id, analysis_data) do
    import Ecto.Query

    from(e in WeGoNext.Encounters.Encounter, where: e.id == ^encounter_id)
    |> WeGoNext.Repo.update_all(set: [analysis: analysis_data])
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

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
        criteria_by_spell = Criteria.criteria_by_spell_id(encounter.id, encounter.difficulty_id)

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
    case Criteria.get_criteria_for_spell(spell_id, encounter.id, encounter.difficulty_id) do
      [criteria | _] ->
        Criteria.delete_criteria(criteria)
        criteria_by_spell = Criteria.criteria_by_spell_id(encounter.id, encounter.difficulty_id)

        {:noreply,
         socket
         |> assign(:criteria_by_spell, criteria_by_spell)
         |> put_flash(:info, "Criteria removed")}

      [] ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_player_debuffs", _, socket) do
    {:noreply, assign(socket, :show_player_debuffs, !socket.assigns.show_player_debuffs)}
  end

  @impl true
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

  @impl true
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

  # ============================================================================
  # Render
  # ============================================================================

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
        <SummaryTab.render :if={@active_tab == :summary} summary={@summary} player_classes={@player_classes} />
        <FailuresTab.render :if={@active_tab == :failures} stats={@failure_stats} player_classes={@player_classes} />
        <DeathsTab.render :if={@active_tab == :deaths} deaths={@deaths} player_classes={@player_classes} />
        <DamageTakenTab.render :if={@active_tab == :damage} stats={@damage_stats} encounter={@encounter} criteria_by_spell={@criteria_by_spell} player_classes={@player_classes} />
        <DamageDoneTab.render :if={@active_tab == :damage_done} stats={@damage_done} player_classes={@player_classes} />
        <InterruptsTab.render :if={@active_tab == :interrupts} stats={@interrupt_stats} criteria_by_spell={@criteria_by_spell} player_classes={@player_classes} />
        <DebuffsTab.render
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

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp total_interrupts(stats) do
    stats.by_player
    |> Map.values()
    |> Enum.map(& &1.total_interrupts)
    |> Enum.sum()
  end

  # Filter debuffs for tab count - delegates to shared logic
  defp filtered_debuffs(stats, hidden_spell_ids, force_shown_spell_ids, show_player_debuffs) do
    top_debuffs(stats)
    |> Enum.reject(fn debuff ->
      MapSet.member?(hidden_spell_ids, debuff.spell_id)
    end)
    |> Enum.filter(fn debuff ->
      cond do
        MapSet.member?(force_shown_spell_ids, debuff.spell_id) -> true
        show_player_debuffs -> true
        true -> DebuffAnalyzer.npc_source?(debuff.source_guid)
      end
    end)
  end

  defp top_debuffs(stats) do
    stats.by_spell
    |> Enum.map(fn {name, data} ->
      %{
        name: name,
        count: data.total_applications,
        players: data.players_affected,
        spell_id: data.spell_id,
        source_guid: Map.get(data, :source_guid),
        source_name: Map.get(data, :source_name, "Unknown")
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(25)
  end
end
