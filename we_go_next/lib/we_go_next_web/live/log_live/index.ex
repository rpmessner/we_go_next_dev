defmodule WeGoNextWeb.LogLive.Index do
  @moduledoc """
  LiveView for imported combat log management.

  Handles switching between imported logs and per-log settings:
  reimport, and Warcraft Logs report linking. Importing new logs happens on
  the home page (`WeGoNextWeb.EncounterLive.Index`).
  """
  use WeGoNextWeb, :live_view

  alias WeGoNext.{
    Accounts,
    CombatLogFile,
    EncounterStore,
    FileWatcher,
    ImportWorker,
    RaidNights,
    Repo,
    WarcraftLogs
  }

  alias WeGoNextWeb.Components.ImportedLogsSwitcher
  alias WeGoNextWeb.{ImportStatus, LoadState, WatchControl}
  import Ecto.Query

  # ============================================================================
  # Mount
  # ============================================================================

  @impl true
  def mount(_params, _session, socket) do
    user = Accounts.get_or_create_default_user()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")
    end

    socket = ImportStatus.mount(socket, user.id)

    {:ok,
     socket
     |> assign(:page_title, "Imported Logs")
     |> assign(:user, user)
     |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
     |> assign(:imported_logs, list_imported_logs(user.id))
     |> assign(:load_status, LoadState.initial())}
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("load_imported", %{"file_id" => file_id}, socket) do
    file_id = String.to_integer(file_id)

    {:noreply,
     socket
     |> transition_load(:load)
     |> start_async(:load_from_db, fn -> EncounterStore.load_from_db(file_id) end)}
  end

  @impl true
  def handle_event("reimport_log", %{"path" => path}, socket) do
    Accounts.set_last_loaded_log(socket.assigns.user, path)

    case ImportWorker.start_import(socket.assigns.user.id, path, force_reimport: true) do
      :ok ->
        {:noreply,
         socket
         |> ImportStatus.refresh(socket.assigns.user.id)}

      {:already_importing, existing_path} ->
        {:noreply,
         socket
         |> ImportStatus.refresh(socket.assigns.user.id)
         |> put_flash(:error, "Already importing #{Path.basename(existing_path)}")}
    end
  end

  @impl true
  def handle_event("toggle_watch_enabled", %{"file_id" => file_id}, socket) do
    socket = WatchControl.toggle(socket, file_id)
    handle_info({:watch_changed, file_id}, socket)
  end

  @impl true
  def handle_event(
        "save_raid_night_name",
        %{"file_id" => file_id, "raid_night" => %{"name" => name}},
        socket
      ) do
    with {:ok, file_id} <- parse_id(file_id),
         %CombatLogFile{} = combat_log_file <-
           get_user_combat_log(socket.assigns.user.id, file_id),
         {:ok, _combat_log_file} <- RaidNights.rename(combat_log_file, name) do
      {:noreply,
       socket
       |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
       |> put_flash(:info, "Raid night name saved")}
    else
      _reason -> {:noreply, put_flash(socket, :error, "Failed to save raid night name")}
    end
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
         |> ImportStatus.refresh(socket.assigns.user.id)
         |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
         |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
         |> put_flash(:info, "Imported #{count} encounters")}

      {:error, _reason} ->
        {:noreply, ImportStatus.refresh(socket, socket.assigns.user.id)}
    end
  end

  @impl true
  def handle_info({:watch_stopped, file_id, _reason}, socket),
    do: handle_info({:watch_changed, file_id}, socket)

  def handle_info({:watch_changed, _file_id}, socket) do
    logs = socket.assigns |> Map.get(:imported_logs, []) |> WatchControl.snapshot()
    {:noreply, assign(socket, :imported_logs, logs)}
  end

  @impl true
  def handle_info({:import_started, _token}, socket),
    do: {:noreply, ImportStatus.refresh(socket, socket.assigns.user.id)}

  def handle_info(:reconcile_import, socket) do
    socket = ImportStatus.refresh(socket, socket.assigns.user.id)

    socket =
      if socket.assigns.import_status.state == :importing do
        socket
      else
        socket
        |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
        |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
      end

    {:noreply, socket}
  end

  def handle_info({:encounters_loaded, _count}, socket) do
    {:noreply, assign(socket, :combat_log_file, EncounterStore.current_combat_log_file())}
  end

  @impl true
  def handle_info(
        {:import_progress, %{bytes_read: bytes, total_bytes: total, encounters_found: found}},
        socket
      ) do
    prev_found = socket.assigns.import_status.encounters_found

    socket =
      ImportStatus.progress(socket, %{
        bytes_read: bytes,
        total_bytes: total,
        encounters_found: found
      })

    socket =
      if socket.assigns.import_status.state == :importing and found > prev_found do
        assign(socket, :imported_logs, list_imported_logs(socket.assigns.user.id))
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:log_rotated, new_clf, count}, socket) do
    FileWatcher.display(new_clf)

    {:noreply,
     socket
     |> assign(:combat_log_file, new_clf)
     |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
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
         |> transition_load(:loaded)
         |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
         |> put_flash(:info, "Loaded #{count} encounters from database")}

      {:error, reason} ->
        {:noreply,
         socket
         |> transition_load(:failed, reason)}
    end
  end

  @impl true
  def handle_async(:load_from_db, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> transition_load(:failed, reason)}
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6" data-load-state={@load_status.state}>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <.back navigate={~p"/"}>Back to encounters</.back>
          <h1 class="mt-3 text-2xl font-bold text-wow-gold">Imported Logs</h1>
          <p class="mt-1 text-sm text-zinc-400">
            Manage imported combat logs: switch the current log, reimport, and manage Warcraft Logs links.
          </p>
        </div>
      </div>

      <div
        :if={@import_status.state == :importing}
        class="rounded-lg border border-zinc-700 bg-zinc-800 p-4"
      >
        <div class="mb-1 flex items-center justify-between text-sm text-zinc-400">
          <span>
            Reimporting log file...
          </span>
          <span>{@import_status.percent}%</span>
        </div>
        <div class="h-2.5 w-full rounded-full bg-zinc-700">
          <div
            class="h-2.5 rounded-full bg-wow-gold transition-all duration-300"
            style={"width: #{@import_status.percent}%"}
          >
          </div>
        </div>
      </div>

      <p :if={@import_status.state in [:failed, :timed_out]} class="text-sm text-red-400">{@import_status.error}</p>
      <p :if={@load_status.state == :failed} class="text-sm text-red-400">{@load_status.error}</p>

      <ImportedLogsSwitcher.render
        imported_logs={@imported_logs}
        combat_log_file={@combat_log_file}
      />

      <section
        :if={@imported_logs == []}
        class="rounded-lg border border-zinc-700 bg-zinc-800 p-6"
      >
        <h2 class="text-lg font-semibold text-zinc-100">No Imported Logs</h2>
        <p class="mt-2 text-sm text-zinc-400">
          Nothing has been imported yet. Import a combat log from the
          <.link navigate={~p"/"} class="text-wow-gold hover:underline">encounter list</.link>
          first.
        </p>
      </section>
    </div>
    """
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp transition_load(socket, event, reason \\ nil) do
    status = socket.assigns.load_status

    {:ok, state, ctx, _effects} =
      LoadState.step(status.state, event, %{error: status.error, reason: reason})

    assign(socket, :load_status, %{state: state, error: ctx.error})
  end

  defp list_imported_logs(user_id) do
    CombatLogFile
    |> where([clf], clf.user_id == ^user_id)
    |> join(:left, [clf], e in WeGoNext.Encounters.Encounter, on: e.combat_log_file_id == clf.id)
    |> group_by([clf], clf.id)
    |> select([clf, e], %{
      id: clf.id,
      file_path: clf.file_path,
      file_mtime: clf.file_mtime,
      last_parsed_at: clf.last_parsed_at,
      last_parsed_byte: clf.last_parsed_byte,
      encounter_count: count(e.id),
      first_encounter_start_at: min(e.start_time),
      source: clf.source,
      watch_enabled: clf.watch_enabled,
      warcraft_logs_report_url: clf.warcraft_logs_report_url,
      warcraft_logs_report_code: clf.warcraft_logs_report_code,
      warcraft_logs_fight_id: clf.warcraft_logs_fight_id,
      warcraft_logs_linked_at: clf.warcraft_logs_linked_at,
      raid_night_name: clf.raid_night_name
    })
    |> order_by([clf, e], desc_nulls_last: min(e.start_time), desc: clf.last_parsed_at)
    |> Repo.all()
    |> WatchControl.snapshot()
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
