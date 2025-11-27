defmodule WeGoNextWeb.EncounterLive.Index do
  use WeGoNextWeb, :live_view

  alias WeGoNext.{EncounterStore, Encounter, Accounts, Repo, CombatLogFile}
  alias WeGoNext.Analyzers.DeathAnalyzer
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")
    end

    user = Accounts.get_or_create_default_user()
    encounters = EncounterStore.list_encounters()
    log_path = EncounterStore.current_log_path()
    combat_log_file = EncounterStore.current_combat_log_file()
    watching_file = WeGoNext.FileWatcher.current_file()

    # Load available log files if user has configured a path
    log_files =
      case Accounts.list_combat_logs(user) do
        {:ok, files} -> files
        {:error, _} -> []
      end

    # Check which logs have been imported
    imported_logs = list_imported_logs(user.id)

    {:ok,
     socket
     |> assign(:page_title, "Encounters")
     |> assign(:user, user)
     |> assign(:encounters, encounters)
     |> assign(:log_path, log_path)
     |> assign(:combat_log_file, combat_log_file)
     |> assign(:log_files, log_files)
     |> assign(:imported_logs, imported_logs)
     |> assign(:selected_log, nil)
     |> assign(:loading, false)
     |> assign(:syncing, false)
     |> assign(:error, nil)
     |> assign(:watching, watching_file != nil)}
  end

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
      Accounts.set_last_loaded_log(socket.assigns.user, path)
      user_id = socket.assigns.user.id

      {:noreply,
       socket
       |> assign(:loading, true)
       |> assign(:error, nil)
       |> assign(:selected_log, path)
       |> start_async(:import_log, fn -> EncounterStore.import_log(path, user_id) end)}
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
  def handle_async(:import_log, {:ok, result}, socket) do
    case result do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:encounters, EncounterStore.list_encounters())
         |> assign(:log_path, EncounterStore.current_log_path())
         |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
         |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
         |> assign(:watching, true)
         |> put_flash(:info, "Imported #{count} encounters - Auto-refresh enabled")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Failed to import log: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_async(:import_log, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, "Failed to import log: #{inspect(reason)}")}
  end

  @impl true
  def handle_async(:sync_log, {:ok, result}, socket) do
    case result do
      {:ok, count} ->
        message = if count > 0, do: "Found #{count} new encounters", else: "No new encounters"

        {:noreply,
         socket
         |> assign(:syncing, false)
         |> assign(:encounters, EncounterStore.list_encounters())
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
         |> assign(:encounters, EncounterStore.list_encounters())
         |> assign(:log_path, EncounterStore.current_log_path())
         |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
         |> assign(:watching, true)
         |> put_flash(:info, "Loaded #{count} encounters from database - Auto-refresh enabled")}

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

  @impl true
  def handle_info({:encounters_loaded, _count}, socket) do
    {:noreply, assign(socket, :encounters, EncounterStore.list_encounters())}
  end

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

      <%!-- Log file selector --%>
      <div class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <%= if @user.wow_logs_path && @log_files != [] do %>
          <div class="mb-3">
            <label class="block text-sm font-medium text-zinc-400 mb-2">
              Import Combat Log
            </label>
            <form phx-change="select_log" phx-submit="import_log" class="flex gap-2">
              <select
                name="log_path"
                class="flex-1 bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
              >
                <option value="">Choose a log file...</option>
                <%= for log <- @log_files do %>
                  <option value={log.full_path} selected={@selected_log == log.full_path}>
                    {log.filename} ({format_size(log.size)})
                    {if is_imported?(log.full_path, @imported_logs), do: " ✓", else: ""}
                  </option>
                <% end %>
              </select>
              <button
                type="submit"
                disabled={@loading || !@selected_log}
                class="px-4 py-2 bg-wow-gold text-zinc-900 font-semibold rounded hover:bg-yellow-400 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {if @loading, do: "Importing...", else: "Import"}
              </button>
            </form>
          </div>

          <%!-- Refresh button for currently loaded log --%>
          <div :if={@log_path} class="flex items-center justify-between border-t border-zinc-700 pt-3 mt-3">
            <div>
              <p class="text-sm text-zinc-400">Currently loaded:</p>
              <p class="text-zinc-200">{Path.basename(@log_path)}</p>
              <div class="flex items-center gap-2 mt-1">
                <p :if={@combat_log_file} class="text-xs text-zinc-500">
                  {encounter_count(@combat_log_file, @imported_logs)} encounters imported
                </p>
                <span :if={@watching} class="inline-flex items-center gap-1 text-xs text-green-400">
                  <span class="relative flex h-2 w-2">
                    <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
                    <span class="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
                  </span>
                  Auto-refresh active
                </span>
              </div>
            </div>
            <button
              phx-click="sync_log"
              disabled={@syncing}
              class="px-4 py-2 bg-zinc-700 text-zinc-200 font-medium rounded hover:bg-zinc-600 disabled:opacity-50"
            >
              {if @syncing, do: "Syncing...", else: "Refresh"}
            </button>
          </div>
        <% else %>
          <div class="text-center py-4">
            <p class="text-zinc-400 mb-3">
              <%= if @user.wow_logs_path do %>
                No combat log files found in the configured folder.
              <% else %>
                Configure your WoW Logs folder to get started.
              <% end %>
            </p>
            <.link
              navigate={~p"/settings"}
              class="inline-flex items-center px-4 py-2 bg-wow-gold text-zinc-900 font-semibold rounded hover:bg-yellow-400"
            >
              Configure WoW Folder
            </.link>
          </div>
        <% end %>

        <p :if={@error} class="mt-2 text-sm text-red-400">{@error}</p>
      </div>

      <%!-- Previously imported logs --%>
      <div :if={@imported_logs != [] && !@log_path} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Previously Imported Logs</h3>
        <div class="space-y-2">
          <%= for clf <- @imported_logs do %>
            <button
              phx-click="load_imported"
              phx-value-file_id={clf.id}
              class="w-full text-left px-3 py-2 bg-zinc-900 rounded hover:bg-zinc-700 transition-colors"
            >
              <span class="text-zinc-200">{Path.basename(clf.file_path)}</span>
              <span class="text-zinc-500 text-sm ml-2">
                ({clf.encounter_count} encounters)
              </span>
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Encounters list --%>
      <div :if={@encounters != []}>
        <h2 class="section-header">Encounters ({length(@encounters)})</h2>
        <div class="space-y-2">
          <.link
            :for={{encounter, idx} <- Enum.with_index(@encounters, 1)}
            navigate={~p"/encounters/#{idx}"}
            class="encounter-card block"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <span class="text-zinc-500 font-mono text-sm w-6">{idx}.</span>
                <div>
                  <span class="font-semibold text-zinc-100">{encounter.name}</span>
                  <span class="text-zinc-500 ml-2">({encounter.difficulty_name})</span>
                </div>
              </div>
              <div class="flex items-center gap-4">
                <span class={[
                  "inline-flex items-center px-2 py-1 rounded text-xs font-medium",
                  if(encounter.success,
                    do: "bg-green-900 text-green-300",
                    else: "bg-red-900 text-red-300"
                  )
                ]}>
                  {if encounter.success, do: "KILL", else: "WIPE"}
                </span>
                <span class="text-zinc-400 font-mono text-sm">
                  {format_duration(encounter)}
                </span>
                <span class="text-zinc-500 text-sm">
                  {death_count(encounter)} deaths
                </span>
              </div>
            </div>
          </.link>
        </div>
      </div>

      <%!-- Empty state --%>
      <div :if={@encounters == [] && !@loading && @log_files != []} class="text-center py-12 text-zinc-500">
        <p class="text-lg">No encounters loaded</p>
        <p class="text-sm mt-2">Select a combat log file above to import</p>
      </div>
    </div>
    """
  end

  defp format_duration(%Encounter{fight_time_ms: ms}) when is_integer(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_duration(_), do: "0:00"

  defp format_size(bytes) when bytes >= 1_000_000 do
    "#{Float.round(bytes / 1_000_000, 1)} MB"
  end

  defp format_size(bytes) when bytes >= 1000 do
    "#{div(bytes, 1000)} KB"
  end

  defp format_size(bytes), do: "#{bytes} B"

  defp death_count(encounter) do
    encounter
    |> DeathAnalyzer.analyze()
    |> length()
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
      encounter_count: count(e.id)
    })
    |> order_by([clf], desc: clf.last_parsed_at)
    |> Repo.all()
  end

  defp is_imported?(file_path, imported_logs) do
    Enum.any?(imported_logs, &(&1.file_path == file_path))
  end

  defp encounter_count(%CombatLogFile{id: id}, imported_logs) do
    case Enum.find(imported_logs, &(&1.id == id)) do
      nil -> 0
      log -> log.encounter_count
    end
  end
end
