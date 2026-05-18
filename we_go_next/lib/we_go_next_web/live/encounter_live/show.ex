defmodule WeGoNextWeb.EncounterLive.Show do
  @moduledoc """
  Medallion encounter detail shell keyed by `gold.dim_encounter.id`.

  This route intentionally reads only gold/silver read models. It must not call
  legacy analyzers, analyzer cache output, or `public.mechanic_criteria`.
  """

  use WeGoNextWeb, :live_view

  alias WeGoNext.Gold.EncounterDetail
  import WeGoNextWeb.EncounterComponents, only: [format_duration: 1]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case EncounterDetail.get(id) do
      {:ok, detail} ->
        {:ok,
         socket
         |> assign(:page_title, detail.encounter.name)
         |> assign(:detail, detail)
         |> assign(:encounter, detail.encounter)
         |> assign(:counts, detail.counts)}

      {:error, reason} ->
        {:ok,
         socket
         |> assign(:page_title, "Encounter Not Found")
         |> assign(:detail, nil)
         |> assign(:encounter, nil)
         |> assign(:counts, %{})
         |> assign(:error, not_found_message(reason))}
    end
  end

  @impl true
  def render(%{encounter: nil} = assigns) do
    ~H"""
    <div class="space-y-6">
      <.back navigate={~p"/"}>Back to encounters</.back>

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
      <div>
        <.back navigate={~p"/"}>Back to encounters</.back>
        <h1 class="mt-3 text-2xl font-bold text-wow-gold">{@encounter.name}</h1>
        <p class="mt-1 text-sm text-zinc-400">
          Medallion encounter detail keyed by gold encounter #{@encounter.id}.
        </p>
      </div>

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
          <.count_item label="Interrupts" value={@counts.interrupt_opportunities} />
          <.count_item label="Debuffs" value={@counts.debuff_applications} />
          <.count_item label="Failure Facts" value={@counts.failure_facts} />
        </div>
      </section>
    </div>
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

  defp format_value(nil), do: "Unknown"
  defp format_value(value), do: to_string(value)

  defp format_datetime(nil), do: "Unknown"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
  end

  defp not_found_message(:invalid_id), do: "Encounter IDs must be positive gold encounter IDs."
  defp not_found_message(:not_found), do: "No gold encounter exists for that ID."
end
