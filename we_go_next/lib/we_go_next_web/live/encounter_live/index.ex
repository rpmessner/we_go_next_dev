defmodule WeGoNextWeb.EncounterLive.Index do
  @moduledoc """
  LiveView for the encounter list / home page.

  Handles:
  - Log file selection and import
  - Switching between imported logs
  - Displaying encounter list
  - Real-time updates via PubSub
  """
  use WeGoNextWeb, :live_view

  alias WeGoNext.{
    Accounts,
    CombatLogFile,
    Documents,
    EncounterStore,
    Importer,
    ImportWorker,
    Repo,
    WarcraftLogs
  }

  alias WeGoNextWeb.Components.{LogSelector, ImportedLogsSwitcher, EncounterList}
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
    log_path = EncounterStore.current_log_path()
    combat_log_file = EncounterStore.current_combat_log_file()

    log_files =
      case Accounts.list_combat_logs(user) do
        {:ok, files} -> files
        {:error, _} -> []
      end

    imported_logs = list_imported_logs(user.id)

    unimported_log_files = unimported_log_files(log_files, imported_logs)

    selected_log =
      case unimported_log_files do
        [single_log] -> single_log.full_path
        _ -> nil
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
     |> assign(:encounter_records, encounter_records)
     |> assign(:documents_state, documents_state)
     |> assign(:show_resets, false)
     |> assign(:open_menu_id, nil)
     |> assign(:log_path, log_path)
     |> assign(:combat_log_file, combat_log_file)
     |> assign(:log_files, log_files)
     |> assign(:unimported_log_files, unimported_log_files)
     |> assign(:imported_logs, imported_logs)
     |> assign(:selected_log, selected_log)
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
    {:noreply, assign(socket, :selected_log, path)}
  end

  @impl true
  def handle_event("import_log", %{"log_path" => path}, socket) do
    path = String.trim(path)

    if path == "" do
      {:noreply, assign(socket, :error, "Please select a log file")}
    else
      do_import(socket, path, force_reimport: false)
    end
  end

  @impl true
  def handle_event("load_imported", %{"file_id" => file_id}, socket) do
    file_id = String.to_integer(file_id)

    {:noreply,
     socket
     |> assign(:loading, true)
     |> start_async(:load_from_db, fn -> EncounterStore.load_from_db(file_id) end)}
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
  def handle_event("reimport_log", %{"path" => path}, socket) do
    do_import(socket, path, force_reimport: true)
  end

  @impl true
  def handle_event("save_warcraft_logs_url", %{"file_id" => file_id, "url" => url}, socket) do
    with {:ok, file_id} <- parse_id(file_id),
         %CombatLogFile{} = combat_log_file <-
           get_user_combat_log(socket.assigns.user.id, file_id),
         {:ok, _combat_log_file} <- WarcraftLogs.associate_report(combat_log_file, url) do
      {:noreply,
       socket
       |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
       |> maybe_refresh_current_combat_log(file_id)
       |> put_flash(:info, "Warcraft Logs report linked")}
    else
      {:error, :missing_report_code} ->
        {:noreply, put_flash(socket, :error, "Enter a Warcraft Logs report URL")}

      {:error, :invalid_fight_id} ->
        {:noreply,
         put_flash(socket, :error, "The Warcraft Logs fight id must be a positive number")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to link Warcraft Logs report")}

      nil ->
        {:noreply, put_flash(socket, :error, "Imported log not found")}
    end
  end

  @impl true
  def handle_event("clear_warcraft_logs_url", %{"file_id" => file_id}, socket) do
    with {:ok, file_id} <- parse_id(file_id),
         %CombatLogFile{} = combat_log_file <-
           get_user_combat_log(socket.assigns.user.id, file_id),
         {:ok, _combat_log_file} <- WarcraftLogs.clear_report_association(combat_log_file) do
      {:noreply,
       socket
       |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
       |> maybe_refresh_current_combat_log(file_id)
       |> put_flash(:info, "Warcraft Logs report link cleared")}
    else
      _reason ->
        {:noreply, put_flash(socket, :error, "Failed to clear Warcraft Logs report link")}
    end
  end

  # ============================================================================
  # Info Handlers (PubSub)
  # ============================================================================

  @impl true
  def handle_info({:import_complete, result}, socket) do
    case result do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:import_progress, nil)
         |> assign_document_records()
         |> assign(:log_path, EncounterStore.current_log_path())
         |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
         |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
         |> assign_unimported_log_files()
         |> clear_unavailable_selected_log()
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
    {:noreply,
     socket
     |> assign_document_records()}
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
        socket
        |> assign_document_records()
        |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
        |> assign_unimported_log_files()
        |> clear_unavailable_selected_log()
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
    {:noreply,
     socket
     |> assign_document_records()
     |> assign(:log_path, new_clf.file_path)
     |> assign(:combat_log_file, new_clf)
     |> assign(:log_files, reload_log_files(socket.assigns.user))
     |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
     |> assign_unimported_log_files()
     |> clear_unavailable_selected_log()
     |> put_flash(
       :info,
       "Log rotation detected! Switched to #{Path.basename(new_clf.file_path)} (#{count} encounters)"
     )}
  end

  # ============================================================================
  # Async Handlers
  # ============================================================================

  @impl true
  def handle_async(:load_from_db, {:ok, result}, socket) do
    case result do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign_document_records()
         |> assign(:log_path, EncounterStore.current_log_path())
         |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
         |> put_flash(:info, "Loaded #{count} encounters from database")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Failed to load: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_async(:load_from_db, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, "Failed to load: #{inspect(reason)}")}
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-wow-gold">WoW Raid Diagnostic Tool</h1>
        <div class="flex items-center gap-4">
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
        log_files={@unimported_log_files}
        selected_log={@selected_log}
        loading={@loading}
        import_progress={@import_progress}
        error={@error}
      />

      <ImportedLogsSwitcher.render
        imported_logs={@imported_logs}
        combat_log_file={@combat_log_file}
      />

      <EncounterList.render
        encounter_records={@encounter_records}
        show_resets={@show_resets}
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

  defp do_import(socket, path, opts) do
    Accounts.set_last_loaded_log(socket.assigns.user, path)
    user_id = socket.assigns.user.id
    force_reimport = Keyword.get(opts, :force_reimport, false)

    case ImportWorker.start_import(user_id, path, force_reimport: force_reimport) do
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

  defp assign_unimported_log_files(socket) do
    assign(
      socket,
      :unimported_log_files,
      unimported_log_files(socket.assigns.log_files, socket.assigns.imported_logs)
    )
  end

  defp unimported_log_files(log_files, imported_logs) do
    imported_paths = MapSet.new(imported_logs, & &1.file_path)
    Enum.reject(log_files, &MapSet.member?(imported_paths, &1.full_path))
  end

  defp clear_unavailable_selected_log(socket) do
    selected_log = socket.assigns.selected_log

    if is_binary(selected_log) and
         Enum.any?(socket.assigns.unimported_log_files, &(&1.full_path == selected_log)) do
      socket
    else
      assign(socket, :selected_log, nil)
    end
  end

  defp assign_document_records(socket) do
    {records, state} = document_records()

    socket
    |> assign(:encounter_records, records)
    |> assign(:documents_state, state)
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

  defp list_imported_logs(user_id) do
    CombatLogFile
    |> where([clf], clf.user_id == ^user_id)
    |> join(:left, [clf], e in WeGoNext.Encounters.Encounter, on: e.combat_log_file_id == clf.id)
    |> group_by([clf], clf.id)
    |> select([clf, e], %{
      id: clf.id,
      file_path: clf.file_path,
      last_parsed_at: clf.last_parsed_at,
      last_parsed_byte: clf.last_parsed_byte,
      encounter_count: count(e.id),
      first_encounter_start_at: min(e.start_time),
      is_complete: clf.is_complete,
      warcraft_logs_report_url: clf.warcraft_logs_report_url,
      warcraft_logs_report_code: clf.warcraft_logs_report_code,
      warcraft_logs_fight_id: clf.warcraft_logs_fight_id,
      warcraft_logs_linked_at: clf.warcraft_logs_linked_at
    })
    |> order_by([clf], desc: clf.last_parsed_at)
    |> Repo.all()
  end

  defp get_user_combat_log(user_id, file_id) do
    Repo.get_by(CombatLogFile, id: file_id, user_id: user_id)
  end

  defp maybe_refresh_current_combat_log(socket, file_id) do
    case socket.assigns.combat_log_file do
      %CombatLogFile{id: ^file_id} ->
        assign(socket, :combat_log_file, Repo.get(CombatLogFile, file_id))

      _combat_log_file ->
        socket
    end
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> {:ok, integer}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_id), do: {:error, :invalid_id}
end
