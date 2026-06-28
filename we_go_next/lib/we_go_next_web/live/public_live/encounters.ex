defmodule WeGoNextWeb.PublicLive.Encounters do
  use WeGoNextWeb, :live_view

  alias WeGoNext.Gold.PublicReadModels

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Public Encounters")
     |> assign(:slug, slug)
     |> assign(:encounters, PublicReadModels.list_encounters())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <header class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 class="text-2xl font-bold text-wow-gold">Public Encounters</h1>
          <p class="mt-1 text-sm text-zinc-400">Mirrored gold failure summaries.</p>
        </div>
        <.link navigate={~p"/r/#{@slug}/failures"} class="text-sm text-zinc-400 hover:text-zinc-200">
          Failure Totals
        </.link>
      </header>

      <div :if={@encounters == []} class="rounded-lg border border-zinc-700 bg-zinc-800 p-8 text-center">
        <p class="text-sm text-zinc-400">No mirrored encounters have been published yet.</p>
      </div>

      <section :if={@encounters != []} class="overflow-hidden rounded-lg border border-zinc-700 bg-zinc-800">
        <table class="min-w-full divide-y divide-zinc-700 text-sm">
          <thead class="bg-zinc-950 text-left text-xs uppercase tracking-wide text-zinc-500">
            <tr>
              <th class="px-4 py-3">Encounter</th>
              <th class="px-4 py-3">Started</th>
              <th class="px-4 py-3 text-right">Failures</th>
              <th class="px-4 py-3 text-right">Players</th>
              <th class="px-4 py-3 text-right">Damage</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-700">
            <tr :for={encounter <- @encounters}>
              <td class="px-4 py-3">
                <.link
                  navigate={~p"/r/#{@slug}/encounters/#{encounter.source_encounter_key}"}
                  class="font-medium text-zinc-100 hover:text-wow-gold"
                >
                  {encounter.name}
                </.link>
                <div class="mt-1 text-xs text-zinc-500">
                  {format_value(encounter.difficulty_name)} · {result_label(encounter.success)}
                </div>
              </td>
              <td class="px-4 py-3 text-zinc-300">{format_datetime(encounter.start_time)}</td>
              <td class="px-4 py-3 text-right font-mono text-zinc-100">{encounter.failure_count}</td>
              <td class="px-4 py-3 text-right font-mono text-zinc-300">{encounter.failing_player_count}</td>
              <td class="px-4 py-3 text-right font-mono text-zinc-300">{format_total(encounter.total_damage)}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end

  defp result_label(true), do: "Kill"
  defp result_label(false), do: "Wipe"
  defp result_label(_), do: "Unknown"

  defp format_datetime(nil), do: "Unknown"
  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  defp format_value(nil), do: "Unknown"
  defp format_value(value), do: to_string(value)

  defp format_total(value),
    do: value |> to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
end
