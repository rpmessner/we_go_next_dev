defmodule WeGoNextWeb.EncounterLive.Index do
  @moduledoc """
  LiveView for the encounter list / home page.

  Handles log file selection/import and renders the encounter list from
  generated encounter documents. Per-log management (publish, reimport,
  Warcraft Logs links) lives at `/logs` (`WeGoNextWeb.LogLive.Index`).
  """
  use WeGoNextWeb, :live_view

  alias WeGoNext.{
    Accounts,
    CombatLogFile,
    Documents,
    FileWatcher,
    Importer,
    ImportWorker,
    Repo
  }

  alias WeGoNext.Gold.DimEncounter

  alias WeGoNextWeb.Components.{EncounterList, LogSelector}
  import Ecto.Query

  # ============================================================================
  # Mount
  # ============================================================================

  @impl true
  def mount(_params, _session, socket) do
    user = Accounts.get_or_create_default_user()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")
      Phoenix.PubSub.subscribe(WeGoNext.PubSub, ImportWorker.progress_topic(user.id))
    end

    {encounter_records, documents_state} = document_records()

    log_files =
      case Accounts.list_combat_logs(user) do
        {:ok, files} -> files
        {:error, _} -> []
      end

    imported_logs = list_imported_logs(user.id)

    selector_logs = selector_logs(log_files, imported_logs)
    filter_log_id = default_filter_log_id(imported_logs)

    selected_log =
      case imported_logs do
        [%{file_path: path} | _rest] -> path
        [] -> if(length(selector_logs) == 1, do: hd(selector_logs).full_path, else: "all")
      end

    {loading, import_progress, selected_log} =
      case ImportWorker.get_status(user.id) do
        %{status: :importing, path: path} ->
          {true, %{percent: 0, encounters_found: 0, status: :parsing}, path}

        _ ->
          {false, nil, selected_log}
      end

    {:ok,
     socket
     |> assign(:page_title, "Encounters")
     |> assign(:user, user)
     |> assign(:documents_state, documents_state)
     |> assign(:show_resets, false)
     |> assign(:sort_direction, :asc)
     |> assign(:open_menu_id, nil)
     |> assign(:log_files, log_files)
     |> assign(:selector_logs, selector_logs)
     |> assign(:imported_logs, imported_logs)
     |> assign(:watch_log, newest_watchable_log(imported_logs))
     |> assign(:filter_log_id, filter_log_id)
     |> assign(
       :encounter_records,
       filter_records(encounter_records, filter_log_id, imported_logs)
     )
     |> assign(:selected_log, selected_log)
     |> assign(:import_enabled, import_enabled?(selected_log, imported_logs))
     |> assign(:loading, loading)
     |> assign(:error, nil)
     |> assign(:import_progress, import_progress)}
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("select_log", params, socket) do
    path = params["log_path"]

    filter_log_id = filter_id_for_path(path, socket.assigns.imported_logs)

    {:noreply,
     socket
     |> assign(:selected_log, path)
     |> assign(:filter_log_id, filter_log_id)
     |> assign(:import_enabled, import_enabled?(path, socket.assigns.imported_logs))
     |> assign_document_records()}
  end

  @impl true
  def handle_event("import_log", %{"log_path" => path}, socket) do
    path = String.trim(path)

    if path == "" do
      {:noreply, assign(socket, :error, "Please select a log file")}
    else
      do_import(socket, path)
    end
  end

  @impl true
  def handle_event("toggle_menu", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    current = socket.assigns.open_menu_id

    new_id = if current == id, do: nil, else: id
    {:noreply, assign(socket, :open_menu_id, new_id)}
  end

  @impl true
  def handle_event("close_menu", _params, socket) do
    {:noreply, assign(socket, :open_menu_id, nil)}
  end

  @impl true
  def handle_event("toggle_reset", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)

    case Importer.toggle_reset(id) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign_document_records()
         |> assign(:open_menu_id, nil)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle reset status")}
    end
  end

  @impl true
  def handle_event("toggle_show_resets", _params, socket) do
    {:noreply, assign(socket, :show_resets, not socket.assigns.show_resets)}
  end

  @impl true
  def handle_event("toggle_sort_direction", _params, socket) do
    direction = if socket.assigns.sort_direction == :asc, do: :desc, else: :asc

    {:noreply,
     socket
     |> assign(:sort_direction, direction)
     |> push_event("store_session_preference", %{
       key: "encounter_sort_direction",
       value: Atom.to_string(direction)
     })}
  end

  @impl true
  def handle_event(
        "restore_session_preferences",
        %{"encounter_sort_direction" => direction},
        socket
      )
      when direction in ["asc", "desc"] do
    {:noreply, assign(socket, :sort_direction, String.to_existing_atom(direction))}
  end

  def handle_event("restore_session_preferences", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_watch_enabled", %{"file_id" => file_id}, socket) do
    with {file_id, ""} <- Integer.parse(file_id),
         %CombatLogFile{source: :live} = combat_log_file <-
           Repo.get_by(CombatLogFile, id: file_id, user_id: socket.assigns.user.id),
         :ok <- toggle_watching(combat_log_file) do
      imported_logs = list_imported_logs(socket.assigns.user.id)

      {:noreply,
       socket
       |> assign(:imported_logs, imported_logs)
       |> assign(:watch_log, newest_watchable_log(imported_logs))
       |> assign_selector_logs()}
    else
      _reason -> {:noreply, put_flash(socket, :error, "Failed to update watch setting")}
    end
  end

  # ============================================================================
  # Info Handlers (PubSub)
  # ============================================================================

  @impl true
  def handle_info({:import_complete, result}, socket) do
    case result do
      {:ok, count} ->
        imported_logs = list_imported_logs(socket.assigns.user.id)

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:import_progress, nil)
         |> assign(:imported_logs, imported_logs)
         |> assign(:watch_log, newest_watchable_log(imported_logs))
         |> assign_filter_for_path(socket.assigns.selected_log)
         |> assign_document_records()
         |> assign_selector_logs()
         |> assign(:import_enabled, true)
         |> put_flash(:info, "Imported #{count} encounters")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:import_progress, nil)
         |> assign(:error, "Failed to import log: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:encounters_loaded, _count}, socket) do
    {:noreply, assign_document_records(socket)}
  end

  @impl true
  def handle_info({:import_progress, :saving}, socket) do
    {:noreply,
     assign(socket, :import_progress, %{
       percent: 100,
       encounters_found: socket.assigns.import_progress[:encounters_found] || 0,
       status: :saving
     })}
  end

  @impl true
  def handle_info(
        {:import_progress, %{bytes_read: bytes, total_bytes: total, encounters_found: found}},
        socket
      ) do
    percent = if total > 0, do: round(bytes / total * 100), else: 0
    prev_found = socket.assigns.import_progress[:encounters_found] || 0

    socket =
      if found > prev_found do
        imported_logs = list_imported_logs(socket.assigns.user.id)

        socket
        |> assign_document_records()
        |> assign(:imported_logs, imported_logs)
        |> assign(:watch_log, newest_watchable_log(imported_logs))
        |> assign_selector_logs()
      else
        socket
      end

    {:noreply,
     assign(socket, :import_progress, %{
       percent: percent,
       encounters_found: found,
       status: :parsing
     })}
  end

  @impl true
  def handle_info({:log_rotated, new_clf, count}, socket) do
    imported_logs = list_imported_logs(socket.assigns.user.id)

    {:noreply,
     socket
     |> assign_document_records()
     |> assign(:log_files, reload_log_files(socket.assigns.user))
     |> assign(:imported_logs, imported_logs)
     |> assign(:watch_log, newest_watchable_log(imported_logs))
     |> assign_selector_logs()
     |> put_flash(
       :info,
       "Log rotation detected! Switched to #{Path.basename(new_clf.file_path)} (#{count} encounters)"
     )}
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div id="encounter-index" phx-hook="SessionPreferences" class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-wow-gold">WoW Raid Diagnostic Tool</h1>
        <div class="flex items-center gap-4">
          <.link navigate={~p"/logs"} class="text-sm text-zinc-400 hover:text-zinc-200">
            Logs
          </.link>
          <.link navigate={~p"/failures"} class="text-sm text-zinc-400 hover:text-zinc-200">
            Failures
          </.link>
          <.link navigate={~p"/settings"} class="text-sm text-zinc-400 hover:text-zinc-200">
            Settings
          </.link>
        </div>
      </div>

      <LogSelector.render
        user={@user}
        log_files={@selector_logs}
        selected_log={@selected_log}
        import_enabled={@import_enabled}
        loading={@loading}
        import_progress={@import_progress}
        error={@error}
        watch_log={@watch_log}
      />

      <EncounterList.render
        encounter_records={@encounter_records}
        show_resets={@show_resets}
        sort_direction={@sort_direction}
        show_sort_control={true}
        open_menu_id={@open_menu_id}
        is_admin={@user.is_admin}
        log_files={@log_files}
        loading={@loading}
      />

      <section
        :if={@encounter_records == [] && !@loading && @documents_state == :empty}
        class="rounded-lg border border-zinc-700 bg-zinc-800 p-6"
      >
        <h2 class="text-lg font-semibold text-zinc-100">No Encounter Documents</h2>
        <p class="mt-2 text-sm text-zinc-400">
          No generated encounter documents exist in the configured document store. Import or rebuild pulls to write
          <span class="font-mono text-zinc-300">index.json</span>
          and
          <span class="font-mono text-zinc-300">encounters/*.json</span>
          before the local detail UI can render them.
        </p>
      </section>

      <section
        :if={@encounter_records == [] && !@loading && match?({:error, _reason}, @documents_state)}
        class="rounded-lg border border-red-800/70 bg-red-950/30 p-6"
      >
        <h2 class="text-lg font-semibold text-red-100">Document Store Unavailable</h2>
        <p class="mt-2 text-sm text-red-200">
          The encounter document index could not be read from the configured store:
          <span class="font-mono">{inspect(elem(@documents_state, 1))}</span>
        </p>
      </section>
    </div>
    """
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp do_import(socket, path) do
    Accounts.set_last_loaded_log(socket.assigns.user, path)
    user_id = socket.assigns.user.id

    case ImportWorker.start_import(user_id, path, force_reimport: false) do
      :ok ->
        {:noreply,
         socket
         |> assign(:loading, true)
         |> assign(:error, nil)
         |> assign(:selected_log, path)
         |> assign(:import_progress, %{percent: 0, encounters_found: 0, status: :parsing})}

      {:already_importing, existing_path} ->
        {:noreply,
         socket
         |> assign(:error, "Already importing #{Path.basename(existing_path)}")}
    end
  end

  defp reload_log_files(user) do
    case Accounts.list_combat_logs(user) do
      {:ok, files} -> files
      {:error, _} -> []
    end
  end

  defp toggle_watching(%CombatLogFile{watch_enabled: true} = combat_log_file) do
    with {:ok, _combat_log_file} <-
           combat_log_file
           |> CombatLogFile.changeset(%{watch_enabled: false})
           |> Repo.update() do
      case FileWatcher.current_file() do
        %CombatLogFile{id: id} when id == combat_log_file.id -> FileWatcher.stop_watching()
        _other -> :ok
      end

      :ok
    end
  end

  defp toggle_watching(%CombatLogFile{watch_enabled: false} = combat_log_file) do
    FileWatcher.watch(combat_log_file)
  end

  defp assign_selector_logs(socket) do
    assign(
      socket,
      :selector_logs,
      selector_logs(socket.assigns.log_files, socket.assigns.imported_logs)
    )
  end

  defp selector_logs(log_files, imported_logs) do
    imported_paths = MapSet.new(imported_logs, & &1.file_path)

    imported_options =
      Enum.map(imported_logs, fn log ->
        %{
          full_path: log.file_path,
          filename: Path.basename(log.file_path),
          imported: true,
          filename_datetime: CombatLogFile.filename_datetime(log.file_path),
          encounter_count: log.encounter_count,
          first_encounter_start_at: log.first_encounter_start_at
        }
      end)

    discovered_options =
      log_files
      |> Enum.reject(&MapSet.member?(imported_paths, &1.full_path))
      |> Enum.map(&Map.put(&1, :imported, false))

    (imported_options ++ discovered_options)
    |> Enum.sort_by(&selector_log_order_key/1, :desc)
  end

  defp selector_log_order_key(log) do
    datetime = log.filename_datetime
    {if(datetime, do: NaiveDateTime.to_erl(datetime), else: {{0, 1, 1}, {0, 0, 0}}), log.filename}
  end

  defp assign_document_records(socket) do
    {records, state} = document_records()

    socket
    |> assign(
      :encounter_records,
      filter_records(records, socket.assigns.filter_log_id, socket.assigns.imported_logs)
    )
    |> assign(:documents_state, state)
  end

  defp default_filter_log_id([%{id: id} | _rest]), do: id
  defp default_filter_log_id([]), do: :all

  defp filter_id_for_path("all", _imported_logs), do: :all

  defp filter_id_for_path(path, imported_logs) do
    case Enum.find(imported_logs, &(&1.file_path == path)) do
      %{id: id} -> id
      nil -> :none
    end
  end

  defp import_enabled?("all", _imported_logs), do: false
  defp import_enabled?(nil, _imported_logs), do: false

  defp import_enabled?(_path, _imported_logs), do: true

  defp assign_filter_for_path(socket, path) do
    case Enum.find(socket.assigns.imported_logs, &(&1.file_path == path)) do
      %{id: id} -> assign(socket, :filter_log_id, id)
      nil -> socket
    end
  end

  defp filter_records(records, :all, _imported_logs), do: records
  defp filter_records(_records, :none, _imported_logs), do: []

  defp filter_records(records, log_id, imported_logs) do
    case Enum.find(imported_logs, &(&1.id == log_id)) do
      %{file_path: file_path} ->
        keys = log_source_keys(file_path)
        Enum.filter(records, &MapSet.member?(keys, &1.source_encounter_key))

      nil ->
        records
    end
  end

  defp log_source_keys(file_path) do
    DimEncounter
    |> where([d], d.source_file_path == ^file_path)
    |> select([d], d.source_encounter_key)
    |> Repo.all()
    |> MapSet.new()
  end

  defp document_records do
    case Documents.list_index() do
      {:ok, %{encounters: encounters}} when encounters != [] ->
        records =
          encounters
          |> Enum.map(&document_index_record/1)
          |> Enum.sort_by(&{encounter_timestamp(&1.start_time), &1.source_encounter_key}, :asc)

        {records, :ready}

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

  defp encounter_timestamp(%DateTime{} = start_time),
    do: DateTime.to_unix(start_time, :microsecond)

  defp encounter_timestamp(%NaiveDateTime{} = start_time),
    do: NaiveDateTime.diff(start_time, ~N[1970-01-01 00:00:00], :microsecond)

  defp encounter_timestamp(_start_time), do: 0

  defp list_imported_logs(user_id) do
    CombatLogFile
    |> where([clf], clf.user_id == ^user_id)
    |> join(:left, [clf], e in WeGoNext.Encounters.Encounter, on: e.combat_log_file_id == clf.id)
    |> group_by([clf], clf.id)
    |> select([clf, e], %{
      id: clf.id,
      file_path: clf.file_path,
      last_parsed_at: clf.last_parsed_at,
      encounter_count: count(e.id),
      first_encounter_start_at: min(e.start_time),
      source: clf.source,
      file_mtime: clf.file_mtime,
      watch_enabled: clf.watch_enabled
    })
    |> order_by([clf, e], desc_nulls_last: min(e.start_time), desc: clf.last_parsed_at)
    |> Repo.all()
  end

  defp newest_watchable_log(imported_logs) do
    imported_logs
    |> Enum.filter(&(&1.source == :live))
    |> Enum.max_by(
      fn log ->
        datetime = CombatLogFile.filename_datetime(log.file_path)
        {if(datetime, do: NaiveDateTime.to_erl(datetime), else: {{0, 1, 1}, {0, 0, 0}}), log.id}
      end,
      fn -> nil end
    )
  end
end
