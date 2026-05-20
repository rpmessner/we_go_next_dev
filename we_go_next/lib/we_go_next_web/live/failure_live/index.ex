defmodule WeGoNextWeb.FailureLive.Index do
  @moduledoc """
  Cross-encounter mechanic failure dashboard backed by gold facts.
  """

  use WeGoNextWeb, :live_view

  alias WeGoNext.Gold.FailureSummary

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Mechanic Failures")
     |> assign(:filters, %{start_date: nil, end_date: nil})
     |> assign(:filter_values, %{"start_date" => "", "end_date" => ""})
     |> assign(:rows, [])
     |> assign(:player_groups, [])
     |> assign(:readiness, FailureSummary.readiness())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)
    rows = FailureSummary.list_grouped_failures(filters)
    readiness = FailureSummary.readiness(filters)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_values, filter_values(filters))
     |> assign(:rows, rows)
     |> assign(:player_groups, FailureSummary.group_by_player(rows))
     |> assign(:readiness, readiness)}
  end

  @impl true
  def handle_event("filter", %{"filters" => filter_params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/failures?#{clean_filter_params(filter_params)}")}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/failures")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <.back navigate={~p"/"}>Back to encounters</.back>
          <h1 class="mt-3 text-2xl font-bold text-wow-gold">Mechanic Failures</h1>
          <p class="mt-1 text-sm text-zinc-400">
            Cross-encounter failure totals from gold facts.
          </p>
        </div>

        <.link navigate={~p"/settings"} class="text-sm text-zinc-400 hover:text-zinc-200">
          Settings
        </.link>
      </div>

      <section class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
        <form phx-submit="filter" class="grid gap-3 sm:grid-cols-[1fr_1fr_auto_auto] sm:items-end">
          <div>
            <label for="failure-start-date" class="block text-xs font-medium uppercase tracking-wide text-zinc-500">
              Start Date
            </label>
            <input
              id="failure-start-date"
              name="filters[start_date]"
              type="date"
              value={@filter_values["start_date"]}
              class="mt-1 w-full rounded border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-100"
            />
          </div>

          <div>
            <label for="failure-end-date" class="block text-xs font-medium uppercase tracking-wide text-zinc-500">
              End Date
            </label>
            <input
              id="failure-end-date"
              name="filters[end_date]"
              type="date"
              value={@filter_values["end_date"]}
              class="mt-1 w-full rounded border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-100"
            />
          </div>

          <button
            type="submit"
            class="rounded bg-wow-gold px-4 py-2 text-sm font-semibold text-zinc-950 hover:bg-yellow-300"
          >
            Apply
          </button>

          <button
            type="button"
            phx-click="clear_filters"
            class="rounded border border-zinc-700 px-4 py-2 text-sm text-zinc-300 hover:bg-zinc-700"
          >
            Clear
          </button>
        </form>
      </section>

      <section class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
        <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-300">
              Data Readiness
            </h2>
            <p class="mt-1 text-sm text-zinc-500">
              {readiness_ruleset_label(@readiness.active_ruleset)}
            </p>
          </div>
          <div class="grid grid-cols-2 gap-2 text-right text-xs text-zinc-500 sm:grid-cols-4">
            <div>
              <div class="font-mono text-base text-zinc-100">
                {@readiness.active_promoted_snapshots_count}
              </div>
              <div>criteria</div>
            </div>
            <div>
              <div class="font-mono text-base text-zinc-100">
                {@readiness.scoped_encounters_count}
              </div>
              <div>encounters</div>
            </div>
            <div>
              <div class="font-mono text-base text-zinc-100">
                {@readiness.matching_silver_observation_count}
              </div>
              <div>silver rows</div>
            </div>
            <div>
              <div class="font-mono text-base text-zinc-100">
                {@readiness.selected_fact_count}
              </div>
              <div>facts</div>
            </div>
          </div>
        </div>

        <div :if={@readiness.diagnostics == []} class="mt-4 rounded border border-emerald-700/60 bg-emerald-950/30 px-3 py-2 text-sm text-emerald-100">
          Failures data is ready for the current filters.
        </div>

        <div :if={@readiness.diagnostics != []} class="mt-4 space-y-2">
          <div
            :for={diagnostic <- @readiness.diagnostics}
            class={diagnostic_class(diagnostic.severity)}
          >
            <div class="flex flex-col gap-1 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <div class="font-medium text-zinc-100">{diagnostic.title}</div>
                <p class="mt-1 text-sm text-zinc-300">{diagnostic.body}</p>
              </div>
              <span class={diagnostic_badge_class(diagnostic.severity)}>
                {diagnostic_label(diagnostic.severity)}
              </span>
            </div>
          </div>
        </div>
      </section>

      <section class="grid gap-4 sm:grid-cols-3">
        <div class="stat-block">
          <div class="stat-value">{total_failures(@rows)}</div>
          <div class="stat-label">Failures</div>
        </div>
        <div class="stat-block">
          <div class="stat-value">{length(@player_groups)}</div>
          <div class="stat-label">Players</div>
        </div>
        <div class="stat-block">
          <div class="stat-value">{format_number(total_damage(@rows))}</div>
          <div class="stat-label">Damage</div>
        </div>
      </section>

      <div :if={@player_groups == []} class="rounded-lg border border-zinc-700 bg-zinc-800 p-8 text-center">
        <p class="text-sm text-zinc-400">
          No mechanic failures found for this date range. Check data readiness above for the likely reason.
        </p>
      </div>

      <section :for={group <- @player_groups} class="rounded-lg border border-zinc-700 bg-zinc-800">
        <div class="flex flex-col gap-1 border-b border-zinc-700 px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 class="text-lg font-semibold text-zinc-100">{group.player_name}</h2>
            <p class="text-xs font-mono text-zinc-500">{group.player_guid}</p>
          </div>
          <div class="text-sm text-zinc-400">
            <span class="font-semibold text-zinc-100">{group.failure_count}</span>
            failures
            <span :if={group.total_damage > 0}>
              &bull; {format_number(group.total_damage)} damage
            </span>
          </div>
        </div>

        <div class="overflow-x-auto">
          <table class="w-full">
            <thead>
              <tr class="border-b border-zinc-700 text-left text-xs uppercase tracking-wide text-zinc-500">
                <th class="px-4 py-2">Mechanic</th>
                <th class="px-4 py-2">Type</th>
                <th class="px-4 py-2 text-right">Failures</th>
                <th class="px-4 py-2 text-right">Damage</th>
                <th class="px-4 py-2 text-right">Encounters</th>
                <th class="px-4 py-2">Latest</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={failure <- group.failures} class="border-b border-zinc-700/60 last:border-0">
                <td class="px-4 py-3">
                  <div class="font-medium text-zinc-100">{failure.spell_name}</div>
                  <div class="text-xs text-zinc-500">
                    Spell {failure.spell_id}
                    <span :if={failure.boss_name}> &bull; {failure.boss_name}</span>
                  </div>
                </td>
                <td class="px-4 py-3 text-sm text-zinc-300">{format_mechanic_type(failure.mechanic_type)}</td>
                <td class="px-4 py-3 text-right font-mono text-wow-death">{failure.failure_count}</td>
                <td class="px-4 py-3 text-right font-mono text-zinc-300">{format_number(failure.total_damage)}</td>
                <td class="px-4 py-3 text-right font-mono text-zinc-300">{failure.encounter_count}</td>
                <td class="px-4 py-3 text-sm text-zinc-400">{format_date_time(failure.latest_start_time)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end

  defp parse_filters(params) do
    if has_date_filter?(params) do
      %{}
    else
      FailureSummary.default_filters()
    end
    |> maybe_put_date(:start_date, Map.get(params, "start_date"))
    |> maybe_put_date(:end_date, Map.get(params, "end_date"))
  end

  defp has_date_filter?(params) do
    date_filter_present?(params, "start_date") or date_filter_present?(params, "end_date")
  end

  defp date_filter_present?(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) -> String.trim(value) != ""
      _value -> false
    end
  end

  defp maybe_put_date(filters, _key, value) when value in [nil, ""], do: filters

  defp maybe_put_date(filters, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(filters, key, date)
      {:error, _reason} -> filters
    end
  end

  defp filter_values(filters) do
    %{
      "start_date" => format_date_input(Map.get(filters, :start_date)),
      "end_date" => format_date_input(Map.get(filters, :end_date))
    }
  end

  defp clean_filter_params(params) do
    params
    |> Enum.filter(fn {_key, value} -> is_binary(value) and String.trim(value) != "" end)
    |> Map.new()
  end

  defp format_date_input(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date_input(_date), do: ""

  defp total_failures(rows), do: rows |> Enum.map(& &1.failure_count) |> Enum.sum()
  defp total_damage(rows), do: rows |> Enum.map(& &1.total_damage) |> Enum.sum()

  defp readiness_ruleset_label(nil), do: "No active ruleset."

  defp readiness_ruleset_label(%{name: name, version: version}) do
    "Active ruleset: #{name} v#{version}."
  end

  defp diagnostic_class(:blocked) do
    "rounded border border-red-700/70 bg-red-950/30 px-3 py-2"
  end

  defp diagnostic_class(:warning) do
    "rounded border border-yellow-700/70 bg-yellow-950/30 px-3 py-2"
  end

  defp diagnostic_class(:info) do
    "rounded border border-sky-700/70 bg-sky-950/30 px-3 py-2"
  end

  defp diagnostic_badge_class(:blocked) do
    "inline-flex self-start rounded border border-red-600/60 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide text-red-200"
  end

  defp diagnostic_badge_class(:warning) do
    "inline-flex self-start rounded border border-yellow-600/60 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide text-yellow-200"
  end

  defp diagnostic_badge_class(:info) do
    "inline-flex self-start rounded border border-sky-600/60 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide text-sky-200"
  end

  defp diagnostic_label(:blocked), do: "Blocked"
  defp diagnostic_label(:warning), do: "Check"
  defp diagnostic_label(:info), do: "Note"

  defp format_mechanic_type(type) when is_binary(type) do
    type
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_mechanic_type(_type), do: "Unknown"

  defp format_date_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp format_date_time(_datetime), do: "Unknown"
end
