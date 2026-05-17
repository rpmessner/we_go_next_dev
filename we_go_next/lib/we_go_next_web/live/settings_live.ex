defmodule WeGoNextWeb.SettingsLive do
  use WeGoNextWeb, :live_view

  import WeGoNextWeb.EncounterComponents, only: [format_size: 1]

  alias WeGoNext.{Accounts, EncounterStore, FileWatcher}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")
    end

    user = Accounts.get_or_create_default_user()
    watching_file = FileWatcher.current_file()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:user, user)
     |> assign(:path_input, user.wow_logs_path || "")
     |> assign(:path_valid, check_path_valid(user.wow_logs_path))
     |> assign(:log_files, [])
     |> assign(:saving, false)
     |> assign(:watching_file, watching_file)
     |> assign(:selected_log, nil)
     |> assign(:importing, false)
     |> maybe_load_log_files(user)}
  end

  @impl true
  def handle_event("validate_path", %{"path" => path}, socket) do
    path = String.trim(path)
    valid = check_path_valid(path)

    {:noreply,
     socket
     |> assign(:path_input, path)
     |> assign(:path_valid, valid)}
  end

  @impl true
  def handle_event("save_path", %{"path" => path}, socket) do
    path = String.trim(path)

    case Accounts.set_wow_logs_path(socket.assigns.user, path) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:path_valid, check_path_valid(path))
         |> maybe_load_log_files(user)
         |> put_flash(:info, "WoW Logs folder saved!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save path")}
    end
  end

  @impl true
  def handle_event("select_log", %{"log_path" => path}, socket) do
    {:noreply, assign(socket, :selected_log, path)}
  end

  @impl true
  def handle_event("watch_log", %{"log_path" => path}, socket) do
    path = String.trim(path)

    if path == "" do
      {:noreply, put_flash(socket, :error, "Please select a log file")}
    else
      user_id = socket.assigns.user.id

      {:noreply,
       socket
       |> assign(:importing, true)
       |> start_async(:import_and_watch, fn -> EncounterStore.import_log(path, user_id) end)}
    end
  end

  @impl true
  def handle_event("watch_most_recent", _params, socket) do
    case List.first(socket.assigns.log_files) do
      nil ->
        {:noreply, put_flash(socket, :error, "No log files available")}

      most_recent ->
        user_id = socket.assigns.user.id
        path = most_recent.full_path

        {:noreply,
         socket
         |> assign(:importing, true)
         |> assign(:selected_log, path)
         |> start_async(:import_and_watch, fn -> EncounterStore.import_log(path, user_id) end)}
    end
  end

  @impl true
  def handle_event("stop_watching", _params, socket) do
    FileWatcher.stop_watching()
    {:noreply, assign(socket, :watching_file, nil) |> put_flash(:info, "Stopped watching")}
  end

  @impl true
  def handle_async(:import_and_watch, {:ok, result}, socket) do
    case result do
      {:ok, count} ->
        watching_file = FileWatcher.current_file()

        {:noreply,
         socket
         |> assign(:importing, false)
         |> assign(:watching_file, watching_file)
         |> put_flash(:info, "Imported #{count} encounters - Now watching for changes")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:importing, false)
         |> put_flash(:error, "Failed to import: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_async(:import_and_watch, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:importing, false)
     |> put_flash(:error, "Failed to import: #{inspect(reason)}")}
  end

  @impl true
  def handle_info({:encounters_loaded, count}, socket) do
    {:noreply, put_flash(socket, :info, "#{count} new encounter(s) detected!")}
  end

  @impl true
  def handle_info({:analysis_computed, _encounter_id, _current, _total}, socket) do
    # Ignore analysis progress updates on settings page
    {:noreply, socket}
  end

  @impl true
  def handle_info({:log_rotated, new_clf, count}, socket) do
    # Log rotation detected - update watching file indicator
    {:noreply,
     socket
     |> assign(:watching_file, new_clf)
     |> assign(:log_files, reload_log_files(socket.assigns.user))
     |> put_flash(
       :info,
       "Log rotation! Now watching #{Path.basename(new_clf.file_path)} (#{count} encounters)"
     )}
  end

  defp reload_log_files(%{wow_logs_path: nil}), do: []
  defp reload_log_files(%{wow_logs_path: ""}), do: []

  defp reload_log_files(user) do
    case Accounts.list_combat_logs(user) do
      {:ok, files} -> files
      {:error, _} -> []
    end
  end

  defp check_path_valid(nil), do: false
  defp check_path_valid(""), do: false

  defp check_path_valid(path) do
    File.dir?(path)
  end

  defp maybe_load_log_files(socket, %{wow_logs_path: nil}), do: assign(socket, :log_files, [])
  defp maybe_load_log_files(socket, %{wow_logs_path: ""}), do: assign(socket, :log_files, [])

  defp maybe_load_log_files(socket, user) do
    case Accounts.list_combat_logs(user) do
      {:ok, files} -> assign(socket, :log_files, files)
      {:error, _} -> assign(socket, :log_files, [])
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.back navigate={~p"/"}>Back to encounters</.back>

      <h1 class="text-2xl font-bold text-wow-gold">Settings</h1>

      <%!-- Watching Status Banner --%>
      <div :if={@watching_file} class="bg-green-900/50 border border-green-700 rounded-lg p-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <span class="relative flex h-3 w-3">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span>
            </span>
            <div>
              <p class="text-green-300 font-medium">Watching for new encounters</p>
              <p class="text-green-400/70 text-sm">{Path.basename(@watching_file.file_path)}</p>
            </div>
          </div>
          <button
            phx-click="stop_watching"
            class="px-3 py-1.5 bg-green-800 text-green-200 text-sm rounded hover:bg-green-700"
          >
            Stop Watching
          </button>
        </div>
      </div>

      <div class="bg-zinc-800 rounded-lg p-6 border border-zinc-700">
        <h2 class="text-lg font-semibold text-zinc-100 mb-4">WoW Combat Logs Folder</h2>

        <p class="text-sm text-zinc-400 mb-4">
          Set the path to your World of Warcraft Logs folder. This is typically located at:
        </p>

        <div class="bg-zinc-900 rounded p-3 mb-4 font-mono text-sm text-zinc-300">
          <div class="mb-1 text-zinc-500"># Standard Windows install (via WSL2):</div>
          <div>/mnt/c/Program Files (x86)/World of Warcraft/_retail_/Logs</div>
          <div class="mt-2 mb-1 text-zinc-500"># If WoW is on a different drive (e.g., G:):</div>
          <div>/mnt/g/World of Warcraft/_retail_/Logs</div>
        </div>

        <form phx-submit="save_path" class="space-y-4">
          <div>
            <label for="path" class="block text-sm font-medium text-zinc-400 mb-1">
              Logs Folder Path
            </label>
            <div class="flex gap-2">
              <input
                type="text"
                name="path"
                id="path"
                value={@path_input}
                phx-change="validate_path"
                phx-debounce="300"
                class={[
                  "flex-1 bg-zinc-900 border rounded px-3 py-2 text-zinc-100 placeholder-zinc-500 focus:ring-1",
                  if(@path_valid,
                    do: "border-green-600 focus:border-green-500 focus:ring-green-500",
                    else: "border-zinc-600 focus:border-wow-gold focus:ring-wow-gold"
                  )
                ]}
                placeholder="/mnt/c/Program Files (x86)/World of Warcraft/_retail_/Logs"
              />
              <button
                type="submit"
                disabled={!@path_valid}
                class="px-4 py-2 bg-wow-gold text-zinc-900 font-semibold rounded hover:bg-yellow-400 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Save
              </button>
            </div>
            <p :if={@path_input != "" && !@path_valid} class="mt-1 text-sm text-red-400">
              Folder not found. Make sure the path exists and is accessible.
            </p>
            <p :if={@path_valid} class="mt-1 text-sm text-green-400">
              ✓ Folder found
            </p>
          </div>
        </form>
      </div>

      <%!-- File Watching Section --%>
      <div :if={@log_files != []} class="bg-zinc-800 rounded-lg p-6 border border-zinc-700">
        <h2 class="text-lg font-semibold text-zinc-100 mb-4">Start Watching</h2>

        <p class="text-sm text-zinc-400 mb-4">
          Select a combat log file to import and watch for new encounters.
          The file watcher will automatically detect when WoW writes new encounter data.
        </p>

        <%!-- Quick Action: Watch Most Recent --%>
        <div class="mb-4">
          <button
            phx-click="watch_most_recent"
            disabled={@importing}
            class="w-full px-4 py-3 bg-wow-gold text-zinc-900 font-semibold rounded hover:bg-yellow-400 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
          >
            <svg :if={!@importing} xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
            </svg>
            <span :if={@importing}>Importing...</span>
            <span :if={!@importing}>Watch Most Recent Log</span>
          </button>
          <p class="text-xs text-zinc-500 mt-1 text-center">
            {if Enum.at(@log_files, 0), do: Path.basename(Enum.at(@log_files, 0).filename), else: ""}
          </p>
        </div>

        <div class="relative my-4">
          <div class="absolute inset-0 flex items-center">
            <div class="w-full border-t border-zinc-700"></div>
          </div>
          <div class="relative flex justify-center text-sm">
            <span class="bg-zinc-800 px-2 text-zinc-500">or select a specific file</span>
          </div>
        </div>

        <%!-- Log File Selector --%>
        <form phx-change="select_log" phx-submit="watch_log" class="space-y-3">
          <select
            name="log_path"
            class="w-full bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
          >
            <option value="">Choose a log file...</option>
            <%= for log <- @log_files do %>
              <option value={log.full_path} selected={@selected_log == log.full_path}>
                {log.filename} ({format_size(log.size)})
              </option>
            <% end %>
          </select>
          <button
            type="submit"
            disabled={@importing || !@selected_log}
            class="w-full px-4 py-2 bg-zinc-700 text-zinc-200 font-medium rounded hover:bg-zinc-600 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {if @importing, do: "Importing...", else: "Import & Watch Selected"}
          </button>
        </form>
      </div>

      <%!-- Current settings summary --%>
      <div class="bg-zinc-800 rounded-lg p-6 border border-zinc-700">
        <h2 class="text-lg font-semibold text-zinc-100 mb-4">Current Configuration</h2>
        <dl class="space-y-2 text-sm">
          <div class="flex">
            <dt class="text-zinc-500 w-40">Logs Folder:</dt>
            <dd class="text-zinc-200">{@user.wow_logs_path || "Not configured"}</dd>
          </div>
          <div class="flex">
            <dt class="text-zinc-500 w-40">Last Loaded Log:</dt>
            <dd class="text-zinc-200">
              {if @user.last_loaded_log, do: Path.basename(@user.last_loaded_log), else: "None"}
            </dd>
          </div>
          <div class="flex">
            <dt class="text-zinc-500 w-40">Currently Watching:</dt>
            <dd class={if @watching_file, do: "text-green-400", else: "text-zinc-500"}>
              {if @watching_file, do: Path.basename(@watching_file.file_path), else: "None"}
            </dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end
end
