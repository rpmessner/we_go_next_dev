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

  alias WeGoNext.{EncounterStore, Accounts, Repo, CombatLogFile, Importer, ImportWorker}
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

    encounter_records = EncounterStore.list_encounter_records()
    log_path = EncounterStore.current_log_path()
    combat_log_file = EncounterStore.current_combat_log_file()

    log_files =
      case Accounts.list_combat_logs(user) do
        {:ok, files} -> files
        {:error, _} -> []
      end

    imported_logs = list_imported_logs(user.id)

    selected_log =
      case log_files do
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
     |> assign(:show_resets, false)
     |> assign(:open_menu_id, nil)
     |> assign(:log_path, log_path)
     |> assign(:combat_log_file, combat_log_file)
     |> assign(:log_files, log_files)
     |> assign(:imported_logs, imported_logs)
     |> assign(:selected_log, selected_log)
     |> assign(:loading, loading)
     |> assign(:syncing, false)
     |> assign(:error, nil)
     |> assign(:import_progress, import_progress)
     |> assign(:confirm_reimport, false)}
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("select_log", params, socket) do
    path = params["log_path"]
    {:noreply, socket |> assign(:selected_log, path) |> assign(:confirm_reimport, false)}
  end

  @impl true
  def handle_event("import_log", %{"log_path" => path}, socket) do
    path = String.trim(path)

    if path == "" do
      {:noreply, assign(socket, :error, "Please select a log file")}
    else
      if complete_log?(path, socket.assigns.imported_logs) and not socket.assigns.confirm_reimport do
        {:noreply, assign(socket, :confirm_reimport, true)}
      else
        force_reimport = socket.assigns.confirm_reimport
        do_import(socket, path, force_reimport: force_reimport)
      end
    end
  end

  @impl true
  def handle_event("cancel_reimport", _params, socket) do
    {:noreply, assign(socket, :confirm_reimport, false)}
  end

  @impl true
  def handle_event("purge_log", %{"path" => path}, socket) do
    case Enum.find(socket.assigns.imported_logs, &(&1.file_path == path)) do
      nil ->
        {:noreply, assign(socket, :error, "Log not found")}

      log ->
        Importer.purge_log(log.id)

        socket =
          if socket.assigns.log_path == path do
            socket
            |> assign(:encounter_records, [])
            |> assign(:log_path, nil)
            |> assign(:combat_log_file, nil)
          else
            socket
          end

        {:noreply,
         socket
         |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
         |> put_flash(:info, "Purged #{Path.basename(path)}")}
    end
  end

  @impl true
  def handle_event("sync_log", _params, socket) do
    case socket.assigns.log_path do
      nil ->
        {:noreply, assign(socket, :error, "No log file loaded")}

      path ->
        {:noreply,
         socket
         |> assign(:syncing, true)
         |> assign(:error, nil)
         |> start_async(:sync_log, fn -> EncounterStore.sync_log(path) end)}
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
         |> assign(:encounter_records, EncounterStore.list_encounter_records())
         |> assign(:open_menu_id, nil)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle reset status")}
    end
  end

  @impl true
  def handle_event("toggle_show_resets", _params, socket) do
    {:noreply, assign(socket, :show_resets, not socket.assigns.show_resets)}
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
         |> assign(:encounter_records, EncounterStore.list_encounter_records())
         |> assign(:log_path, EncounterStore.current_log_path())
         |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
         |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
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
    {:noreply, assign(socket, :encounter_records, EncounterStore.list_encounter_records())}
  end

  @impl true
  def handle_info({:analysis_computed, _encounter_id, current, total}, socket) do
    # Refresh encounter records to get updated analysis status
    # Only refresh on last analysis or every 5th to avoid excessive updates
    socket =
      if current == total or rem(current, 5) == 0 do
        assign(socket, :encounter_records, EncounterStore.list_encounter_records())
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:import_progress, :saving}, socket) do
    {:noreply, assign(socket, :import_progress, %{percent: 100, encounters_found: socket.assigns.import_progress[:encounters_found] || 0, status: :saving})}
  end

  @impl true
  def handle_info({:import_progress, %{bytes_read: bytes, total_bytes: total, encounters_found: found}}, socket) do
    percent = if total > 0, do: round(bytes / total * 100), else: 0
    prev_found = socket.assigns.import_progress[:encounters_found] || 0

    socket =
      if found > prev_found do
        socket
        |> assign(:encounter_records, EncounterStore.list_encounter_records())
        |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
      else
        socket
      end

    {:noreply, assign(socket, :import_progress, %{percent: percent, encounters_found: found, status: :parsing})}
  end

  @impl true
  def handle_info({:log_rotated, new_clf, count}, socket) do
    {:noreply,
     socket
     |> assign(:encounter_records, EncounterStore.list_encounter_records())
     |> assign(:log_path, new_clf.file_path)
     |> assign(:combat_log_file, new_clf)
     |> assign(:log_files, reload_log_files(socket.assigns.user))
     |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
     |> put_flash(:info, "Log rotation detected! Switched to #{Path.basename(new_clf.file_path)} (#{count} encounters)")}
  end

  # ============================================================================
  # Async Handlers
  # ============================================================================

  @impl true
  def handle_async(:sync_log, {:ok, result}, socket) do
    case result do
      {:ok, count} ->
        message = if count > 0, do: "Found #{count} new encounters", else: "No new encounters"

        {:noreply,
         socket
         |> assign(:syncing, false)
         |> assign(:encounter_records, EncounterStore.list_encounter_records())
         |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
         |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:syncing, false)
         |> assign(:error, "Failed to sync log: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_async(:sync_log, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:syncing, false)
     |> assign(:error, "Failed to sync log: #{inspect(reason)}")}
  end

  @impl true
  def handle_async(:load_from_db, {:ok, result}, socket) do
    case result do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:encounter_records, EncounterStore.list_encounter_records())
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
        <.link navigate={~p"/settings"} class="text-sm text-zinc-400 hover:text-zinc-200">
          Settings
        </.link>
      </div>

      <LogSelector.render
        user={@user}
        log_files={@log_files}
        selected_log={@selected_log}
        imported_logs={@imported_logs}
        loading={@loading}
        syncing={@syncing}
        confirm_reimport={@confirm_reimport}
        import_progress={@import_progress}
        log_path={@log_path}
        combat_log_file={@combat_log_file}
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
         |> assign(:confirm_reimport, false)
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
      is_complete: clf.is_complete
    })
    |> order_by([clf], desc: clf.last_parsed_at)
    |> Repo.all()
  end

  defp complete_log?(file_path, imported_logs) do
    case Enum.find(imported_logs, &(&1.file_path == file_path)) do
      nil ->
        false

      log ->
        parsed = log.last_parsed_byte || 0
        parsed > 0 and not partially_imported?(file_path, imported_logs)
    end
  end

  defp partially_imported?(file_path, imported_logs) do
    case Enum.find(imported_logs, &(&1.file_path == file_path)) do
      nil ->
        false

      log ->
        case File.stat(file_path) do
          {:ok, %{size: disk_size}} ->
            parsed = log.last_parsed_byte || 0
            parsed > 0 and (disk_size - parsed) > 100

          {:error, _} ->
            false
        end
    end
  end
end
