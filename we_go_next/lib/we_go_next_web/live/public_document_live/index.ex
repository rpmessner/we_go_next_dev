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

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:slug, slug)
     |> assign(:title, title)
     |> assign(:encounter_records, encounter_records)
     |> assign(:documents_state, documents_state)
     |> assign(:show_resets, false)
     |> assign(:open_menu_id, nil)}
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
      is_reset: false
    }
  end
end
