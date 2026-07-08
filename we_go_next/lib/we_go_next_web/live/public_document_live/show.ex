defmodule WeGoNextWeb.PublicDocumentLive.Show do
  @moduledoc """
  Public encounter detail rendered from one uploaded encounter document.
  """

  use WeGoNextWeb, :live_view

  alias WeGoNext.Documents

  import WeGoNextWeb.EncounterComponents,
    only: [format_duration: 1, format_number: 1, tab_button: 1, wowhead_link: 1]

  @impl true
  def mount(
        %{"slug" => slug, "source_encounter_key" => source_encounter_key} = params,
        session,
        socket
      ) do
    active_tab = parse_tab(Map.get(params, "tab"))

    case Documents.fetch_encounter(source_encounter_key) do
      {:ok, document} ->
        {:ok,
         socket
         |> assign(:page_title, document.encounter.name)
         |> assign(:slug, slug)
         |> assign(:title, session["public_report_title"])
         |> assign(:document, document)
         |> assign(:document_state, document_state(document))
         |> assign(:encounter, document.encounter)
         |> assign(:counts, document.counts)
         |> assign(:roster, document.roster)
         |> assign(:deaths, document.deaths)
         |> assign(:pull_review, document.pull_review)
         |> assign(:failure_preview, normalize_failure_preview(document.failure_preview))
         |> assign(:interrupt_coverage, document.interrupt_coverage)
         |> assign(:active_tab, active_tab)}

      {:error, reason} ->
        {:ok,
         socket
         |> assign(:page_title, "Encounter Not Found")
         |> assign(:slug, slug)
         |> assign(:title, session["public_report_title"])
         |> assign(:document, nil)
         |> assign(:document_state, {:missing, source_encounter_key})
         |> assign(:encounter, nil)
         |> assign(:error, not_found_message(reason, source_encounter_key))}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, parse_tab(tab))}
  end

  @impl true
  def render(%{encounter: nil} = assigns) do
    ~H"""
    <div class="space-y-6">
      <.link navigate={~p"/r/#{@slug}"} class="text-sm text-zinc-400 hover:text-zinc-200">
        Back to encounters
      </.link>

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
          <.link navigate={~p"/r/#{@slug}"} class="text-sm text-zinc-400 hover:text-zinc-200">
            Back to encounters
          </.link>
          <h1 class="mt-3 text-2xl font-bold text-wow-gold">{@encounter.name}</h1>
          <p class="mt-1 text-sm text-zinc-400">
            {@title} &middot; Started {format_datetime(@encounter.start_time)}
          </p>
        </div>
      </div>

      <.document_state_banner state={@document_state} document={@document} />

      <section class="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
        <.pull_stat
          label="Deaths"
          value={to_string(@counts.deaths || 0)}
          tone={if @counts.deaths > 0, do: :danger, else: :ok}
        />
        <.pull_stat
          label="Failures"
          value={to_string(@failure_preview.counts.failures || 0)}
          tone={if @failure_preview.counts.failures > 0, do: :danger, else: :ok}
        />
        <.pull_stat
          label="Missed Kicks"
          value={to_string(missed_interrupt_count(@interrupt_coverage))}
          tone={if missed_interrupt_count(@interrupt_coverage) > 0, do: :warning, else: :ok}
        />
        <.pull_stat
          label="Damage Done"
          value={format_number(total_damage_done(@pull_review.damage_done))}
          tone={:neutral}
        />
        <.pull_stat
          label="Low Damage"
          value={to_string(length(@pull_review.low_dps))}
          tone={if @pull_review.low_dps == [], do: :ok, else: :warning}
        />
      </section>

      <nav class="border-b border-zinc-700">
        <div class="flex gap-5 overflow-x-auto">
          <.tab_button tab={:overview} active={@active_tab}>Overview</.tab_button>
          <.tab_button tab={:damage} active={@active_tab} count={length(@pull_review.low_dps)}>
            Damage
          </.tab_button>
          <.tab_button tab={:failures} active={@active_tab} count={@failure_preview.counts.failures}>
            Failures
          </.tab_button>
          <.tab_button tab={:deaths} active={@active_tab} count={@counts.deaths}>Death Recap</.tab_button>
          <.tab_button tab={:interrupts} active={@active_tab} count={@counts.interrupt_opportunities}>
            Interrupt Coverage
          </.tab_button>
        </div>
      </nav>

      <section :if={@active_tab == :overview} class="space-y-6">
        <div class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
          <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <.metadata_item label="Difficulty" value={@encounter.difficulty_name || "Unknown"} />
            <.metadata_item label="Result" value={if @encounter.success, do: "Kill", else: "Wipe"} />
            <.metadata_item label="Duration" value={format_duration(@encounter)} />
            <.metadata_item label="Group Size" value={format_value(@encounter.group_size)} />
            <.metadata_item label="Started" value={format_datetime(@encounter.start_time)} />
          </div>
        </div>

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
                </tr>
              </thead>
              <tbody>
                <tr :for={player <- @roster} class="border-b border-zinc-700/60 last:border-0">
                  <td class="px-4 py-3">
                    <div class="font-medium" style={player_class_style(player.class_id)}>
                      {player.player_name}
                    </div>
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-300">
                    {format_role(player.detected_role)}
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-300">{format_class(player.class_id)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </section>

      <section :if={@active_tab == :damage} class="space-y-6">
        <.simple_table
          title="Low Damage Warnings"
          empty="No low damage warnings for this pull."
          rows={@pull_review.low_dps}
          columns={[:player, :role, :dps, :median_share]}
        />
        <.simple_table
          title="Damage Done Ranking"
          empty="No damage meter rows exist for this pull."
          rows={@pull_review.damage_done}
          columns={[:player, :role, :dps, :total_damage]}
        />
      </section>

      <section :if={@active_tab == :failures} class="space-y-6">
        <div :if={@failure_preview.mechanics == [] && @failure_preview.diagnostics == []} class="rounded-lg border border-zinc-700 bg-zinc-800 px-4 py-6 text-sm text-zinc-400">
          No mechanic failures exist for this pull.
        </div>

        <div :if={@failure_preview.diagnostics != []} class="space-y-2">
          <div :for={diagnostic <- @failure_preview.diagnostics} class="rounded-lg border border-yellow-800/70 bg-yellow-950/30 p-4">
            <div class="font-medium text-zinc-100">{diagnostic.title}</div>
            <p class="mt-1 text-sm text-zinc-300">{diagnostic.body}</p>
          </div>
        </div>

        <section
          :for={mechanic <- @failure_preview.mechanics}
          class="rounded-lg border border-zinc-700 bg-zinc-800"
        >
          <div class="flex flex-col gap-2 border-b border-zinc-700 px-4 py-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h2 class="font-semibold text-zinc-100">
                <.wowhead_link spell_id={mechanic.spell_id} name={mechanic.spell_name} />
              </h2>
              <p class="mt-1 text-xs text-zinc-500">
                Spell {mechanic.spell_id} &middot; {format_mechanic_type(mechanic.mechanic_type)}
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
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-300">{format_role(player.detected_role)}</td>
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
            <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <span class="font-semibold" style={player_class_style(death.class_id)}>
                  {death.player_name || death.target_guid}
                </span>
                <span class="ml-2 text-xs uppercase tracking-wide text-zinc-500">
                  {format_role(death.detected_role)}
                </span>
              </div>
              <div class="text-sm text-zinc-300 sm:text-right">
                {death.killing_blow_spell_name || "Unknown killing blow"}
              </div>
            </div>
          </article>
        </div>
      </section>

      <section :if={@active_tab == :interrupts} class="rounded-lg border border-zinc-700 bg-zinc-800">
        <div class="border-b border-zinc-700 px-4 py-3">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Interrupt Coverage</h2>
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
                <th class="px-4 py-2 text-right">Missed</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={spell <- @interrupt_coverage.spell_coverage} class="border-b border-zinc-700/60 last:border-0">
                <td class="px-4 py-3">
                  <.wowhead_link spell_id={spell.spell_id} name={spell.spell_name} />
                </td>
                <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                  {spell.total_opportunities}
                </td>
                <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                  {spell.successful_interrupts}
                </td>
                <td class="px-4 py-3 text-right font-mono text-sm text-zinc-300">
                  {spell.missed_opportunities}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end

  defp document_state(document) do
    cond do
      document.derivation_version != Documents.current_derivation_version() ->
        {:stale, Documents.current_derivation_version()}

      empty_document?(document) ->
        :empty

      true ->
        :fresh
    end
  end

  defp document_state_banner(%{state: :fresh} = assigns), do: ~H""

  defp document_state_banner(%{state: {:stale, current_version}} = assigns) do
    assigns = assign(assigns, :current_version, current_version)

    ~H"""
    <section class="rounded-lg border border-yellow-800/70 bg-yellow-950/30 p-4">
      <h2 class="font-semibold text-yellow-100">Stale Encounter Document</h2>
      <p class="mt-1 text-sm text-yellow-200">
        This document was built with derivation version {@document.derivation_version}; the app expects
        {@current_version}. Some sections may not match the current analysis semantics.
      </p>
    </section>
    """
  end

  defp document_state_banner(%{state: :empty} = assigns) do
    ~H"""
    <section class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
      <h2 class="font-semibold text-zinc-100">Empty Encounter Document</h2>
      <p class="mt-1 text-sm text-zinc-400">
        This pull has a document, but no player-facing analysis rows were generated for it yet.
      </p>
    </section>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:tone, :atom, default: :neutral)

  defp pull_stat(assigns) do
    ~H"""
    <div class={["rounded-lg border p-4", stat_class(@tone)]}>
      <div class="text-xs font-semibold uppercase tracking-wide text-zinc-400">{@label}</div>
      <div class="mt-2 font-mono text-2xl font-semibold text-zinc-100">{@value}</div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)

  defp metadata_item(assigns) do
    ~H"""
    <div>
      <div class="text-xs font-semibold uppercase tracking-wide text-zinc-500">{@label}</div>
      <div class="mt-1 text-sm text-zinc-200">{@value}</div>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:empty, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:columns, :list, required: true)

  defp simple_table(assigns) do
    ~H"""
    <section class="rounded-lg border border-zinc-700 bg-zinc-800">
      <div class="border-b border-zinc-700 px-4 py-3">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">{@title}</h2>
      </div>
      <div :if={@rows == []} class="px-4 py-6 text-sm text-zinc-400">{@empty}</div>
      <div :if={@rows != []} class="overflow-x-auto">
        <table class="w-full">
          <thead>
            <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
              <th :for={column <- @columns} class={column_header_class(column)}>{column_label(column)}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class="border-b border-zinc-700/60 last:border-0">
              <td :for={column <- @columns} class={column_value_class(column)}>
                {column_value(row, column)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp parse_tab("damage"), do: :damage
  defp parse_tab("failures"), do: :failures
  defp parse_tab("deaths"), do: :deaths
  defp parse_tab("interrupts"), do: :interrupts
  defp parse_tab(_tab), do: :overview

  defp normalize_failure_preview(nil),
    do: %{mechanics: [], diagnostics: [], counts: %{failures: 0}}

  defp normalize_failure_preview(failure_preview) do
    failure_preview
    |> Map.put_new(:mechanics, [])
    |> Map.put_new(:diagnostics, [])
    |> Map.put_new(:counts, %{})
  end

  defp empty_document?(document) do
    counts = document.counts || %{}

    (counts.deaths || 0) == 0 and
      (counts.players || 0) == 0 and
      (document.roster || []) == [] and
      (document.deaths || []) == [] and
      (document.pull_review.damage_done || []) == [] and
      (document.failure_preview.mechanics || []) == [] and
      (document.interrupt_coverage.spell_coverage || []) == []
  end

  defp missed_interrupt_count(nil), do: 0

  defp missed_interrupt_count(interrupt_coverage) do
    interrupt_coverage.spell_coverage
    |> Enum.map(&(&1.missed_opportunities || 0))
    |> Enum.sum()
  end

  defp total_damage_done(rows) do
    rows
    |> Enum.map(&(&1.total_damage || 0))
    |> Enum.sum()
  end

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp format_datetime(value) when is_binary(value), do: value
  defp format_datetime(_value), do: "Unknown"

  defp format_value(nil), do: "Unknown"
  defp format_value(value), do: to_string(value)

  defp format_role(nil), do: "Unknown"
  defp format_role(role), do: role |> to_string() |> String.capitalize()

  defp format_class(nil), do: "Unknown"
  defp format_class(class_id), do: WeGoNext.WowClass.class_name(class_id) || "Unknown"

  defp player_class_style(nil), do: nil
  defp player_class_style(class_id), do: "color: #{WeGoNext.WowClass.class_color(class_id)}"

  defp format_mechanic_type(nil), do: "Unknown"

  defp format_mechanic_type(type) do
    type
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp plural(1), do: ""
  defp plural(_count), do: "s"

  defp stat_class(:danger), do: "border-red-800/70 bg-red-950/30"
  defp stat_class(:warning), do: "border-yellow-800/70 bg-yellow-950/30"
  defp stat_class(:ok), do: "border-green-800/70 bg-green-950/30"
  defp stat_class(_tone), do: "border-zinc-700 bg-zinc-800"

  defp column_header_class(column) when column in [:dps, :total_damage, :median_share],
    do: "px-4 py-2 text-right"

  defp column_header_class(_column), do: "px-4 py-2"

  defp column_value_class(column) when column in [:dps, :total_damage, :median_share],
    do: "px-4 py-3 text-right font-mono text-sm text-zinc-300"

  defp column_value_class(_column), do: "px-4 py-3 text-sm text-zinc-300"

  defp column_label(:player), do: "Player"
  defp column_label(:role), do: "Role"
  defp column_label(:dps), do: "DPS"
  defp column_label(:total_damage), do: "Total"
  defp column_label(:median_share), do: "Median Share"

  defp column_value(row, :player), do: row.player_name || row.player_guid || "Unknown"
  defp column_value(row, :role), do: format_role(row.detected_role)
  defp column_value(row, :dps), do: format_number(row.dps)
  defp column_value(row, :total_damage), do: format_number(row.total_damage)
  defp column_value(row, :median_share), do: "#{row.percent_of_median || 0}%"

  defp not_found_message(:missing_document, source_encounter_key) do
    "No public encounter document exists for source key #{source_encounter_key}."
  end

  defp not_found_message(reason, source_encounter_key) do
    "Could not read public encounter document #{source_encounter_key}: #{inspect(reason)}"
  end
end
