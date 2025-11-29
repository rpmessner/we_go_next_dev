defmodule WeGoNextWeb.EncounterLive.Index do
  use WeGoNextWeb, :live_view

  alias WeGoNext.{EncounterStore, Accounts, Repo, CombatLogFile, Importer, ImportWorker}
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    user = Accounts.get_or_create_default_user()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")
      # Subscribe to import progress for this user
      Phoenix.PubSub.subscribe(WeGoNext.PubSub, ImportWorker.progress_topic(user.id))
    end

    encounter_records = EncounterStore.list_encounter_records()
    log_path = EncounterStore.current_log_path()
    combat_log_file = EncounterStore.current_combat_log_file()

    # Load available log files if user has configured a path
    log_files =
      case Accounts.list_combat_logs(user) do
        {:ok, files} -> files
        {:error, _} -> []
      end

    # Check which logs have been imported
    imported_logs = list_imported_logs(user.id)

    # Auto-select if there's only one log file
    selected_log =
      case log_files do
        [single_log] -> single_log.full_path
        _ -> nil
      end

    # Check if an import is already running for this user
    {loading, import_progress, selected_log} =
      case ImportWorker.get_status(user.id) do
        %{status: :importing, path: path} ->
          # Show 0% initially - real progress arrives via PubSub shortly
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
      # Check if this is a complete (dead) log that needs confirmation
      if complete_log?(path, socket.assigns.imported_logs) and not socket.assigns.confirm_reimport do
        {:noreply, assign(socket, :confirm_reimport, true)}
      else
        # If confirm_reimport is true, we're doing a force reimport
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
        # Delete all encounters and events for this log file
        Importer.purge_log(log.id)

        # Clear current view if this was the loaded log
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

  @impl true
  def handle_info({:encounters_loaded, _count}, socket) do
    {:noreply, assign(socket, :encounter_records, EncounterStore.list_encounter_records())}
  end

  @impl true
  def handle_info({:import_progress, :saving}, socket) do
    {:noreply, assign(socket, :import_progress, %{percent: 100, encounters_found: socket.assigns.import_progress[:encounters_found] || 0, status: :saving})}
  end

  @impl true
  def handle_info({:import_progress, %{bytes_read: bytes, total_bytes: total, encounters_found: found}}, socket) do
    percent = if total > 0, do: round(bytes / total * 100), else: 0
    prev_found = socket.assigns.import_progress[:encounters_found] || 0

    # Refresh encounter list and imported logs when new encounters are added
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
    # Log rotation detected - update the UI
    {:noreply,
     socket
     |> assign(:encounter_records, EncounterStore.list_encounter_records())
     |> assign(:log_path, new_clf.file_path)
     |> assign(:combat_log_file, new_clf)
     |> assign(:log_files, reload_log_files(socket.assigns.user))
     |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
     |> put_flash(:info, "Log rotation detected! Switched to #{Path.basename(new_clf.file_path)} (#{count} encounters)")}
  end

  defp reload_log_files(user) do
    case Accounts.list_combat_logs(user) do
      {:ok, files} -> files
      {:error, _} -> []
    end
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
                disabled={@loading}
                class="flex-1 bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold disabled:opacity-50"
              >
                <option value="">Choose a log file...</option>
                <%= for log <- @log_files do %>
                  <option value={log.full_path} selected={@selected_log == log.full_path}>
                    {log.filename} ({format_size(log.size)})
                    {cond do
                      partially_imported?(log.full_path, @imported_logs) -> " ⚠ (incomplete)"
                      complete_log?(log.full_path, @imported_logs) -> " ✓ (complete)"
                      imported?(log.full_path, @imported_logs) -> " ✓"
                      true -> ""
                    end}
                  </option>
                <% end %>
              </select>
              <%= if @confirm_reimport do %>
                <button
                  type="submit"
                  disabled={@loading}
                  class="px-4 py-2 bg-red-600 text-white font-semibold rounded hover:bg-red-500 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Confirm Reimport
                </button>
                <button
                  type="button"
                  phx-click="cancel_reimport"
                  class="px-3 py-2 text-zinc-400 hover:text-zinc-200"
                >
                  Cancel
                </button>
              <% else %>
                <button
                  type="submit"
                  disabled={@loading || !@selected_log}
                  class={[
                    "px-4 py-2 font-semibold rounded disabled:opacity-50 disabled:cursor-not-allowed",
                    cond do
                      partially_imported?(@selected_log, @imported_logs) -> "bg-yellow-600 text-white hover:bg-yellow-500"
                      complete_log?(@selected_log, @imported_logs) -> "bg-zinc-600 text-zinc-300 hover:bg-zinc-500"
                      true -> "bg-wow-gold text-zinc-900 hover:bg-yellow-400"
                    end
                  ]}
                >
                  {cond do
                    @loading -> "Importing..."
                    partially_imported?(@selected_log, @imported_logs) -> "Resume"
                    complete_log?(@selected_log, @imported_logs) -> "Reimport"
                    true -> "Import"
                  end}
                </button>
                <button
                  :if={imported?(@selected_log, @imported_logs)}
                  type="button"
                  phx-click="purge_log"
                  phx-value-path={@selected_log}
                  disabled={@loading}
                  data-confirm="Delete all encounters from this log? This cannot be undone."
                  class="px-3 py-2 text-red-400 hover:text-red-300 hover:bg-red-900/30 rounded disabled:opacity-50"
                  title="Purge encounters"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </button>
              <% end %>
            </form>
            <%!-- Warning message for complete logs --%>
            <p :if={@confirm_reimport} class="text-sm text-yellow-500 mt-2">
              This log has already been fully imported. Click "Confirm Reimport" to import again.
            </p>

            <%!-- Progress bar during import --%>
            <div :if={@import_progress} class="mt-3">
              <div class="flex items-center justify-between text-sm text-zinc-400 mb-1">
                <span>
                  <%= case @import_progress.status do %>
                    <% :parsing -> %>
                      Parsing log file...
                    <% :saving -> %>
                      Saving to database...
                  <% end %>
                </span>
                <span>{@import_progress.percent}%</span>
              </div>
              <div class="w-full bg-zinc-700 rounded-full h-2.5">
                <div
                  class="bg-wow-gold h-2.5 rounded-full transition-all duration-300"
                  style={"width: #{@import_progress.percent}%"}
                >
                </div>
              </div>
              <p class="text-xs text-zinc-500 mt-1">
                {if @import_progress.encounters_found > 0, do: "#{@import_progress.encounters_found} encounters found", else: "Scanning for encounters..."}
              </p>
            </div>
          </div>

          <%!-- Currently loaded log info + Refresh button (only for incomplete logs) --%>
          <div :if={@log_path} class="flex items-center justify-between border-t border-zinc-700 pt-3 mt-3">
            <div>
              <p class="text-sm text-zinc-400">Currently loaded:</p>
              <p class="text-zinc-200">{Path.basename(@log_path)}</p>
              <p :if={@combat_log_file} class="text-xs text-zinc-500 mt-1">
                {encounter_count(@combat_log_file, @imported_logs)} encounters imported
              </p>
            </div>
            <button
              :if={not dead_log?(@log_path, @log_files)}
              phx-click="sync_log"
              disabled={@syncing}
              class="px-4 py-2 bg-zinc-700 text-zinc-200 font-medium rounded hover:bg-zinc-600 disabled:opacity-50"
            >
              {if @syncing, do: "Refreshing...", else: "Refresh"}
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

      <%!-- Imported logs switcher - show when there are multiple logs --%>
      <div :if={length(@imported_logs) > 1} class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Switch Log File</h3>
        <div class="space-y-2">
          <%= for clf <- @imported_logs do %>
            <% is_current = @combat_log_file && @combat_log_file.id == clf.id %>
            <button
              phx-click={if is_current, do: nil, else: "load_imported"}
              phx-value-file_id={clf.id}
              disabled={is_current}
              class={[
                "w-full text-left px-3 py-2 rounded transition-colors flex items-center justify-between",
                if(is_current,
                  do: "bg-wow-gold/20 border border-wow-gold/50 cursor-default",
                  else: "bg-zinc-900 hover:bg-zinc-700 cursor-pointer"
                )
              ]}
            >
              <div>
                <span class={if is_current, do: "text-wow-gold font-medium", else: "text-zinc-200"}>
                  {Path.basename(clf.file_path)}
                </span>
                <span class="text-zinc-500 text-sm ml-2">
                  ({clf.encounter_count} encounters)
                </span>
              </div>
              <span :if={is_current} class="text-xs text-wow-gold px-2 py-0.5 bg-wow-gold/10 rounded">
                Current
              </span>
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Encounters list --%>
      <div :if={@encounter_records != []}>
        <div class="flex items-center justify-between mb-3">
          <h2 class="section-header mb-0">Encounters ({visible_count(@encounter_records, @show_resets)})</h2>
          <div :if={@user.is_admin && has_resets?(@encounter_records)} class="flex items-center gap-2">
            <label class="flex items-center gap-2 cursor-pointer text-sm text-zinc-400">
              <input
                type="checkbox"
                checked={@show_resets}
                phx-click="toggle_show_resets"
                class="rounded border-zinc-600 bg-zinc-700 text-blue-500 focus:ring-blue-500 focus:ring-offset-zinc-800"
              />
              Show resets ({reset_count(@encounter_records)})
            </label>
          </div>
        </div>
        <div class="space-y-2">
          <%= for {encounter, idx} <- filtered_encounters(@encounter_records, @show_resets) do %>
            <div class={["encounter-card", if(encounter.is_reset, do: "opacity-50", else: "")]}>
              <div class="flex items-center justify-between">
                <.link href={~p"/encounters/#{encounter.id}"} class="flex-1 flex items-center gap-3">
                  <span class="text-zinc-500 font-mono text-sm w-6">{idx}.</span>
                  <div>
                    <span class="font-semibold text-zinc-100">{encounter.name}</span>
                    <span class="text-zinc-500 ml-2">({encounter.difficulty_name})</span>
                    <span :if={encounter.is_reset} class="ml-2 text-xs text-yellow-500">(Reset)</span>
                  </div>
                </.link>
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
                    {death_count_from_record(encounter)} deaths
                  </span>
                  <%!-- Gear menu for admin actions --%>
                  <div :if={@user.is_admin} class="relative">
                    <button
                      phx-click="toggle_menu"
                      phx-value-id={encounter.id}
                      class="p-1.5 rounded text-zinc-500 hover:text-zinc-300 hover:bg-zinc-700 transition-colors"
                      title="Options"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                      </svg>
                    </button>
                    <%!-- Dropdown menu --%>
                    <div
                      :if={@open_menu_id == encounter.id}
                      class="absolute right-0 top-full mt-1 w-36 bg-zinc-800 border border-zinc-600 rounded-lg shadow-lg z-10"
                      phx-click-away="close_menu"
                    >
                      <button
                        phx-click="toggle_reset"
                        phx-value-id={encounter.id}
                        class="w-full text-left px-3 py-2 text-sm text-zinc-300 hover:bg-zinc-700 rounded-lg transition-colors"
                      >
                        {if encounter.is_reset, do: "Unmark as reset", else: "Mark as reset"}
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Empty state --%>
      <div :if={@encounter_records == [] && !@loading && @log_files != []} class="text-center py-12 text-zinc-500">
        <p class="text-lg">No encounters loaded</p>
        <p class="text-sm mt-2">Select a combat log file above to import</p>
      </div>
    </div>
    """
  end

  defp format_size(bytes) when bytes >= 1_000_000 do
    "#{Float.round(bytes / 1_000_000, 1)} MB"
  end

  defp format_size(bytes) when bytes >= 1000 do
    "#{div(bytes, 1000)} KB"
  end

  defp format_size(bytes), do: "#{bytes} B"

  # Get death count from cached analysis if available
  defp death_count_from_record(record) do
    case record.analysis do
      %{"deaths" => deaths} when is_list(deaths) -> length(deaths)
      _ -> 0
    end
  end

  # Filter and index encounters
  defp filtered_encounters(records, show_resets) do
    records
    |> Enum.with_index(1)
    |> Enum.reject(fn {record, _idx} ->
      not show_resets and record.is_reset
    end)
  end

  defp visible_count(records, show_resets) do
    if show_resets do
      length(records)
    else
      Enum.count(records, &(not &1.is_reset))
    end
  end

  defp reset_count(records) do
    Enum.count(records, & &1.is_reset)
  end

  defp has_resets?(records) do
    Enum.any?(records, & &1.is_reset)
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

  defp imported?(file_path, imported_logs) do
    Enum.any?(imported_logs, &(&1.file_path == file_path))
  end

  # Check if a log is fully imported (parsed up to what we knew about at import time)
  # Uses stored file_size, NOT current disk size, to avoid race conditions where
  # WoW writes more data between import completion and UI render
  defp complete_log?(file_path, imported_logs) do
    case Enum.find(imported_logs, &(&1.file_path == file_path)) do
      nil ->
        false

      log ->
        parsed = log.last_parsed_byte || 0
        # The importer stores end_byte as both last_parsed_byte and file_size
        # So if they match (within tolerance), we've completed what we started with
        parsed > 0 and not partially_imported?(file_path, imported_logs)
    end
  end

  # Check if an imported log was interrupted mid-import OR has new content
  # Returns true if there's significant unparsed content (> 100 bytes)
  defp partially_imported?(file_path, imported_logs) do
    case Enum.find(imported_logs, &(&1.file_path == file_path)) do
      nil ->
        false

      log ->
        # Compare last_parsed_byte against current disk file size
        case File.stat(file_path) do
          {:ok, %{size: disk_size}} ->
            parsed = log.last_parsed_byte || 0
            # Consider incomplete only if > 100 bytes unparsed
            # (accounts for trailing newlines, partial lines at EOF)
            parsed > 0 and (disk_size - parsed) > 100

          {:error, _} ->
            false
        end
    end
  end

  # Check if a log is "dead" - not the newest log file in the folder
  # WoW only writes to the newest log, so older logs are dead
  defp dead_log?(file_path, log_files) when is_list(log_files) do
    case log_files do
      [] -> false
      logs ->
        # log_files are sorted by mtime desc, so first is newest
        newest = hd(logs)
        newest.full_path != file_path
    end
  end

  defp dead_log?(_, _), do: false

  defp encounter_count(%CombatLogFile{id: id}, imported_logs) do
    case Enum.find(imported_logs, &(&1.id == id)) do
      nil -> 0
      log -> log.encounter_count
    end
  end
end
