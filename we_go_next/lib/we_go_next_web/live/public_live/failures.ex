defmodule WeGoNextWeb.PublicLive.Failures do
  use WeGoNextWeb, :live_view

  alias WeGoNext.Gold.PublicReadModels

  @impl true
  def mount(%{"slug" => slug}, %{"public_report_id" => report_id}, socket) do
    rows = PublicReadModels.grouped_failures(report_id)
    encounters = PublicReadModels.list_encounters(report_id)

    {:ok,
     socket
     |> assign(:page_title, "Public Failure Totals")
     |> assign(:slug, slug)
     |> assign(:rows, rows)
     |> assign(:player_groups, PublicReadModels.group_by_player(rows))
     |> assign(:encounter_count, length(encounters))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <header class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <.link navigate={~p"/r/#{@slug}"} class="text-sm text-zinc-400 hover:text-zinc-200">
            Back to encounters
          </.link>
          <h1 class="mt-3 text-2xl font-bold text-wow-gold">Public Failure Totals</h1>
          <p class="mt-1 text-sm text-zinc-400">Cross-encounter mirrored gold facts.</p>
        </div>
      </header>

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
          <div class="stat-value">{@encounter_count}</div>
          <div class="stat-label">Encounters</div>
        </div>
      </section>

      <div :if={@player_groups == []} class="rounded-lg border border-zinc-700 bg-zinc-800 p-8 text-center">
        <p class="text-sm text-zinc-400">No mirrored failures have been published yet.</p>
      </div>

      <section :for={group <- @player_groups} class="rounded-lg border border-zinc-700 bg-zinc-800 p-4">
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
                <th class="px-4 py-2">Boss</th>
                <th class="px-4 py-2 text-right">Failures</th>
                <th class="px-4 py-2 text-right">Damage</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={failure <- group.failures}>
                <td class="px-4 py-2 text-zinc-100">{failure.spell_name}</td>
                <td class="px-4 py-2 text-zinc-300">{format_value(failure.boss_name)}</td>
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

  defp total_failures(rows), do: rows |> Enum.map(& &1.failure_count) |> Enum.sum()
  defp format_value(nil), do: "Unknown"
  defp format_value(value), do: to_string(value)

  defp format_total(value),
    do: value |> to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
end
