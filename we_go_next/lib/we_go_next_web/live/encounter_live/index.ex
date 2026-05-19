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

  alias WeGoNext.{EncounterStore, Accounts, Repo, CombatLogFile, Importer, ImportWorker, Rules}
  alias WeGoNext.Gold.Rebuilds
  alias WeGoNext.Rules.Ruleset
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
     |> assign(:confirm_reimport, false)
     |> assign(:rebuilding_gold, false)
     |> assign_rules_status()
     |> assign_medallion_status()}
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
         |> assign_medallion_status()
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

  @impl true
  def handle_event("seed_initial_rules", _params, socket) do
    case Rules.seed_initial_rules() do
      {:ok, %{ruleset: ruleset, criteria: criteria}} ->
        {:noreply,
         socket
         |> assign_rules_status()
         |> put_flash(
           :info,
           "Seeded #{length(criteria)} rule(s) into #{ruleset.name} v#{ruleset.version}."
         )}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to seed bundled rules: #{format_reason(reason)}")}
    end
  end

  @impl true
  def handle_event("activate_ruleset", %{"id" => id}, socket) do
    with {ruleset_id, ""} <- Integer.parse(id),
         %Ruleset{} = ruleset <- Rules.get_ruleset(ruleset_id),
         {:ok, active_ruleset} <- Rules.activate_ruleset(ruleset) do
      {:noreply,
       socket
       |> assign_rules_status()
       |> put_flash(:info, "Activated #{active_ruleset.name} v#{active_ruleset.version}.")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Ruleset not found.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to activate ruleset: #{format_reason(reason)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid ruleset id.")}
    end
  end

  @impl true
  def handle_event("promote_active_ruleset", _params, socket) do
    case Rules.promote_active_ruleset_to_gold() do
      {:ok, %{ruleset: ruleset, criteria: criteria}} ->
        {:noreply,
         socket
         |> assign_rules_status()
         |> assign_medallion_status()
         |> put_flash(
           :info,
           "Promoted #{length(criteria)} rule(s) from #{ruleset.name} v#{ruleset.version}."
         )}

      {:error, :active_ruleset_not_found} ->
        {:noreply, put_flash(socket, :error, "Activate a ruleset before promoting rules.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to promote active rules: #{format_reason(reason)}")}
    end
  end

  @impl true
  def handle_event("rebuild_gold_facts", _params, socket) do
    cond do
      socket.assigns.rebuilding_gold ->
        {:noreply, socket}

      is_nil(socket.assigns.rules_status.active_ruleset) ->
        {:noreply, put_flash(socket, :error, "Activate a ruleset before rebuilding gold facts.")}

      socket.assigns.medallion_status.gold_encounters_count == 0 ->
        {:noreply, put_flash(socket, :error, "Import a log before rebuilding gold facts.")}

      true ->
        {:noreply,
         socket
         |> assign(:rebuilding_gold, true)
         |> assign(:error, nil)
         |> start_async(:rebuild_gold, fn -> Rebuilds.rebuild_all(ruleset: :active) end)}
    end
  end

  @impl true
  def handle_event("force_reimport_selected_log", _params, socket) do
    case selected_reimport_path(socket.assigns.selected_log, socket.assigns.log_path) do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a log before forcing reimport.")}

      path ->
        do_import(socket, path, force_reimport: true)
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
         |> assign(:encounter_records, EncounterStore.list_encounter_records())
         |> assign(:log_path, EncounterStore.current_log_path())
         |> assign(:combat_log_file, EncounterStore.current_combat_log_file())
         |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
         |> assign_rules_status()
         |> assign_medallion_status()
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
    {:noreply,
     socket
     |> assign(:encounter_records, EncounterStore.list_encounter_records())
     |> assign_medallion_status()}
  end

  @impl true
  def handle_info({:import_progress, :saving}, socket) do
    {:noreply,
     assign(socket, :import_progress, %{
       percent: 100,
       encounters_found: socket.assigns.import_progress[:encounters_found] || 0,
       status: :saving
     })}
  end

  @impl true
  def handle_info(
        {:import_progress, %{bytes_read: bytes, total_bytes: total, encounters_found: found}},
        socket
      ) do
    percent = if total > 0, do: round(bytes / total * 100), else: 0
    prev_found = socket.assigns.import_progress[:encounters_found] || 0

    socket =
      if found > prev_found do
        socket
        |> assign(:encounter_records, EncounterStore.list_encounter_records())
        |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
        |> assign_medallion_status()
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
     |> assign(:encounter_records, EncounterStore.list_encounter_records())
     |> assign(:log_path, new_clf.file_path)
     |> assign(:combat_log_file, new_clf)
     |> assign(:log_files, reload_log_files(socket.assigns.user))
     |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
     |> assign_medallion_status()
     |> put_flash(
       :info,
       "Log rotation detected! Switched to #{Path.basename(new_clf.file_path)} (#{count} encounters)"
     )}
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
         |> assign(:imported_logs, list_imported_logs(socket.assigns.user.id))
         |> assign_medallion_status()
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
         |> assign_medallion_status()
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
  def handle_async(:rebuild_gold, {:ok, result}, socket) do
    case result do
      {:ok, totals} ->
        {:noreply,
         socket
         |> assign(:rebuilding_gold, false)
         |> assign_medallion_status()
         |> put_flash(:info, rebuild_message(totals))}

      {:error, %{encounter_id: encounter_id, reason: reason}} ->
        {:noreply,
         socket
         |> assign(:rebuilding_gold, false)
         |> assign_medallion_status()
         |> put_flash(
           :error,
           "Failed to rebuild gold facts for encounter #{encounter_id}: #{format_reason(reason)}"
         )}
    end
  end

  @impl true
  def handle_async(:rebuild_gold, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:rebuilding_gold, false)
     |> assign_medallion_status()
     |> put_flash(:error, "Failed to rebuild gold facts: #{inspect(reason)}")}
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
        <div class="flex items-center gap-4">
          <.link navigate={~p"/failures"} class="text-sm text-zinc-400 hover:text-zinc-200">
            Failures
          </.link>
          <.link navigate={~p"/settings"} class="text-sm text-zinc-400 hover:text-zinc-200">
            Settings
          </.link>
        </div>
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

      <.rules_operations status={@rules_status} />

      <.medallion_operations
        status={@medallion_status}
        active_ruleset={@rules_status.active_ruleset}
        rebuilding_gold={@rebuilding_gold}
        loading={@loading}
        selected_log={selected_reimport_path(@selected_log, @log_path)}
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

  defp rules_operations(assigns) do
    ~H"""
    <section class="rounded-lg border border-zinc-700 bg-zinc-900/70 p-4">
      <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">
            Rules Operations
          </h2>
          <div class="mt-2 flex flex-wrap gap-2 text-sm">
            <span class={status_badge_class(@status.active_ruleset)}>
              {active_ruleset_label(@status.active_ruleset)}
            </span>
            <span class="rounded border border-zinc-700 px-3 py-1 text-zinc-300">
              {@status.authored_rules_count} authored rule{plural(@status.authored_rules_count)}
            </span>
            <span class="rounded border border-zinc-700 px-3 py-1 text-zinc-300">
              {@status.promoted_snapshots_count} gold snapshot{plural(@status.promoted_snapshots_count)}
            </span>
          </div>
          <p :if={@status.active_ruleset} class="mt-2 text-sm text-zinc-500">
            Active ruleset has {@status.active_authored_rules_count} authored rule{plural(@status.active_authored_rules_count)}
            and {@status.active_promoted_snapshots_count} promoted snapshot{plural(@status.active_promoted_snapshots_count)}.
          </p>
        </div>

        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            phx-click="seed_initial_rules"
            class="rounded bg-zinc-700 px-3 py-2 text-sm font-semibold text-zinc-100 hover:bg-zinc-600"
          >
            Seed Bundled Rules
          </button>
          <button
            type="button"
            phx-click="promote_active_ruleset"
            disabled={is_nil(@status.active_ruleset)}
            class="rounded bg-wow-gold px-3 py-2 text-sm font-semibold text-zinc-950 hover:bg-yellow-300 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Promote Active Rules
          </button>
        </div>
      </div>

      <div :if={@status.rulesets != []} class="mt-4 overflow-hidden rounded border border-zinc-800">
        <div class="grid grid-cols-[1fr_auto_auto] gap-3 bg-zinc-950 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-zinc-500">
          <span>Ruleset</span>
          <span>Status</span>
          <span>Action</span>
        </div>
        <div
          :for={ruleset <- @status.rulesets}
          class="grid grid-cols-[1fr_auto_auto] items-center gap-3 border-t border-zinc-800 px-3 py-2 text-sm"
        >
          <div>
            <span class="font-medium text-zinc-100">{ruleset.name}</span>
            <span class="ml-2 text-zinc-500">v{ruleset.version}</span>
          </div>
          <span class="text-zinc-400">{ruleset.status}</span>
          <button
            :if={ruleset.status != "active"}
            type="button"
            phx-click="activate_ruleset"
            phx-value-id={ruleset.id}
            class="rounded border border-zinc-600 px-2 py-1 text-xs font-semibold text-zinc-200 hover:bg-zinc-800"
          >
            Activate
          </button>
          <span :if={ruleset.status == "active"} class="text-xs text-zinc-500">Active</span>
        </div>
      </div>
    </section>
    """
  end

  defp assign_rules_status(socket) do
    assign(socket, :rules_status, Rules.operations_status())
  end

  defp medallion_operations(assigns) do
    ~H"""
    <section class="rounded-lg border border-zinc-700 bg-zinc-900/70 p-4">
      <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">
            Medallion Recompute
          </h2>
          <div class="mt-2 flex flex-wrap gap-2 text-sm">
            <span class="rounded border border-zinc-700 px-3 py-1 text-zinc-300">
              {@status.gold_encounters_count} gold encounter{plural(@status.gold_encounters_count)}
            </span>
            <span class="rounded border border-zinc-700 px-3 py-1 text-zinc-300">
              {@status.failure_facts_count} failure fact{plural(@status.failure_facts_count)}
            </span>
            <span class="rounded border border-zinc-700 px-3 py-1 text-zinc-300">
              {selected_log_label(@selected_log)}
            </span>
          </div>
          <div class="mt-3 grid gap-2 text-sm text-zinc-500 lg:grid-cols-2">
            <p>
              Use gold rebuild after rules, promotions, or gold fact logic changed. It reads existing silver rows and keeps imported parser output.
            </p>
            <p>
              Use force reimport after parser or silver projection logic changed. It reparses the selected log and recomputes derived rows.
            </p>
          </div>
        </div>

        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            phx-click="rebuild_gold_facts"
            disabled={
              @rebuilding_gold or is_nil(@active_ruleset) or @status.gold_encounters_count == 0
            }
            class="rounded bg-wow-gold px-3 py-2 text-sm font-semibold text-zinc-950 hover:bg-yellow-300 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {if @rebuilding_gold, do: "Rebuilding Gold...", else: "Rebuild Gold Facts"}
          </button>
          <button
            type="button"
            phx-click="force_reimport_selected_log"
            disabled={@loading or is_nil(@selected_log)}
            data-confirm="Force reimport this log? Existing encounters for the selected log will be replaced before parsing."
            class="rounded bg-zinc-700 px-3 py-2 text-sm font-semibold text-zinc-100 hover:bg-zinc-600 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Force Reimport Log
          </button>
        </div>
      </div>
    </section>
    """
  end

  defp assign_medallion_status(socket) do
    assign(socket, :medallion_status, Rebuilds.status())
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
            parsed > 0 and disk_size - parsed > 100

          {:error, _} ->
            false
        end
    end
  end

  defp active_ruleset_label(nil), do: "No active ruleset"

  defp active_ruleset_label(%Ruleset{name: name, version: version}),
    do: "Active: #{name} v#{version}"

  defp status_badge_class(nil) do
    "rounded border border-amber-500/40 bg-amber-500/10 px-3 py-1 text-amber-300"
  end

  defp status_badge_class(%Ruleset{}) do
    "rounded border border-green-500/40 bg-green-500/10 px-3 py-1 text-green-300"
  end

  defp plural(1), do: ""
  defp plural(_count), do: "s"

  defp selected_reimport_path(selected_log, log_path) do
    cond do
      is_binary(selected_log) and String.trim(selected_log) != "" -> selected_log
      is_binary(log_path) and String.trim(log_path) != "" -> log_path
      true -> nil
    end
  end

  defp selected_log_label(nil), do: "No log selected"
  defp selected_log_label(path), do: Path.basename(path)

  defp rebuild_message(totals) do
    "Rebuilt gold facts for #{totals.encounters} encounter#{plural(totals.encounters)}. " <>
      "Deleted #{totals.deleted} stale row#{plural(totals.deleted)}, inserted #{totals.inserted} row#{plural(totals.inserted)}."
  end

  defp format_reason(%Ecto.Changeset{} = changeset), do: inspect(changeset.errors)
  defp format_reason(reason), do: inspect(reason)
end
