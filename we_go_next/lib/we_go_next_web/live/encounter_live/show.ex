defmodule WeGoNextWeb.EncounterLive.Show do
  @moduledoc """
  Medallion encounter detail shell keyed by `gold.dim_encounter.id`.

  This route intentionally reads only gold/silver read models. It must not call
  legacy analyzers, analyzer cache output, or `public.mechanic_criteria`.
  """

  use WeGoNextWeb, :live_view

  alias WeGoNext.Accounts
  alias WeGoNext.Gold.EncounterDetail
  alias WeGoNext.WowClass
  import WeGoNextWeb.EncounterComponents, only: [format_duration: 1, format_number: 1]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = Accounts.get_or_create_default_user()

    case EncounterDetail.get(id, character_name: user.character_name) do
      {:ok, detail} ->
        {:ok,
         socket
         |> assign(:page_title, detail.encounter.name)
         |> assign(:user, user)
         |> assign(:detail, detail)
         |> assign(:encounter, detail.encounter)
         |> assign(:counts, detail.counts)
         |> assign(:roster, detail.roster)
         |> assign(:deaths, detail.deaths)
         |> assign(:interrupt_coverage, detail.interrupt_coverage)
         |> assign_personal_summary(detail.personal_pull_summary)
         |> assign(:active_tab, :overview)}

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
         |> assign(:interrupt_coverage, %{spell_coverage: [], player_contributions: []})
         |> assign_personal_summary(%{selected_player_guid: nil, players: []})
         |> assign(:active_tab, :overview)
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
            Medallion encounter detail keyed by gold encounter #{@encounter.id}.
          </p>
        </div>

        <.link navigate={~p"/failures"} class="text-sm text-zinc-400 hover:text-zinc-200">
          View failures
        </.link>
      </div>

      <nav class="border-b border-zinc-700">
        <div class="flex gap-5 overflow-x-auto">
          <.tab_button tab={:overview} active={@active_tab}>Overview</.tab_button>
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
            <.metadata_item label="Gold Encounter ID" value={to_string(@encounter.id)} />
          </div>
        </section>

        <section class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Medallion Rows</h2>
          <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <.count_item label="Players" value={@counts.players} />
            <.count_item label="Damage Groups" value={@counts.damage_taken_groups} />
            <.count_item label="Damage Hits" value={@counts.damage_taken_events} />
            <.count_item label="Damage Done Groups" value={@counts.damage_done_groups} />
            <.count_item label="Deaths" value={@counts.deaths} />
            <.count_item label="Interrupt Opportunities" value={@counts.interrupt_opportunities} />
            <.count_item label="Debuffs" value={@counts.debuff_applications} />
            <.count_item label="Failure Facts" value={@counts.failure_facts} />
          </div>
        </section>

        <section class="rounded-lg border border-zinc-700 bg-zinc-800">
          <div class="border-b border-zinc-700 px-4 py-3">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Roster</h2>
          </div>

          <div :if={@roster == []} class="px-4 py-6 text-sm text-zinc-400">
            No silver player roster rows exist for this gold encounter yet.
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
                  <td class="px-4 py-3 text-sm text-zinc-300">{format_role(player.detected_role)}</td>
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

      <section :if={@active_tab == :deaths} class="rounded-lg border border-zinc-700 bg-zinc-800">
        <div class="border-b border-zinc-700 px-4 py-3">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Death Recap</h2>
        </div>

        <div :if={@deaths == []} class="px-4 py-6 text-sm text-zinc-400">
          No silver death rows exist for this gold encounter.
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
                    {format_role(death.detected_role)}
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
                      {recap_value(event, "spell_name") || "Unknown"}
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
            Raw coverage comes from silver interrupt opportunities. Failed opportunities currently include NPC cast-success rows and should not be treated as assigned missed kicks unless they are labeled by rules-backed failure facts.
          </p>
        </div>

        <div class="rounded-lg border border-zinc-700 bg-zinc-800">
          <div class="border-b border-zinc-700 px-4 py-3">
            <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Spell Coverage</h3>
          </div>

          <div :if={@interrupt_coverage.spell_coverage == []} class="px-4 py-6 text-sm text-zinc-400">
            No silver interrupt opportunity rows exist for this gold encounter.
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
                  <th class="px-4 py-2">Rule Label</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={spell <- @interrupt_coverage.spell_coverage} class="border-b border-zinc-700/60 last:border-0">
                  <td class="px-4 py-3">
                    <div class="font-medium text-zinc-100">{spell.spell_name}</div>
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
            No successful player interrupts are stored for this gold encounter.
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
                Player-scoped rollup from silver damage, death, and interrupt rows plus gold mechanic failure facts.
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
          No silver player roster rows exist for this gold encounter.
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
                {format_role(@selected_personal_player.detected_role)}
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
  defp parse_tab("interrupts"), do: :interrupts
  defp parse_tab("personal"), do: :personal
  defp parse_tab(_tab), do: :overview

  defp player_class_style(nil), do: nil
  defp player_class_style(class_id), do: "color: #{WowClass.class_color(class_id)}"

  defp format_class(nil), do: "Unknown"
  defp format_class(class_id), do: WowClass.class_name(class_id)

  defp format_spec(nil), do: "Unknown"
  defp format_spec(spec_id), do: "Spec #{spec_id}"

  defp format_role(nil), do: "Unknown"

  defp format_role(role) do
    role
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_value(nil), do: "Unknown"
  defp format_value(value), do: to_string(value)

  defp format_ms(ms) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)

    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  defp format_ms(_ms), do: "0:00"

  defp format_optional_ms(nil), do: "None"
  defp format_optional_ms(ms), do: format_ms(ms)

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

  defp not_found_message(:invalid_id), do: "Encounter IDs must be positive gold encounter IDs."
  defp not_found_message(:not_found), do: "No gold encounter exists for that ID."
end
