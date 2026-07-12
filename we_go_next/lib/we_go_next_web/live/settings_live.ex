defmodule WeGoNextWeb.SettingsLive do
  use WeGoNextWeb, :live_view

  alias WeGoNext.{Accounts, CombatLogFile, FileWatcher, Repo}

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
     |> assign(:warcraft_logs_client_name_input, user.warcraft_logs_client_name || "")
     |> assign(:document_r2_endpoint_input, user.document_r2_endpoint || "")
     |> assign(:document_r2_bucket_input, user.document_r2_bucket || "")
     |> assign(:document_r2_access_key_id_input, user.document_r2_access_key_id || "")
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
  def handle_event(
        "save_warcraft_logs_credentials",
        %{"warcraft_logs" => %{"client_name" => client_name, "api_key" => api_key}},
        socket
      ) do
    user = socket.assigns.user
    api_key = String.trim(api_key || "")

    result =
      if api_key == "" and Accounts.warcraft_logs_credentials_configured?(user) do
        Accounts.update_warcraft_logs_client_name(user, client_name)
      else
        Accounts.set_warcraft_logs_credentials(user, client_name, api_key)
      end

    case result do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:warcraft_logs_client_name_input, user.warcraft_logs_client_name || "")
         |> put_flash(:info, "Warcraft Logs credentials saved")}

      {:error, :client_name_required} ->
        {:noreply, put_flash(socket, :error, "Warcraft Logs client name is required")}

      {:error, :api_key_required} ->
        {:noreply, put_flash(socket, :error, "Warcraft Logs API key is required")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save Warcraft Logs credentials")}
    end
  end

  @impl true
  def handle_event("clear_warcraft_logs_credentials", _params, socket) do
    case Accounts.clear_warcraft_logs_credentials(socket.assigns.user) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:warcraft_logs_client_name_input, "")
         |> put_flash(:info, "Warcraft Logs credentials cleared")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to clear Warcraft Logs credentials")}
    end
  end

  @impl true
  def handle_event(
        "save_document_r2_credentials",
        %{
          "document_r2" => %{
            "endpoint" => endpoint,
            "bucket" => bucket,
            "access_key_id" => access_key_id,
            "secret_access_key" => secret_access_key
          }
        },
        socket
      ) do
    user = socket.assigns.user
    secret_access_key = String.trim(secret_access_key || "")

    result =
      if secret_access_key == "" and Accounts.document_r2_configured?(user) do
        Accounts.update_document_r2_settings(user, endpoint, bucket, access_key_id)
      else
        Accounts.set_document_r2_credentials(
          user,
          endpoint,
          bucket,
          access_key_id,
          secret_access_key
        )
      end

    case result do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign_document_r2_inputs(user)
         |> put_flash(:info, "R2 document store credentials saved")}

      {:error, :endpoint_required} ->
        {:noreply, put_flash(socket, :error, "R2 endpoint is required")}

      {:error, :bucket_required} ->
        {:noreply, put_flash(socket, :error, "R2 bucket is required")}

      {:error, :access_key_id_required} ->
        {:noreply, put_flash(socket, :error, "R2 access key ID is required")}

      {:error, :secret_access_key_required} ->
        {:noreply, put_flash(socket, :error, "R2 secret access key is required")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save R2 document store credentials")}
    end
  end

  @impl true
  def handle_event("clear_document_r2_credentials", _params, socket) do
    case Accounts.clear_document_r2_credentials(socket.assigns.user) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign_document_r2_inputs(user)
         |> put_flash(:info, "R2 document store credentials cleared")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to clear R2 document store credentials")}
    end
  end

  @impl true
  def handle_event("stop_watching", _params, socket) do
    case socket.assigns.watching_file do
      %CombatLogFile{} = combat_log_file ->
        with {:ok, _updated_log} <-
               combat_log_file
               |> CombatLogFile.changeset(%{watch_enabled: false})
               |> Repo.update() do
          FileWatcher.stop_watching()

          {:noreply,
           assign(socket, :watching_file, nil) |> put_flash(:info, "Stopped watching log")}
        else
          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to stop watching log")}
        end

      nil ->
        {:noreply, socket}
    end
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

      <div class="bg-zinc-800 rounded-lg p-6 border border-zinc-700">
        <div class="mb-4 flex items-center justify-between gap-4">
          <div>
            <h2 class="text-lg font-semibold text-zinc-100">Warcraft Logs Credentials</h2>
            <p class="mt-1 text-sm text-zinc-400">
              Saved locally for report fetches. The key is encrypted before it is stored.
            </p>
          </div>
          <span class={[
            "rounded px-2 py-1 text-xs font-semibold",
            if(warcraft_logs_configured?(@user),
              do: "bg-green-900 text-green-300",
              else: "bg-zinc-700 text-zinc-300"
            )
          ]}>
            {if warcraft_logs_configured?(@user), do: "Configured", else: "Not configured"}
          </span>
        </div>

        <form phx-submit="save_warcraft_logs_credentials" class="space-y-4">
          <div>
            <label
              for="warcraft_logs_client_name"
              class="block text-sm font-medium text-zinc-400 mb-1"
            >
              Client Name
            </label>
            <input
              type="text"
              name="warcraft_logs[client_name]"
              id="warcraft_logs_client_name"
              value={@warcraft_logs_client_name_input}
              class="w-full bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 placeholder-zinc-500 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
              placeholder="Warcraft Logs client name"
            />
          </div>

          <div>
            <label for="warcraft_logs_api_key" class="block text-sm font-medium text-zinc-400 mb-1">
              API Key
            </label>
            <input
              type="password"
              name="warcraft_logs[api_key]"
              id="warcraft_logs_api_key"
              value=""
              autocomplete="off"
              class="w-full bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 placeholder-zinc-500 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
              placeholder={if warcraft_logs_configured?(@user), do: "Saved key unchanged", else: "Paste API key"}
            />
            <p class="mt-1 text-xs text-zinc-500">
              Leave blank to keep the saved key when changing only the client name.
            </p>
          </div>

          <div class="flex items-center gap-2">
            <button
              type="submit"
              class="px-4 py-2 bg-wow-gold text-zinc-900 font-semibold rounded hover:bg-yellow-400"
            >
              Save Credentials
            </button>
            <button
              :if={warcraft_logs_configured?(@user)}
              type="button"
              phx-click="clear_warcraft_logs_credentials"
              data-confirm="Clear saved Warcraft Logs credentials?"
              class="px-4 py-2 bg-zinc-700 text-zinc-100 font-semibold rounded hover:bg-zinc-600"
            >
              Clear
            </button>
          </div>
        </form>
      </div>

      <div class="bg-zinc-800 rounded-lg p-6 border border-zinc-700">
        <div class="mb-4 flex items-center justify-between gap-4">
          <div>
            <h2 class="text-lg font-semibold text-zinc-100">R2 Document Store</h2>
            <p class="mt-1 text-sm text-zinc-400">
              Saved locally for parser uploads. The secret access key is encrypted before it is stored.
            </p>
          </div>
          <span class={[
            "rounded px-2 py-1 text-xs font-semibold",
            if(document_r2_configured?(@user),
              do: "bg-green-900 text-green-300",
              else: "bg-zinc-700 text-zinc-300"
            )
          ]}>
            {if document_r2_configured?(@user), do: "Configured", else: "Not configured"}
          </span>
        </div>

        <form phx-submit="save_document_r2_credentials" class="space-y-4">
          <div>
            <label for="document_r2_endpoint" class="block text-sm font-medium text-zinc-400 mb-1">
              Endpoint
            </label>
            <input
              type="url"
              name="document_r2[endpoint]"
              id="document_r2_endpoint"
              value={@document_r2_endpoint_input}
              class="w-full bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 placeholder-zinc-500 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
              placeholder="https://<account-id>.r2.cloudflarestorage.com"
            />
          </div>

          <div>
            <label for="document_r2_bucket" class="block text-sm font-medium text-zinc-400 mb-1">
              Bucket
            </label>
            <input
              type="text"
              name="document_r2[bucket]"
              id="document_r2_bucket"
              value={@document_r2_bucket_input}
              class="w-full bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 placeholder-zinc-500 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
              placeholder="we-go-next-documents"
            />
          </div>

          <div>
            <label
              for="document_r2_access_key_id"
              class="block text-sm font-medium text-zinc-400 mb-1"
            >
              Access Key ID
            </label>
            <input
              type="text"
              name="document_r2[access_key_id]"
              id="document_r2_access_key_id"
              value={@document_r2_access_key_id_input}
              class="w-full bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 placeholder-zinc-500 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
              placeholder="R2 access key ID"
            />
          </div>

          <div>
            <label
              for="document_r2_secret_access_key"
              class="block text-sm font-medium text-zinc-400 mb-1"
            >
              Secret Access Key
            </label>
            <input
              type="password"
              name="document_r2[secret_access_key]"
              id="document_r2_secret_access_key"
              value=""
              autocomplete="off"
              class="w-full bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 placeholder-zinc-500 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
              placeholder={if document_r2_configured?(@user), do: "Saved key unchanged", else: "Paste secret access key"}
            />
            <p class="mt-1 text-xs text-zinc-500">
              Leave blank to keep the saved secret when changing endpoint, bucket, or access key ID.
            </p>
          </div>

          <div class="flex items-center gap-2">
            <button
              type="submit"
              class="px-4 py-2 bg-wow-gold text-zinc-900 font-semibold rounded hover:bg-yellow-400"
            >
              Save Credentials
            </button>
            <button
              :if={document_r2_configured?(@user)}
              type="button"
              phx-click="clear_document_r2_credentials"
              data-confirm="Clear saved R2 document store credentials?"
              class="px-4 py-2 bg-zinc-700 text-zinc-100 font-semibold rounded hover:bg-zinc-600"
            >
              Clear
            </button>
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
          <div class="flex">
            <dt class="text-zinc-500 w-40">Warcraft Logs:</dt>
            <dd class={if warcraft_logs_configured?(@user), do: "text-green-400", else: "text-zinc-500"}>
              {if warcraft_logs_configured?(@user), do: "#{@user.warcraft_logs_client_name} (key saved)", else: "Not configured"}
            </dd>
          </div>
          <div class="flex">
            <dt class="text-zinc-500 w-40">R2 Documents:</dt>
            <dd class={if document_r2_configured?(@user), do: "text-green-400", else: "text-zinc-500"}>
              {if document_r2_configured?(@user), do: "#{@user.document_r2_bucket} (key saved)", else: "Not configured"}
            </dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end

  defp warcraft_logs_configured?(user), do: Accounts.warcraft_logs_credentials_configured?(user)

  defp document_r2_configured?(user), do: Accounts.document_r2_configured?(user)

  defp assign_document_r2_inputs(socket, user) do
    socket
    |> assign(:document_r2_endpoint_input, user.document_r2_endpoint || "")
    |> assign(:document_r2_bucket_input, user.document_r2_bucket || "")
    |> assign(:document_r2_access_key_id_input, user.document_r2_access_key_id || "")
  end
end
