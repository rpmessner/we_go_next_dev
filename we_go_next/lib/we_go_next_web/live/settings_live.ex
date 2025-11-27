defmodule WeGoNextWeb.SettingsLive do
  use WeGoNextWeb, :live_view

  alias WeGoNext.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = Accounts.get_or_create_default_user()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:user, user)
     |> assign(:path_input, user.wow_logs_path || "")
     |> assign(:path_valid, check_path_valid(user.wow_logs_path))
     |> assign(:log_files, [])
     |> assign(:saving, false)
     |> maybe_load_log_files(user.wow_logs_path)}
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
         |> maybe_load_log_files(path)
         |> put_flash(:info, "WoW Logs folder saved!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save path")}
    end
  end

  defp check_path_valid(nil), do: false
  defp check_path_valid(""), do: false

  defp check_path_valid(path) do
    File.dir?(path)
  end

  defp maybe_load_log_files(socket, nil), do: assign(socket, :log_files, [])
  defp maybe_load_log_files(socket, ""), do: assign(socket, :log_files, [])

  defp maybe_load_log_files(socket, path) do
    case Accounts.list_combat_logs_in_path(path) do
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

        <%!-- Show found log files --%>
        <div :if={@log_files != []} class="mt-6">
          <h3 class="text-sm font-medium text-zinc-400 mb-2">
            Found {length(@log_files)} combat log files:
          </h3>
          <div class="bg-zinc-900 rounded max-h-48 overflow-y-auto">
            <div
              :for={log <- Enum.take(@log_files, 10)}
              class="px-3 py-2 border-b border-zinc-800 last:border-0 text-sm"
            >
              <span class="text-zinc-200">{log.filename}</span>
              <span class="text-zinc-500 ml-2">({format_size(log.size)})</span>
            </div>
            <div :if={length(@log_files) > 10} class="px-3 py-2 text-zinc-500 text-sm">
              ... and {length(@log_files) - 10} more
            </div>
          </div>
        </div>
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
        </dl>
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
end
