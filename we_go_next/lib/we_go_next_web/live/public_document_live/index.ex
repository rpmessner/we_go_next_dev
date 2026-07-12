defmodule WeGoNextWeb.PublicDocumentLive.Index do
  @moduledoc """
  Public encounter list rendered from uploaded encounter documents.
  """

  use WeGoNextWeb, :live_view

  alias WeGoNext.Documents
  alias WeGoNextWeb.Components.EncounterList

  @impl true
  def mount(%{"slug" => slug}, %{"public_report_title" => title}, socket) do
    {encounter_records, documents_state} = document_records()
    raid_nights = raid_nights(encounter_records)
    selected_raid_night_key = raid_nights |> List.first() |> then(&if(&1, do: &1.key, else: :all))

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:slug, slug)
     |> assign(:title, title)
     |> assign(:all_encounter_records, encounter_records)
     |> assign(:encounter_records, filter_records(encounter_records, selected_raid_night_key))
     |> assign(:raid_nights, raid_nights)
     |> assign(:selected_raid_night_key, selected_raid_night_key)
     |> assign(:documents_state, documents_state)
     |> assign(:show_resets, false)
     |> assign(:open_menu_id, nil)}
  end

  @impl true
  def handle_event("select_raid_night", %{"raid_night_key" => key}, socket) do
    selected_key = if key == "all", do: :all, else: key

    {:noreply,
     socket
     |> assign(:selected_raid_night_key, selected_key)
     |> assign(
       :encounter_records,
       filter_records(socket.assigns.all_encounter_records, selected_key)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p class="text-sm font-semibold uppercase tracking-wide text-zinc-500">Public Report</p>
          <h1 class="mt-1 text-2xl font-bold text-wow-gold">{@title}</h1>
        </div>
      </div>

      <form
        :if={@raid_nights != []}
        id="raid-night-selector"
        phx-change="select_raid_night"
        class="rounded-lg border border-zinc-700 bg-zinc-800 p-4"
      >
        <label for="raid-night-select" class="mb-2 block text-sm font-medium text-zinc-400">
          Raid Night
        </label>
        <select
          id="raid-night-select"
          name="raid_night_key"
          class="w-full rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-zinc-100 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
        >
          <option value="all" selected={@selected_raid_night_key == :all}>All raid nights</option>
          <option
            :for={raid_night <- @raid_nights}
            value={raid_night.key}
            selected={@selected_raid_night_key == raid_night.key}
          >
            {raid_night.name} ({raid_night.date})
          </option>
        </select>
      </form>

      <EncounterList.render
        encounter_records={@encounter_records}
        show_resets={@show_resets}
        open_menu_id={@open_menu_id}
        is_admin={false}
        log_files={[]}
        loading={false}
        base_path={~p"/r/#{@slug}"}
      />

      <section
        :if={@encounter_records == [] && @documents_state == :empty}
        class="rounded-lg border border-zinc-700 bg-zinc-800 p-6"
      >
        <h2 class="text-lg font-semibold text-zinc-100">No Uploaded Encounters</h2>
        <p class="mt-2 text-sm text-zinc-400">
          This report is enabled, but its public document index has no uploaded encounters yet.
        </p>
      </section>

      <section
        :if={@encounter_records == [] && match?({:error, _reason}, @documents_state)}
        class="rounded-lg border border-red-800/70 bg-red-950/30 p-6"
      >
        <h2 class="text-lg font-semibold text-red-100">Document Store Unavailable</h2>
        <p class="mt-2 text-sm text-red-200">
          The public encounter document index could not be read:
          <span class="font-mono">{inspect(elem(@documents_state, 1))}</span>
        </p>
      </section>
    </div>
    """
  end

  defp document_records do
    case Documents.list_index() do
      {:ok, %{encounters: encounters}} when encounters != [] ->
        {Enum.map(encounters, &document_index_record/1), :ready}

      {:ok, _index} ->
        {[], :empty}

      {:error, reason} ->
        {[], {:error, reason}}
    end
  end

  defp document_index_record(entry) do
    raid_night = Map.get(entry, :raid_night) || legacy_raid_night(entry.start_time)

    %{
      id: entry.source_encounter_key,
      source_encounter_key: entry.source_encounter_key,
      name: entry.boss || "Unknown Encounter",
      wow_encounter_id: entry.wow_encounter_id,
      difficulty_id: entry.difficulty_id,
      difficulty_name: entry.difficulty_name || "Unknown",
      instance_id: Map.get(entry, :instance_id),
      start_time: entry.start_time,
      end_time: entry.end_time,
      success: entry.success,
      fight_time_ms: entry.fight_time_ms,
      is_reset: false,
      raid_night: raid_night,
      raid_night_key: raid_night && raid_night.key
    }
  end

  defp raid_nights(records) do
    records
    |> Enum.map(& &1.raid_night)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.key)
    |> Enum.sort_by(&{&1.date || "", &1.key}, :desc)
  end

  defp filter_records(records, :all), do: records
  defp filter_records(records, key), do: Enum.filter(records, &(&1.raid_night_key == key))

  defp legacy_raid_night(%DateTime{} = datetime) do
    date = DateTime.to_date(datetime)

    %{
      key: "legacy-#{Date.to_iso8601(date)}",
      date: Date.to_iso8601(date),
      name: "Raid Night — #{Calendar.strftime(date, "%b %d, %Y")}"
    }
  end

  defp legacy_raid_night(_start_time), do: nil
end
