defmodule WeGoNextWeb.EncounterLive.Show do
  @moduledoc """
  Encounter detail shell keyed by imported pull id.

  This route intentionally reads only imported observation and tracked failure
  read models. It must not call legacy analyzers, analyzer cache output, or
  `public.mechanic_criteria`.
  """

  use WeGoNextWeb, :live_view

  alias WeGoNext.Accounts
  alias WeGoNext.Gold.{EncounterDetail, ObservedMechanics}
  alias WeGoNext.WowClass

  import WeGoNextWeb.EncounterComponents,
    only: [format_duration: 1, format_number: 1, wowhead_link: 1]

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    user = Accounts.get_or_create_default_user()
    active_tab = parse_tab(Map.get(params, "tab"))

    case EncounterDetail.get(id, character_name: user.character_name) do
      {:ok, detail} ->
        {:ok, observed_mechanics} = ObservedMechanics.for_encounter(detail.encounter.id)

        {:ok,
         socket
         |> assign(:page_title, detail.encounter.name)
         |> assign(:user, user)
         |> assign(:detail, detail)
         |> assign(:encounter, detail.encounter)
         |> assign(:counts, detail.counts)
         |> assign(:roster, detail.roster)
         |> assign(:deaths, detail.deaths)
         |> assign(:failure_preview, detail.failure_preview)
         |> assign(:interrupt_coverage, detail.interrupt_coverage)
         |> assign(:observed_mechanics, observed_mechanics)
         |> assign_personal_summary(detail.personal_pull_summary)
         |> assign(:active_tab, active_tab)}

      {:error, reason} ->
        {:ok,
         socket
         |> assign(:page_title, "Encounter Not Found")
         |> assign(:user, user)
         |> assign(:detail, nil)
         |> assign(:encounter, nil)
         |> assign(:counts, %{})
         |> assign(:roster, [])
         |> assign(:deaths, [])
         |> assign(:failure_preview, %{mechanics: [], diagnostics: [], counts: %{failures: 0}})
         |> assign(:interrupt_coverage, %{spell_coverage: [], player_contributions: []})
         |> assign(:observed_mechanics, %{mechanics: [], counts: %{observed_spells: 0}})
         |> assign_personal_summary(%{selected_player_guid: nil, players: []})
         |> assign(:active_tab, active_tab)
         |> assign(:error, not_found_message(reason))}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, parse_tab(tab))}
  end

  @impl true
  def handle_event("select_personal_player", params, socket) do
    player_guid = get_in(params, ["personal", "player_guid"]) || Map.get(params, "player_guid")

    {:noreply,
     socket
     |> assign(:selected_personal_player_guid, player_guid)
     |> assign(
       :selected_personal_player,
       selected_personal_player(socket.assigns.personal_pull_summary.players, player_guid)
     )}
  end

  @impl true
  def render(%{encounter: nil} = assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <.back navigate={~p"/"}>Back to encounters</.back>
        <.link navigate={~p"/failures"} class="text-sm text-zinc-400 hover:text-zinc-200">
          View failures
        </.link>
      </div>

      <section class="rounded-lg border border-zinc-700 bg-zinc-800 p-6">
        <h1 class="text-2xl font-bold text-wow-gold">Encounter Not Found</h1>
        <p class="mt-2 text-sm text-zinc-400">{@error}</p>
      </section>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <.back navigate={~p"/"}>Back to encounters</.back>
          <h1 class="mt-3 text-2xl font-bold text-wow-gold">{@encounter.name}</h1>
          <p class="mt-1 text-sm text-zinc-400">
            Encounter detail for imported pull #{@encounter.id}.
          </p>
        </div>

        <.link navigate={~p"/failures"} class="text-sm text-zinc-400 hover:text-zinc-200">
          View failures
        </.link>
      </div>

      <nav class="border-b border-zinc-700">
        <div class="flex gap-5 overflow-x-auto">
          <.tab_button tab={:overview} active={@active_tab}>Overview</.tab_button>
          <.tab_button tab={:mechanics} active={@active_tab} count={@observed_mechanics.counts.observed_spells}>
            Mechanics
          </.tab_button>
          <.tab_button tab={:failures} active={@active_tab} count={@failure_preview.counts.failures}>
            Failure Preview
          </.tab_button>
          <.tab_button tab={:deaths} active={@active_tab} count={@counts.deaths}>Death Recap</.tab_button>
          <.tab_button tab={:interrupts} active={@active_tab} count={@counts.interrupt_opportunities}>
            Interrupt Coverage
          </.tab_button>
          <.tab_button tab={:personal} active={@active_tab}>Personal Pulls</.tab_button>
        </div>
      </nav>

      <div :if={@active_tab == :overview} class="space-y-6">
        <section class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
          <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <.metadata_item label="Difficulty" value={@encounter.difficulty_name || "Unknown"} />
            <.metadata_item label="Result" value={if @encounter.success, do: "Kill", else: "Wipe"} />
            <.metadata_item label="Duration" value={format_duration(@encounter)} />
            <.metadata_item label="Group Size" value={format_value(@encounter.group_size)} />
            <.metadata_item label="WoW Encounter ID" value={@encounter.wow_encounter_id} />
            <.metadata_item label="Instance ID" value={format_value(@encounter.instance_id)} />
            <.metadata_item label="Started" value={format_datetime(@encounter.start_time)} />
            <.metadata_item label="Pull ID" value={to_string(@encounter.id)} />
          </div>
        </section>

        <section class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Imported Data</h2>
          <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <.count_item label="Players" value={@counts.players} />
            <.count_item label="Damage Groups" value={@counts.damage_taken_groups} />
            <.count_item label="Damage Hits" value={@counts.damage_taken_events} />
            <.count_item label="Damage Done Groups" value={@counts.damage_done_groups} />
            <.count_item label="Deaths" value={@counts.deaths} />
            <.count_item label="Interrupt Opportunities" value={@counts.interrupt_opportunities} />
            <.count_item label="Debuffs" value={@counts.debuff_applications} />
            <.count_item label="Defensive Windows" value={@counts.defensive_buff_windows} />
            <.count_item label="Tracked Failures" value={@counts.failure_facts} />
          </div>
        </section>

        <section class="rounded-lg border border-zinc-700 bg-zinc-800">
          <div class="border-b border-zinc-700 px-4 py-3">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Roster</h2>
          </div>

          <div :if={@roster == []} class="px-4 py-6 text-sm text-zinc-400">
            No player roster data exists for this pull yet.
          </div>

          <div :if={@roster != []} class="overflow-x-auto">
            <table class="w-full">
              <thead>
                <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
                  <th class="px-4 py-2">Player</th>
                  <th class="px-4 py-2">Role</th>
                  <th class="px-4 py-2">Class</th>
                  <th class="px-4 py-2">Spec</th>
                  <th class="px-4 py-2 text-right">Item Level</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={player <- @roster} class="border-b border-zinc-700/60 last:border-0">
                  <td class="px-4 py-3">
                    <div class="font-medium" style={player_class_style(player.class_id)}>
                      {player.player_name}
                    </div>
                    <div class="text-xs font-mono text-zinc-500">{player.player_guid}</div>
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-300">
                    {format_role(player.detected_role, player.spec_id)}
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-300">{format_class(player.class_id)}</td>
                  <td class="px-4 py-3 text-sm text-zinc-300">{format_spec(player.spec_id)}</td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {format_value(player.item_level)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <section :if={@active_tab == :mechanics} class="space-y-6">
        <div class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">
            Observed Mechanics
          </h2>
          <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <.count_item label="Seen In Log" value={@observed_mechanics.counts.observed_spells || 0} />
            <.count_item label="With Failures" value={@observed_mechanics.counts.producing_failures || 0} />
            <.count_item label="Tracked" value={@observed_mechanics.counts.active_criteria || 0} />
            <.count_item label="Code Defined" value={@observed_mechanics.counts.code_defined || 0} />
          </div>
        </div>

        <div class="rounded-lg border border-zinc-700 bg-zinc-800">
          <div class="border-b border-zinc-700 px-4 py-3">
            <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">
              Encounter Spells
            </h3>
          </div>

          <div :if={@observed_mechanics.mechanics == []} class="px-4 py-6 text-sm text-zinc-400">
            No observed mechanics exist for this pull yet.
          </div>

          <div :if={@observed_mechanics.mechanics != []} class="overflow-x-auto">
            <table class="w-full">
              <thead>
                <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
                  <th class="px-4 py-2">Spell</th>
                  <th class="px-4 py-2">Tracking</th>
                  <th class="px-4 py-2 text-right">Damage</th>
                  <th class="px-4 py-2 text-right">Hits</th>
                  <th class="px-4 py-2 text-right">Players</th>
                  <th class="px-4 py-2">Seen</th>
                  <th class="px-4 py-2">Notes</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={mechanic <- @observed_mechanics.mechanics} class="border-b border-zinc-700/60 last:border-0">
                  <td class="px-4 py-3">
                    <div class="font-medium text-zinc-100">
                      <.wowhead_link spell_id={mechanic.spell_id} name={mechanic.spell_name} />
                    </div>
                    <div class="text-xs text-zinc-500">
                      Spell {mechanic.spell_id}
                      <span :if={mechanic.catalog}>&bull; {mechanic.catalog.boss_name}</span>
                    </div>
                    <div :if={mechanic.catalog} class="mt-1 text-xs text-zinc-400">
                      {format_mechanic_type(mechanic.catalog.mechanic_type)}
                      <span class="text-zinc-600">&bull;</span>
                      {format_mechanic_type(mechanic.catalog.event)}
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <span class={mechanic_status_class(mechanic.rule_status)}>
                      {mechanic_status_label(mechanic.rule_status)}
                    </span>
                    <div :if={mechanic.criteria != []} class="mt-1 text-xs text-zinc-500">
                      {length(mechanic.criteria)} definition{plural(length(mechanic.criteria))}
                    </div>
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {format_number(mechanic.observed.total_damage)}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {mechanic_event_count(mechanic)}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {mechanic_player_count(mechanic)}
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-300">
                    <div>{format_observed_channels(mechanic)}</div>
                    <div :if={mechanic.facts.failure_count > 0} class="mt-1 text-xs text-red-300">
                      {mechanic.facts.failure_count} failure{plural(mechanic.facts.failure_count)}
                      <span :if={mechanic.facts.failed_player_count > 0}>
                        across {mechanic.facts.failed_player_count} player{plural(mechanic.facts.failed_player_count)}
                      </span>
                    </div>
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-400">
                    <div :if={mechanic.diagnostics == []}>No action needed</div>
                    <ul :if={mechanic.diagnostics != []} class="space-y-1">
                      <li :for={diagnostic <- mechanic.diagnostics}>{diagnostic}</li>
                    </ul>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <section :if={@active_tab == :failures} class="space-y-6">
        <div class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">
            Failure Preview
          </h2>
          <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <.count_item label="Mechanics" value={@failure_preview.counts.mechanics || 0} />
            <.count_item label="Players" value={@failure_preview.counts.players || 0} />
            <.count_item label="Failures" value={@failure_preview.counts.failures || 0} />
            <.count_item label="Damage" value={@failure_preview.counts.damage || 0} />
          </div>
        </div>

        <div :if={@failure_preview.diagnostics != []} class="space-y-2">
          <div
            :for={diagnostic <- @failure_preview.diagnostics}
            class={failure_preview_diagnostic_class(diagnostic.severity)}
          >
            <div class="font-medium text-zinc-100">{diagnostic.title}</div>
            <p class="mt-1 text-sm text-zinc-300">{diagnostic.body}</p>
          </div>
        </div>

        <div :if={@failure_preview.mechanics == [] and @failure_preview.diagnostics == []} class="rounded-lg border border-zinc-700 bg-zinc-800 px-4 py-6 text-sm text-zinc-400">
          No tracked failures exist for this pull.
        </div>

        <section
          :for={mechanic <- @failure_preview.mechanics}
          class="rounded-lg border border-zinc-700 bg-zinc-800"
        >
          <div class="flex flex-col gap-2 border-b border-zinc-700 px-4 py-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h3 class="font-semibold text-zinc-100">
                <.wowhead_link spell_id={mechanic.spell_id} name={mechanic.spell_name} />
              </h3>
              <p class="mt-1 text-xs text-zinc-500">
                Spell {mechanic.spell_id}
                <span :if={mechanic.boss_name}> &bull; {mechanic.boss_name}</span>
                <span> &bull; {format_mechanic_type(mechanic.mechanic_type)}</span>
              </p>
            </div>
            <div class="text-sm text-zinc-400 sm:text-right">
              <span class="font-semibold text-zinc-100">{mechanic.failure_count}</span>
              failure{plural(mechanic.failure_count)}
              <span class="text-zinc-600">&bull;</span>
              {format_number(mechanic.total_damage)} damage
            </div>
          </div>

          <div class="overflow-x-auto">
            <table class="w-full">
              <thead>
                <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
                  <th class="px-4 py-2">Player</th>
                  <th class="px-4 py-2">Role</th>
                  <th class="px-4 py-2 text-right">Failures</th>
                  <th class="px-4 py-2 text-right">Damage</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={player <- mechanic.players} class="border-b border-zinc-700/60 last:border-0">
                  <td class="px-4 py-3">
                    <div class="font-medium" style={player_class_style(player.class_id)}>
                      {player.player_name || player.player_guid}
                    </div>
                    <div class="text-xs font-mono text-zinc-500">{player.player_guid}</div>
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-300">
                    {format_role(player.detected_role, player.spec_id)}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {player.failure_count}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {format_number(player.total_damage)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </section>

      <section :if={@active_tab == :deaths} class="rounded-lg border border-zinc-700 bg-zinc-800">
        <div class="border-b border-zinc-700 px-4 py-3">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Death Recap</h2>
        </div>

        <div :if={@deaths == []} class="px-4 py-6 text-sm text-zinc-400">
          No death recap data exists for this pull.
        </div>

        <div :if={@deaths != []} class="divide-y divide-zinc-700">
          <article :for={death <- @deaths} class="p-4">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                  <span class="font-mono text-sm font-semibold text-wow-death">
                    {format_ms(death.died_at_ms_into_fight)}
                  </span>
                  <span class="font-semibold" style={player_class_style(death.class_id)}>
                    {death.player_name || death.target_guid}
                  </span>
                  <span class="text-xs uppercase tracking-wide text-zinc-500">
                    {format_role(death.detected_role, death.spec_id)}
                  </span>
                </div>
                <p class="mt-1 text-xs font-mono text-zinc-500">{death.target_guid}</p>
              </div>

              <div class="text-sm text-zinc-300 sm:text-right">
                <div class="font-medium text-zinc-100">{format_killing_blow(death)}</div>
                <div class="mt-1 text-xs text-zinc-500">
                  Source {format_value(death.killing_blow_source_guid)}
                </div>
              </div>
            </div>

            <div class="mt-4 overflow-x-auto">
              <table class="w-full">
                <thead>
                  <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
                    <th class="px-3 py-2">Time</th>
                    <th class="px-3 py-2">Damage</th>
                    <th class="px-3 py-2">Source</th>
                    <th class="px-3 py-2 text-right">Amount</th>
                    <th class="px-3 py-2 text-right">Overkill</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={death.damage_recap == []} class="border-b border-zinc-700/60 last:border-0">
                    <td colspan="5" class="px-3 py-3 text-sm text-zinc-400">
                      No damage recap details stored.
                    </td>
                  </tr>
                  <tr :for={event <- death.damage_recap} class="border-b border-zinc-700/60 last:border-0">
                    <td class="px-3 py-2 font-mono text-sm text-zinc-300">
                      {format_ms(recap_value(event, "ms_into_fight"))}
                    </td>
                    <td class="px-3 py-2 text-sm text-zinc-100">
                      <.wowhead_link
                        :if={recap_value(event, "spell_id")}
                        spell_id={recap_value(event, "spell_id")}
                        name={recap_value(event, "spell_name") || "Unknown"}
                      />
                      <span :if={!recap_value(event, "spell_id")}>
                        {recap_value(event, "spell_name") || "Unknown"}
                      </span>
                      <span :if={recap_value(event, "spell_id")} class="text-xs text-zinc-500">
                        ({recap_value(event, "spell_id")})
                      </span>
                    </td>
                    <td class="px-3 py-2 text-sm text-zinc-300">
                      {recap_value(event, "source_name") || recap_value(event, "source_guid") || "Unknown"}
                    </td>
                    <td class="px-3 py-2 text-right font-mono text-sm text-zinc-300">
                      {format_number(recap_value(event, "amount") || 0)}
                    </td>
                    <td class="px-3 py-2 text-right font-mono text-sm text-zinc-300">
                      {format_number(recap_value(event, "overkill") || 0)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </article>
        </div>
      </section>

      <section :if={@active_tab == :interrupts} class="space-y-6">
        <div class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Interrupt Coverage</h2>
          <p class="mt-2 text-sm text-zinc-400">
            Successful interrupts come from combat-log interrupt events. Missed opportunities are limited to known interruptible cast windows from code-defined encounter data.
          </p>
        </div>

        <div class="rounded-lg border border-zinc-700 bg-zinc-800">
          <div class="border-b border-zinc-700 px-4 py-3">
            <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Spell Coverage</h3>
          </div>

          <div :if={@interrupt_coverage.spell_coverage == []} class="px-4 py-6 text-sm text-zinc-400">
            No interrupt opportunities exist for this pull.
          </div>

          <div :if={@interrupt_coverage.spell_coverage != []} class="overflow-x-auto">
            <table class="w-full">
              <thead>
                <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
                  <th class="px-4 py-2">Spell</th>
                  <th class="px-4 py-2 text-right">Opportunities</th>
                  <th class="px-4 py-2 text-right">Interrupted</th>
                  <th class="px-4 py-2 text-right">Cast Successes</th>
                  <th class="px-4 py-2 text-right">Targets</th>
                  <th class="px-4 py-2">Tracking</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={spell <- @interrupt_coverage.spell_coverage} class="border-b border-zinc-700/60 last:border-0">
                  <td class="px-4 py-3">
                    <div class="font-medium text-zinc-100">
                      <.wowhead_link spell_id={spell.spell_id} name={spell.spell_name} />
                    </div>
                    <div class="text-xs text-zinc-500">Spell {spell.spell_id}</div>
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {spell.total_opportunities}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {spell.successful_interrupts}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {spell.missed_casts}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {spell.target_count}
                  </td>
                  <td class="px-4 py-3 text-sm">
                    <span
                      :if={spell.required_failure_count}
                      class="rounded bg-red-950 px-2 py-1 text-xs font-medium text-red-300"
                    >
                      Required interrupt failures: {spell.required_failure_count}
                    </span>
                    <span :if={!spell.required_failure_count} class="text-zinc-500">Raw evidence</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="rounded-lg border border-zinc-700 bg-zinc-800">
          <div class="border-b border-zinc-700 px-4 py-3">
            <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Player Contributions</h3>
          </div>

          <div :if={@interrupt_coverage.player_contributions == []} class="px-4 py-6 text-sm text-zinc-400">
            No successful player interrupts are stored for this pull.
          </div>

          <div :if={@interrupt_coverage.player_contributions != []} class="overflow-x-auto">
            <table class="w-full">
              <thead>
                <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
                  <th class="px-4 py-2">Player</th>
                  <th class="px-4 py-2 text-right">Interrupts</th>
                  <th class="px-4 py-2 text-right">Spells Covered</th>
                  <th class="px-4 py-2">Top Coverage</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={player <- @interrupt_coverage.player_contributions} class="border-b border-zinc-700/60 last:border-0">
                  <td class="px-4 py-3">
                    <div class="font-medium" style={player_class_style(player.class_id)}>
                      {player.player_name || player.interrupter_guid}
                    </div>
                    <div class="text-xs font-mono text-zinc-500">{player.interrupter_guid}</div>
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {player.total_interrupts}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                    {player.interrupted_spell_count}
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-300">
                    {format_spell_counts(player.by_spell)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <section :if={@active_tab == :personal} class="space-y-6">
        <div class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Personal Pull Summary</h2>
              <p class="mt-2 text-sm text-zinc-400">
                Player-scoped damage, death, interrupt, and mechanic failure summary for this pull.
              </p>
            </div>

            <form
              :if={@personal_pull_summary.players != []}
              phx-change="select_personal_player"
              class="sm:min-w-64"
            >
              <label for="personal-player-guid" class="block text-xs font-medium uppercase tracking-wide text-zinc-500">
                Player
              </label>
              <select
                id="personal-player-guid"
                name="personal[player_guid]"
                class="mt-1 w-full rounded border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-100"
              >
                <option
                  :for={player <- @personal_pull_summary.players}
                  value={player.player_guid}
                  selected={player.player_guid == @selected_personal_player_guid}
                >
                  {player.player_name}
                </option>
              </select>
            </form>
          </div>
        </div>

        <div :if={@selected_personal_player == nil} class="rounded-lg border border-zinc-700 bg-zinc-800 px-4 py-6 text-sm text-zinc-400">
          No player roster data exists for this pull.
        </div>

        <div :if={@selected_personal_player} class="space-y-6">
          <section class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
            <div class="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
              <div>
                <h3 class="text-xl font-semibold" style={player_class_style(@selected_personal_player.class_id)}>
                  {@selected_personal_player.player_name}
                </h3>
                <p class="text-xs font-mono text-zinc-500">{@selected_personal_player.player_guid}</p>
              </div>
              <div class="text-sm text-zinc-400">
                {format_role(
                  @selected_personal_player.detected_role,
                  @selected_personal_player.spec_id
                )}
                <span class="text-zinc-600">&bull;</span>
                {format_class(@selected_personal_player.class_id)}
                <span class="text-zinc-600">&bull;</span>
                {format_spec(@selected_personal_player.spec_id)}
              </div>
            </div>
          </section>

          <section class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <.metric_item label="Damage Done" value={format_number(@selected_personal_player.damage_done)} />
            <.metric_item label="Damage Taken" value={format_number(@selected_personal_player.damage_taken)} />
            <.metric_item label="Mechanic Failures" value={to_string(@selected_personal_player.mechanic_failures)} />
            <.metric_item label="Failure Damage" value={format_number(@selected_personal_player.failure_damage)} />
            <.metric_item label="Successful Interrupts" value={to_string(@selected_personal_player.successful_interrupts)} />
            <.metric_item label="Deaths" value={to_string(@selected_personal_player.death_count)} />
            <.metric_item label="First Death" value={format_optional_ms(@selected_personal_player.first_death_ms)} />
            <.metric_item label="Max Damage Taken" value={format_number(@selected_personal_player.max_damage_taken_hit)} />
          </section>

          <section class="rounded-lg border border-zinc-700 bg-zinc-800">
            <div class="border-b border-zinc-700 px-4 py-3">
              <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">
                Defensive Coverage
              </h3>
            </div>

            <div :if={@selected_personal_player.defensive_analysis.summary.dangerous_events_count == 0} class="px-4 py-6 text-sm text-zinc-400">
              No failure damage or deaths exist for this player on this pull.
            </div>

            <div :if={@selected_personal_player.defensive_analysis.summary.dangerous_events_count > 0} class="space-y-4 p-4">
              <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <.metric_item
                  label="Defensive Windows"
                  value={to_string(@selected_personal_player.defensive_analysis.summary.windows_count)}
                />
                <.metric_item
                  label="Dangerous Events"
                  value={to_string(@selected_personal_player.defensive_analysis.summary.dangerous_events_count)}
                />
                <.metric_item
                  label="Covered"
                  value={to_string(@selected_personal_player.defensive_analysis.summary.covered_events_count)}
                />
                <.metric_item
                  label="Uncovered"
                  value={to_string(@selected_personal_player.defensive_analysis.summary.uncovered_events_count)}
                />
              </div>

              <div class="overflow-x-auto">
                <table class="w-full">
                  <thead>
                    <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
                      <th class="px-4 py-2">Time</th>
                      <th class="px-4 py-2">Event</th>
                      <th class="px-4 py-2">Spell</th>
                      <th class="px-4 py-2 text-right">Amount</th>
                      <th class="px-4 py-2">Active Defensives</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={event <- @selected_personal_player.defensive_analysis.events}
                      class="border-b border-zinc-700/60 last:border-0"
                    >
                      <td class="px-4 py-3 font-mono text-sm text-zinc-300">
                        {format_ms(event.occurred_at_ms)}
                      </td>
                      <td class="px-4 py-3 text-sm text-zinc-300">
                        <span class={defensive_coverage_class(event.covered)}>
                          {defensive_coverage_label(event.covered)}
                        </span>
                        <div class="mt-1 text-xs text-zinc-500">
                          {format_dangerous_event_type(event.type)}
                        </div>
                      </td>
                      <td class="px-4 py-3 text-sm text-zinc-100">
                        {event.spell_name || event.mechanic_name || "Unknown"}
                      </td>
                      <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                        {format_number(event.amount)}
                      </td>
                      <td class="px-4 py-3 text-sm text-zinc-300">
                        {format_active_defensives(event.active_defensives)}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </section>

          <section class="rounded-lg border border-zinc-700 bg-zinc-800">
            <div class="border-b border-zinc-700 px-4 py-3">
              <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">
                Encounter Performance
              </h3>
            </div>

            <div :if={@selected_personal_player.performance.pulls == []} class="px-4 py-6 text-sm text-zinc-400">
              No same-boss participation rows exist for this player.
            </div>

            <div :if={@selected_personal_player.performance.pulls != []} class="space-y-4 p-4">
              <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <.metric_item
                  label="Recent Pulls"
                  value={to_string(@selected_personal_player.performance.summary.pull_count)}
                />
                <.metric_item
                  label="Avg Failures"
                  value={format_decimal(@selected_personal_player.performance.summary.avg_failures_per_pull)}
                />
                <.metric_item
                  label="Failure Delta"
                  value={format_delta(@selected_personal_player.performance.summary.current_failure_delta)}
                />
                <.metric_item
                  label="Damage Taken Delta"
                  value={format_number_delta(@selected_personal_player.performance.summary.current_damage_taken_delta)}
                />
              </div>

              <div class="overflow-x-auto">
                <table class="w-full">
                  <thead>
                    <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
                      <th class="px-4 py-2">Pull</th>
                      <th class="px-4 py-2">Result</th>
                      <th class="px-4 py-2 text-right">Failures</th>
                      <th class="px-4 py-2 text-right">Deaths</th>
                      <th class="px-4 py-2 text-right">Damage Taken</th>
                      <th class="px-4 py-2 text-right">Interrupts</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={pull <- @selected_personal_player.performance.pulls}
                      class={[
                        "border-b border-zinc-700/60 last:border-0",
                        if(pull.current, do: "bg-zinc-900/50", else: nil)
                      ]}
                    >
                      <td class="px-4 py-3">
                        <div class="text-sm font-medium text-zinc-100">
                          {format_datetime(pull.start_time)}
                        </div>
                        <div :if={pull.current} class="text-xs text-wow-gold">Current pull</div>
                      </td>
                      <td class="px-4 py-3 text-sm text-zinc-300">{format_result(pull.success)}</td>
                      <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                        {pull.mechanic_failures}
                      </td>
                      <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                        {pull.death_count}
                      </td>
                      <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                        {format_number(pull.damage_taken)}
                      </td>
                      <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                        {pull.successful_interrupts}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </section>

          <section class="rounded-lg border border-zinc-700 bg-zinc-800">
            <div class="border-b border-zinc-700 px-4 py-3">
              <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Raw Pull Totals</h3>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full">
                <thead>
                  <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
                    <th class="px-4 py-2">Category</th>
                    <th class="px-4 py-2 text-right">Amount</th>
                    <th class="px-4 py-2 text-right">Events</th>
                    <th class="px-4 py-2 text-right">Max Hit</th>
                  </tr>
                </thead>
                <tbody>
                  <tr class="border-b border-zinc-700/60">
                    <td class="px-4 py-3 text-sm text-zinc-100">Damage Done</td>
                    <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                      {format_number(@selected_personal_player.damage_done)}
                    </td>
                    <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                      {@selected_personal_player.damage_done_hits}
                    </td>
                    <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                      {format_number(@selected_personal_player.max_damage_done_hit)}
                    </td>
                  </tr>
                  <tr class="border-b border-zinc-700/60 last:border-0">
                    <td class="px-4 py-3 text-sm text-zinc-100">Damage Taken</td>
                    <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                      {format_number(@selected_personal_player.damage_taken)}
                    </td>
                    <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                      {@selected_personal_player.damage_taken_hits}
                    </td>
                    <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                      {format_number(@selected_personal_player.max_damage_taken_hit)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </section>
    </div>
    """
  end

  attr(:tab, :atom, required: true)
  attr(:active, :atom, required: true)
  attr(:count, :integer, default: nil)
  slot(:inner_block, required: true)

  defp tab_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="switch_tab"
      phx-value-tab={@tab}
      class={[
        "whitespace-nowrap border-b-2 px-1 pb-3 text-sm font-medium transition-colors",
        if(@active == @tab,
          do: "border-wow-gold text-wow-gold",
          else: "border-transparent text-zinc-400 hover:border-zinc-600 hover:text-zinc-200"
        )
      ]}
    >
      {render_slot(@inner_block)}
      <span :if={@count} class="ml-1 text-zinc-500">({@count})</span>
    </button>
    """
  end

  attr(:title, :string, required: true)
  attr(:body, :string, required: true)

  defp placeholder_panel(assigns) do
    ~H"""
    <section class="rounded-lg border border-dashed border-zinc-700 bg-zinc-800 p-6">
      <h2 class="text-lg font-semibold text-zinc-100">{@title}</h2>
      <p class="mt-2 text-sm text-zinc-400">{@body}</p>
    </section>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)

  defp metadata_item(assigns) do
    ~H"""
    <div>
      <div class="text-xs font-medium uppercase tracking-wide text-zinc-500">{@label}</div>
      <div class="mt-1 text-sm text-zinc-100">{@value}</div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :integer, required: true)

  defp count_item(assigns) do
    ~H"""
    <div class="rounded border border-zinc-700 bg-zinc-900 px-3 py-2">
      <div class="text-xs font-medium uppercase tracking-wide text-zinc-500">{@label}</div>
      <div class="mt-1 text-lg font-semibold text-zinc-100">{@value}</div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)

  defp metric_item(assigns) do
    ~H"""
    <div class="rounded border border-zinc-700 bg-zinc-800 px-3 py-2">
      <div class="text-xs font-medium uppercase tracking-wide text-zinc-500">{@label}</div>
      <div class="mt-1 text-lg font-semibold text-zinc-100">{@value}</div>
    </div>
    """
  end

  defp parse_tab("deaths"), do: :deaths
  defp parse_tab("failures"), do: :failures
  defp parse_tab("mechanics"), do: :mechanics
  defp parse_tab("interrupts"), do: :interrupts
  defp parse_tab("personal"), do: :personal
  defp parse_tab(_tab), do: :overview

  defp player_class_style(nil), do: nil
  defp player_class_style(class_id), do: "color: #{WowClass.class_color(class_id)}"

  defp format_class(nil), do: "Unknown"
  defp format_class(class_id), do: WowClass.class_name(class_id)

  defp format_spec(nil), do: "Unknown"
  defp format_spec(spec_id), do: WowClass.spec_name(spec_id)

  defp format_role(role, spec_id)

  defp format_role(role, spec_id) when not is_nil(spec_id) do
    case WowClass.role_from_spec(spec_id) do
      nil -> format_role_value(role)
      role -> format_role_value(role)
    end
  end

  defp format_role(role, _spec_id), do: format_role_value(role)

  defp format_role_value(nil), do: "Unknown"

  defp format_role_value(role) do
    role
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_value(nil), do: "Unknown"
  defp format_value(value), do: to_string(value)

  defp format_mechanic_type(type) when is_atom(type),
    do: type |> Atom.to_string() |> format_mechanic_type()

  defp format_mechanic_type(type) when is_binary(type) do
    type
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_mechanic_type(type), do: to_string(type)

  defp mechanic_status_label(:producing_failures), do: "Producing failures"
  defp mechanic_status_label(:active_criterion), do: "Tracked"
  defp mechanic_status_label(:catalog_tracked), do: "Trackable"
  defp mechanic_status_label(:catalog_context), do: "Known mechanic"
  defp mechanic_status_label(:observed_only), do: "Combat-log event"
  defp mechanic_status_label(status), do: format_mechanic_type(status)

  defp mechanic_status_class(:producing_failures) do
    "rounded bg-red-950 px-2 py-1 text-xs font-medium text-red-300"
  end

  defp mechanic_status_class(:active_criterion) do
    "rounded bg-yellow-950 px-2 py-1 text-xs font-medium text-yellow-300"
  end

  defp mechanic_status_class(:catalog_tracked) do
    "rounded bg-amber-950 px-2 py-1 text-xs font-medium text-amber-300"
  end

  defp mechanic_status_class(:catalog_context) do
    "rounded bg-sky-950 px-2 py-1 text-xs font-medium text-sky-300"
  end

  defp mechanic_status_class(_status) do
    "rounded bg-zinc-700 px-2 py-1 text-xs font-medium text-zinc-300"
  end

  defp mechanic_event_count(mechanic) do
    mechanic.observed.damage_hits + mechanic.observed.debuff_applications +
      mechanic.observed.interrupt_opportunities
  end

  defp mechanic_player_count(mechanic) do
    Enum.max([
      mechanic.observed.affected_players,
      mechanic.observed.debuffed_players,
      mechanic.observed.interrupt_target_count
    ])
  end

  defp format_observed_channels(mechanic) do
    channels =
      []
      |> maybe_add_observed_channel(mechanic.observed.damage_hits > 0, "damage")
      |> maybe_add_observed_channel(mechanic.observed.debuff_applications > 0, "debuff")
      |> maybe_add_observed_channel(mechanic.observed.interrupt_opportunities > 0, "interrupt")

    if channels == [] do
      "combat log"
    else
      Enum.join(channels, ", ")
    end
  end

  defp maybe_add_observed_channel(channels, false, _label), do: channels
  defp maybe_add_observed_channel(channels, _present, label), do: channels ++ [label]

  defp failure_preview_diagnostic_class(:blocked) do
    "rounded border border-amber-700/60 bg-amber-950/30 px-4 py-3 text-sm"
  end

  defp failure_preview_diagnostic_class(:warning) do
    "rounded border border-yellow-700/60 bg-yellow-950/30 px-4 py-3 text-sm"
  end

  defp failure_preview_diagnostic_class(_severity) do
    "rounded border border-zinc-700 bg-zinc-800 px-4 py-3 text-sm"
  end

  defp plural(1), do: ""
  defp plural(_count), do: "s"

  defp format_ms(ms) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)

    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  defp format_ms(_ms), do: "0:00"

  defp format_optional_ms(nil), do: "None"
  defp format_optional_ms(ms), do: format_ms(ms)

  defp format_dangerous_event_type(:failure_damage), do: "Failure damage"
  defp format_dangerous_event_type(:death), do: "Death"
  defp format_dangerous_event_type(type), do: format_mechanic_type(type)

  defp format_active_defensives([]), do: "None"

  defp format_active_defensives(defensives) do
    defensives
    |> Enum.map_join(", ", fn defensive ->
      "#{defensive.spell_name} (#{defensive.category})"
    end)
  end

  defp defensive_coverage_label(true), do: "Covered"
  defp defensive_coverage_label(false), do: "Uncovered"

  defp defensive_coverage_class(true) do
    "rounded bg-emerald-950 px-2 py-1 text-xs font-medium text-emerald-300"
  end

  defp defensive_coverage_class(false) do
    "rounded bg-red-950 px-2 py-1 text-xs font-medium text-red-300"
  end

  defp format_result(true), do: "Kill"
  defp format_result(false), do: "Wipe"
  defp format_result(_result), do: "Unknown"

  defp format_decimal(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 1)
  defp format_decimal(value), do: to_string(value)

  defp format_delta(nil), do: "No prior pull"
  defp format_delta(0), do: "0"
  defp format_delta(value) when value > 0, do: "+#{value}"
  defp format_delta(value), do: to_string(value)

  defp format_number_delta(nil), do: "No prior pull"
  defp format_number_delta(0), do: "0"
  defp format_number_delta(value) when value > 0, do: "+#{format_number(value)}"
  defp format_number_delta(value), do: "-#{format_number(abs(value))}"

  defp format_killing_blow(%{killing_blow: %{} = killing_blow}) do
    spell_name = recap_value(killing_blow, "spell_name") || "Unknown"
    amount = recap_value(killing_blow, "amount") || 0
    overkill = recap_value(killing_blow, "overkill") || 0

    overkill_text =
      if overkill > 0 do
        " with #{format_number(overkill)} overkill"
      else
        ""
      end

    "#{spell_name} for #{format_number(amount)}#{overkill_text}"
  end

  defp format_killing_blow(%{killing_blow_spell_id: spell_id}) when not is_nil(spell_id) do
    "Spell #{spell_id}"
  end

  defp format_killing_blow(_death), do: "Unknown killing blow"

  defp recap_value(%{} = event, key),
    do: Map.get(event, key) || Map.get(event, String.to_atom(key))

  defp recap_value(_event, _key), do: nil

  defp format_spell_counts([]), do: "None"

  defp format_spell_counts(spell_counts) do
    spell_counts
    |> Enum.take(3)
    |> Enum.map_join(", ", fn spell -> "#{spell.spell_name} x#{spell.count}" end)
  end

  defp format_datetime(nil), do: "Unknown"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
  end

  defp assign_personal_summary(socket, summary) do
    selected_player_guid = summary.selected_player_guid

    socket
    |> assign(:personal_pull_summary, summary)
    |> assign(:selected_personal_player_guid, selected_player_guid)
    |> assign(
      :selected_personal_player,
      selected_personal_player(summary.players, selected_player_guid)
    )
  end

  defp selected_personal_player(players, selected_player_guid) do
    Enum.find(players, &(&1.player_guid == selected_player_guid))
  end

  defp not_found_message(:invalid_id), do: "Pull IDs must be positive numbers."
  defp not_found_message(:not_found), do: "No imported pull exists for that ID."
end
