defmodule WeGoNextWeb.SettingsLive do
  use WeGoNextWeb, :live_view

  alias WeGoNext.{Accounts, FileWatcher}

  @impl true
  def mount(_params, _session, socket) do
    user = Accounts.get_or_create_default_user()
    watching_file = FileWatcher.current_file()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:user, user)
     |> assign(:path_input, user.wow_logs_path || "")
     |> assign(:path_valid, check_path_valid(user.wow_logs_path))
     |> assign(:watching_file, watching_file)}
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
         |> put_flash(:info, "WoW Logs folder saved!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save path")}
    end
  end

  @impl true
  def handle_event("stop_watching", _params, socket) do
    FileWatcher.stop_watching()
    {:noreply, assign(socket, :watching_file, nil) |> put_flash(:info, "Cleared current log")}
  end

  defp check_path_valid(nil), do: false
  defp check_path_valid(""), do: false

  defp check_path_valid(path) do
    File.dir?(path)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.back navigate={~p"/"}>Back to encounters</.back>

      <h1 class="text-2xl font-bold text-wow-gold">Settings</h1>

      <%!-- Current Log Status Banner --%>
      <div :if={@watching_file} class="bg-green-900/50 border border-green-700 rounded-lg p-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <span class="relative flex h-3 w-3">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span>
            </span>
            <div>
              <p class="text-green-300 font-medium">Current log</p>
              <p class="text-green-400/70 text-sm">{Path.basename(@watching_file.file_path)}</p>
            </div>
          </div>
          <button
            phx-click="stop_watching"
            class="px-3 py-1.5 bg-green-800 text-green-200 text-sm rounded hover:bg-green-700"
          >
            Clear
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
            <dt class="text-zinc-500 w-40">Current Log:</dt>
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
