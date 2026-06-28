defmodule WeGoNextWeb.PublicLive.EncounterFailures do
  use WeGoNextWeb, :live_view

  alias WeGoNext.Gold.PublicReadModels

  @impl true
  def mount(
        %{"slug" => slug, "source_encounter_key" => source_encounter_key},
        %{"public_report_id" => report_id},
        socket
      ) do
    case PublicReadModels.encounter_failures(report_id, source_encounter_key) do
      {:ok, breakdown} ->
        {:ok,
         socket
         |> assign(:page_title, breakdown.encounter.name)
         |> assign(:slug, slug)
         |> assign(:breakdown, breakdown)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> assign(:page_title, "Encounter Not Found")
         |> assign(:slug, slug)
         |> assign(:breakdown, nil)}
    end
  end

  @impl true
  def render(%{breakdown: nil} = assigns) do
    ~H"""
    <div class="space-y-6">
      <.link navigate={~p"/r/#{@slug}"} class="text-sm text-zinc-400 hover:text-zinc-200">
        Back to encounters
      </.link>
      <div class="rounded-lg border border-zinc-700 bg-zinc-800 p-8 text-center">
        <h1 class="text-xl font-semibold text-zinc-100">Encounter Not Found</h1>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <header class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <.link navigate={~p"/r/#{@slug}"} class="text-sm text-zinc-400 hover:text-zinc-200">
            Back to encounters
          </.link>
          <h1 class="mt-3 text-2xl font-bold text-wow-gold">{@breakdown.encounter.name}</h1>
          <p class="mt-1 text-sm text-zinc-400">
            {format_value(@breakdown.encounter.difficulty_name)} · {format_datetime(@breakdown.encounter.start_time)}
          </p>
        </div>
      </header>

      <section class="grid gap-4 sm:grid-cols-4">
        <div class="stat-block">
          <div class="stat-value">{@breakdown.counts.failure_count}</div>
          <div class="stat-label">Failures</div>
        </div>
        <div class="stat-block">
          <div class="stat-value">{@breakdown.counts.failing_player_count}</div>
          <div class="stat-label">Players</div>
        </div>
        <div class="stat-block">
          <div class="stat-value">{@breakdown.counts.criterion_count}</div>
          <div class="stat-label">Mechanics</div>
        </div>
        <div class="stat-block">
          <div class="stat-value">{format_total(@breakdown.counts.total_damage)}</div>
          <div class="stat-label">Damage</div>
        </div>
      </section>

      <div :if={@breakdown.player_groups == []} class="rounded-lg border border-zinc-700 bg-zinc-800 p-8 text-center">
        <p class="text-sm text-zinc-400">No mirrored failures exist for this encounter.</p>
      </div>

      <section :for={group <- @breakdown.player_groups} class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
        <div class="flex items-center justify-between gap-3">
          <div>
            <h2 class="font-semibold text-zinc-100">{group.player_name}</h2>
            <p class="text-xs text-zinc-500">{group.player_guid}</p>
          </div>
          <div class="text-right">
            <div class="font-mono text-lg text-wow-gold">{group.failure_count}</div>
            <div class="text-xs text-zinc-500">failures</div>
          </div>
        </div>

        <div class="mt-4 overflow-hidden rounded border border-zinc-700">
          <table class="min-w-full divide-y divide-zinc-700 text-sm">
            <thead class="bg-zinc-950 text-left text-xs uppercase tracking-wide text-zinc-500">
              <tr>
                <th class="px-4 py-2">Mechanic</th>
                <th class="px-4 py-2">Type</th>
                <th class="px-4 py-2 text-right">Failures</th>
                <th class="px-4 py-2 text-right">Damage</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={failure <- group.failures}>
                <td class="px-4 py-2 text-zinc-100">{failure.spell_name}</td>
                <td class="px-4 py-2 text-zinc-300">{format_mechanic_type(failure.mechanic_type)}</td>
                <td class="px-4 py-2 text-right font-mono text-zinc-100">{failure.failure_count}</td>
                <td class="px-4 py-2 text-right font-mono text-zinc-300">{format_total(failure.total_damage)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end

  defp format_datetime(nil), do: "Unknown"
  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  defp format_value(nil), do: "Unknown"
  defp format_value(value), do: to_string(value)

  defp format_total(value),
    do: value |> to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

  defp format_mechanic_type(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
