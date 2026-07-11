defmodule WeGoNextWeb.LogLive.Index do
  @moduledoc """
  LiveView for imported combat log management.

  Handles switching between imported logs and per-log settings: publish,
  reimport, and Warcraft Logs report linking. Importing new logs happens on
  the home page (`WeGoNextWeb.EncounterLive.Index`).
  """
  use WeGoNextWeb, :live_view

  alias WeGoNext.{
    Accounts,
    CombatLogFile,
    EncounterStore,
    ImportWorker,
    Repo,
    WarcraftLogs
  }

  alias WeGoNextWeb.Components.ImportedLogsSwitcher
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

    loading = match?(%{status: :importing}, ImportWorker.get_status(user.id))

    {:ok,
     socket
     |> assign(:page_title, "Imported Logs")
     |> assign(:user, user)
     |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
     |> assign(:imported_logs, list_imported_logs(user.id))
     |> assign(:loading, loading)
     |> assign(:error, nil)
     |> assign(:import_progress, nil)}
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("load_imported", %{"file_id" => file_id}, socket) do
    file_id = String.to_integer(file_id)

    {:noreply,
     socket
     |> assign(:loading, true)
     |> start_async(:load_from_db, fn -> EncounterStore.load_from_db(file_id) end)}
  end

  @impl true
  def handle_event("reimport_log", %{"path" => path}, socket) do
    Accounts.set_last_loaded_log(socket.assigns.user, path)

    case ImportWorker.start_import(socket.assigns.user.id, path, force_reimport: true) do
      :ok ->
        {:noreply,
         socket
         |> assign(:loading, true)
         |> assign(:error, nil)
         |> assign(:import_progress, %{percent: 0, encounters_found: 0, status: :parsing})}

      {:already_importing, existing_path} ->
        {:noreply,
         socket
         |> assign(:error, "Already importing #{Path.basename(existing_path)}")}
    end
  end

  @impl true
  def handle_event("toggle_publish_enabled", %{"file_id" => file_id}, socket) do
    with {:ok, file_id} <- parse_id(file_id),
         %CombatLogFile{} = combat_log_file <-
           get_user_combat_log(socket.assigns.user.id, file_id),
         {:ok, _combat_log_file} <-
           combat_log_file
           |> CombatLogFile.changeset(%{publish_enabled: !combat_log_file.publish_enabled})
           |> Repo.update() do
      {:noreply,
       socket
       |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
       |> maybe_refresh_current_combat_log(file_id)}
    else
      _reason ->
        {:noreply, put_flash(socket, :error, "Failed to update publish setting")}
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
         |> assign(:loading, false)
         |> assign(:import_progress, nil)
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
    {:noreply, assign(socket, :combat_log_file, EncounterStore.current_combat_log_file())}
  end

  @impl true
  def handle_info({:import_progress, :saving}, socket) do
    {:noreply,
     assign(socket, :import_progress, %{
       percent: 100,
       encounters_found: get_in(socket.assigns.import_progress, [:encounters_found]) || 0,
       status: :saving
     })}
  end

  @impl true
  def handle_info(
        {:import_progress, %{bytes_read: bytes, total_bytes: total, encounters_found: found}},
        socket
      ) do
    percent = if total > 0, do: round(bytes / total * 100), else: 0
    prev_found = get_in(socket.assigns.import_progress, [:encounters_found]) || 0

    socket =
      if found > prev_found do
        assign(socket, :imported_logs, list_imported_logs(socket.assigns.user.id))
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
         |> assign(:loading, false)
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
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <.back navigate={~p"/"}>Back to encounters</.back>
          <h1 class="mt-3 text-2xl font-bold text-wow-gold">Imported Logs</h1>
          <p class="mt-1 text-sm text-zinc-400">
            Manage imported combat logs: switch the current log, reimport, publish, and Warcraft Logs links.
          </p>
        </div>
      </div>

      <div
        :if={@import_progress}
        class="rounded-lg border border-zinc-700 bg-zinc-800 p-4"
      >
        <div class="mb-1 flex items-center justify-between text-sm text-zinc-400">
          <span>
            <%= case @import_progress.status do %>
              <% :parsing -> %>
                Reimporting log file...
              <% :saving -> %>
                Saving to database...
            <% end %>
          </span>
          <span>{@import_progress.percent}%</span>
        </div>
        <div class="h-2.5 w-full rounded-full bg-zinc-700">
          <div
            class="h-2.5 rounded-full bg-wow-gold transition-all duration-300"
            style={"width: #{@import_progress.percent}%"}
          >
          </div>
        </div>
      </div>

      <p :if={@error} class="text-sm text-red-400">{@error}</p>

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
      warcraft_logs_linked_at: clf.warcraft_logs_linked_at,
      publish_enabled: clf.publish_enabled
    })
    |> order_by([clf, e], desc_nulls_last: min(e.start_time), desc: clf.last_parsed_at)
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
