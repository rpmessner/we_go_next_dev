defmodule CombatLogParserWeb.EncounterLive.Index do
  use CombatLogParserWeb, :live_view

  alias CombatLogParser.{EncounterStore, Encounter}
  alias CombatLogParser.Analyzers.DeathAnalyzer

  @default_log_dir "/mnt/g/World of Warcraft/_retail_/Logs"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CombatLogParser.PubSub, "encounters")
    end

    encounters = EncounterStore.list_encounters()
    log_path = EncounterStore.current_log_path()

    {:ok,
     socket
     |> assign(:page_title, "Encounters")
     |> assign(:encounters, encounters)
     |> assign(:log_path, log_path)
     |> assign(:log_input, log_path || "")
     |> assign(:loading, false)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("load_log", %{"log_path" => path}, socket) do
    path = String.trim(path)

    if path == "" do
      {:noreply, assign(socket, :error, "Please enter a log file path")}
    else
      {:noreply,
       socket
       |> assign(:loading, true)
       |> assign(:error, nil)
       |> start_async(:load_log, fn -> EncounterStore.load_log(path) end)}
    end
  end

  @impl true
  def handle_event("update_log_input", %{"log_path" => path}, socket) do
    {:noreply, assign(socket, :log_input, path)}
  end

  @impl true
  def handle_async(:load_log, {:ok, result}, socket) do
    case result do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:encounters, EncounterStore.list_encounters())
         |> assign(:log_path, EncounterStore.current_log_path())
         |> put_flash(:info, "Loaded #{count} encounters")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Failed to load log: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_async(:load_log, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, "Failed to load log: #{inspect(reason)}")}
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
        <span class="text-sm text-zinc-500">Hand of Algalon</span>
      </div>

      <%!-- Log file loader --%>
      <div class="bg-zinc-800 rounded-lg p-4 border border-zinc-700">
        <form phx-submit="load_log" class="flex gap-4">
          <div class="flex-1">
            <label for="log_path" class="block text-sm font-medium text-zinc-400 mb-1">
              Combat Log Path
            </label>
            <input
              type="text"
              name="log_path"
              id="log_path"
              value={@log_input}
              phx-change="update_log_input"
              placeholder={@default_log_dir <> "/WoWCombatLog-*.txt"}
              class="w-full bg-zinc-900 border border-zinc-600 rounded px-3 py-2 text-zinc-100 placeholder-zinc-500 focus:border-wow-gold focus:ring-1 focus:ring-wow-gold"
            />
          </div>
          <div class="flex items-end">
            <button
              type="submit"
              disabled={@loading}
              class="px-4 py-2 bg-wow-gold text-zinc-900 font-semibold rounded hover:bg-yellow-400 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {if @loading, do: "Loading...", else: "Load Log"}
            </button>
          </div>
        </form>
        <p :if={@error} class="mt-2 text-sm text-red-400">{@error}</p>
        <p :if={@log_path} class="mt-2 text-sm text-zinc-500">
          Current: {Path.basename(@log_path)}
        </p>
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
                  if(encounter.success, do: "bg-green-900 text-green-300", else: "bg-red-900 text-red-300")
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
      <div :if={@encounters == [] && !@loading} class="text-center py-12 text-zinc-500">
        <p class="text-lg">No encounters loaded</p>
        <p class="text-sm mt-2">Enter the path to a WoW combat log file above</p>
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

  defp death_count(encounter) do
    encounter
    |> DeathAnalyzer.analyze()
    |> length()
  end
end
