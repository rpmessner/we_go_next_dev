defmodule WeGoNext.FileWatcher do
  @moduledoc """
  Tracks the currently loaded combat log file and incrementally syncs appended
  completed encounters.

  WoW can write combat log lines during a pull before the matching
  ENCOUNTER_END exists. The importer only advances progress through completed
  encounter boundaries, so polling a current log is safe even if the file
  changes mid-pull.

  The poll also watches the logs directory for rotation: when WoW creates a
  newer `WoWCombatLog-*.txt` (new session), the watcher imports it, switches
  tracking to it, and broadcasts `{:log_rotated, clf, count}` on the
  `"encounters"` topic. `watch_directory/2` arms the same detection before any
  file is tracked (e.g. dashboard opened before the raid's log exists).
  """
  use GenServer
  import Ecto.Query
  require Logger

  alias WeGoNext.{CombatLogFile, Importer, Repo}

  @poll_interval_ms 5_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sets the current combat log file being viewed.
  Accepts either a CombatLogFile struct or a file path string.
  """
  def watch(file_or_path)

  def watch(%CombatLogFile{source: :live} = clf) do
    case claim_watch(clf) do
      {:ok, updated_clf} -> GenServer.cast(__MODULE__, {:watch, updated_clf})
      {:error, reason} -> {:error, reason}
    end
  end

  def watch(%CombatLogFile{}), do: {:error, :watch_disabled}

  def watch(file_path) when is_binary(file_path) do
    case Repo.get_by(CombatLogFile, file_path: file_path) do
      nil -> {:error, :not_found}
      clf -> watch(clf)
    end
  end

  # Exclusively marks the log as watch-enabled; only the user's newest live
  # log may hold the flag. Also used when rotation switches tracking.
  defp claim_watch(%CombatLogFile{source: :live} = clf) do
    Repo.transaction(fn ->
      fresh_clf = Repo.get!(CombatLogFile, clf.id)

      newest_live_log_id =
        CombatLogFile
        |> where([row], row.user_id == ^fresh_clf.user_id and row.source == :live)
        |> Repo.all()
        |> Enum.max_by(&log_order_key/1, fn -> nil end)
        |> case do
          %CombatLogFile{id: id} -> id
          nil -> nil
        end

      if newest_live_log_id != fresh_clf.id do
        Repo.rollback(:not_newest_live_log)
      end

      CombatLogFile
      |> where([row], row.user_id == ^fresh_clf.user_id and row.source == :live)
      |> Repo.update_all(set: [watch_enabled: false])

      fresh_clf
      |> CombatLogFile.changeset(%{watch_enabled: true})
      |> Repo.update!()
    end)
  end

  defp claim_watch(%CombatLogFile{}), do: {:error, :watch_disabled}

  defp log_order_key(combat_log_file) do
    datetime = CombatLogFile.filename_datetime(combat_log_file.file_path)

    {if(datetime, do: NaiveDateTime.to_erl(datetime), else: {{0, 1, 1}, {0, 0, 0}}),
     combat_log_file.id}
  end

  @doc """
  Watches a logs directory for newly created combat logs when no file is
  tracked yet. No-op while a file is already being tracked (its directory is
  scanned as part of the regular poll).
  """
  def watch_directory(logs_dir, user_id) when is_binary(logs_dir) do
    GenServer.call(__MODULE__, {:watch_directory, logs_dir, user_id})
  end

  @doc """
  Clears the current file reference.
  """
  def stop_watching do
    GenServer.call(__MODULE__, :stop_watching)
  end

  @doc """
  Returns the currently tracked file.
  """
  def current_file do
    GenServer.call(__MODULE__, :current_file)
  end

  @doc """
  Refreshes the tracked struct only when it is tracking the same database row.
  """
  def refresh_if_tracking(%CombatLogFile{} = clf) do
    GenServer.call(__MODULE__, {:refresh_if_tracking, clf})
  end

  @doc """
  Returns the directory of the current log file.
  """
  def watched_directory do
    GenServer.call(__MODULE__, :watched_directory)
  end

  @doc """
  Immediately checks the current watched file for appended completed encounters.
  """
  def sync_now do
    GenServer.call(__MODULE__, :sync_now, 30_000)
  end

  @doc false
  def set_poll_interval_ms(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    GenServer.call(__MODULE__, {:set_poll_interval_ms, interval_ms})
  end

  def set_poll_interval_ms(false) do
    GenServer.call(__MODULE__, {:set_poll_interval_ms, false})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    interval_ms =
      Keyword.get(
        opts,
        :poll_interval_ms,
        Application.get_env(:we_go_next, :file_watcher_poll_interval_ms, @poll_interval_ms)
      )

    {:ok, initial_state(interval_ms)}
  end

  defp initial_state(poll_interval_ms) do
    %{
      clf: nil,
      logs_dir: nil,
      user_id: nil,
      known_files: nil,
      timer_ref: nil,
      sync_ref: nil,
      sync_kind: nil,
      poll_interval_ms: poll_interval_ms
    }
  end

  @impl true
  def handle_cast({:watch, %CombatLogFile{} = clf}, state) do
    logs_dir = Path.dirname(clf.file_path)
    Logger.info("FileWatcher: Now tracking #{Path.basename(clf.file_path)}")

    new_state = %{
      clf: clf,
      logs_dir: logs_dir,
      user_id: clf.user_id,
      known_files: nil,
      timer_ref: state_timer_ref(state),
      sync_ref: state_sync_ref(state),
      sync_kind: state_sync_kind(state),
      poll_interval_ms: state_poll_interval_ms(state)
    }

    {:noreply, schedule_poll(new_state)}
  end

  @impl true
  def handle_call(:stop_watching, _from, state) do
    Logger.info("FileWatcher: Stopped tracking")

    {:reply, :ok, stop_watching_state(state)}
  end

  @impl true
  def handle_call({:watch_directory, logs_dir, user_id}, _from, state) do
    state = ensure_runtime_state(state)

    cond do
      not is_nil(state.clf) ->
        {:reply, :ok, state}

      state.logs_dir == logs_dir and not is_nil(state.known_files) ->
        {:reply, :ok, schedule_poll(%{state | user_id: user_id})}

      true ->
        Logger.info("FileWatcher: Watching #{logs_dir} for new combat logs")

        {:reply, :ok,
         schedule_poll(%{
           state
           | logs_dir: logs_dir,
             user_id: user_id,
             known_files: snapshot_live_logs(logs_dir)
         })}
    end
  end

  @impl true
  def handle_call(:current_file, _from, state) do
    state = ensure_runtime_state(state)
    {:reply, state.clf, schedule_poll(state)}
  end

  @impl true
  def handle_call({:refresh_if_tracking, %CombatLogFile{} = clf}, _from, state) do
    if state.clf && state.clf.id == clf.id do
      logs_dir = Path.dirname(clf.file_path)
      Logger.info("FileWatcher: Refreshed tracking for #{Path.basename(clf.file_path)}")

      {:reply, true, schedule_poll(%{state | clf: clf, logs_dir: logs_dir, user_id: clf.user_id})}
    else
      {:reply, false, state}
    end
  end

  @impl true
  def handle_call(:watched_directory, _from, state) do
    state = ensure_runtime_state(state)
    {:reply, state.logs_dir, schedule_poll(state)}
  end

  @impl true
  def handle_call({:set_poll_interval_ms, interval_ms}, _from, state) do
    {:reply, :ok,
     state |> ensure_runtime_state() |> Map.put(:poll_interval_ms, interval_ms) |> schedule_poll()}
  end

  @impl true
  def handle_call(:sync_now, _from, state) do
    state = ensure_runtime_state(state)

    cond do
      is_nil(state.clf) ->
        {:reply, {:ok, 0}, state}

      not watch_enabled?(state.clf) ->
        {:reply, {:error, :watch_disabled}, stop_watching_state(state)}

      is_nil(state.sync_ref) ->
        {reply, state} = sync_current_file(state)
        {:reply, reply, schedule_poll(state)}

      true ->
        {:reply, {:error, :already_syncing}, state}
    end
  end

  @impl true
  def handle_info(:poll, %{sync_ref: sync_ref} = state) when not is_nil(sync_ref) do
    {:noreply, %{state | timer_ref: nil}}
  end

  def handle_info(:poll, %{clf: nil, logs_dir: nil} = state) do
    {:noreply, %{state | timer_ref: nil}}
  end

  def handle_info(:poll, state) do
    state = %{state | timer_ref: nil}

    cond do
      state.clf && not watch_enabled?(state.clf) ->
        {:noreply, stop_watching_state(state)}

      state.clf && watched_file_has_new_content?(state.clf) ->
        {:noreply, start_async_sync(state)}

      new_log_path = rotation_candidate(state) ->
        {:noreply, start_rotation_import(state, new_log_path)}

      true ->
        {:noreply, state |> maybe_refresh_snapshot() |> schedule_poll()}
    end
  end

  def handle_info({ref, result}, %{sync_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    state = handle_task_result(state.sync_kind, result, state)

    {:noreply, state |> Map.put(:sync_ref, nil) |> Map.put(:sync_kind, nil) |> schedule_poll()}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{sync_ref: ref} = state) do
    Logger.warning("FileWatcher: Sync task exited: #{inspect(reason)}")

    {:noreply,
     state
     |> Map.put(:sync_ref, nil)
     |> Map.put(:sync_kind, nil)
     |> refresh_tracked_file()
     |> schedule_poll()}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp handle_task_result(
         :rotate,
         {:ok, %{file: %CombatLogFile{} = clf, new_encounters: count}},
         state
       ) do
    case claim_watch(clf) do
      {:ok, claimed_clf} ->
        Logger.info(
          "FileWatcher: Rotated to #{Path.basename(claimed_clf.file_path)} (#{count} encounter#{plural(count)})"
        )

        maybe_broadcast_loaded(count)

        Phoenix.PubSub.broadcast(
          WeGoNext.PubSub,
          "encounters",
          {:log_rotated, claimed_clf, count}
        )

        %{
          state
          | clf: claimed_clf,
            logs_dir: Path.dirname(claimed_clf.file_path),
            user_id: claimed_clf.user_id,
            known_files: nil
        }

      {:error, reason} ->
        # An even newer log may have appeared mid-import; the next poll will
        # find and rotate to it instead.
        Logger.warning("FileWatcher: Could not claim watch after rotation: #{inspect(reason)}")
        refresh_tracked_file(state)
    end
  end

  defp handle_task_result(:rotate, {:error, reason}, state) do
    Logger.warning("FileWatcher: Rotation import failed: #{inspect(reason)}")
    refresh_tracked_file(state)
  end

  defp handle_task_result(
         _sync,
         {:ok, %{file: %CombatLogFile{} = clf, new_encounters: count}},
         state
       ) do
    Logger.info(
      "FileWatcher: Synced #{Path.basename(clf.file_path)} (#{count} new encounter#{plural(count)})"
    )

    maybe_broadcast_loaded(count)
    %{state | clf: clf, logs_dir: Path.dirname(clf.file_path), user_id: clf.user_id}
  end

  defp handle_task_result(_sync, {:error, reason}, state) do
    Logger.warning("FileWatcher: Sync failed: #{inspect(reason)}")
    refresh_tracked_file(state)
  end

  defp start_async_sync(state) do
    state = cancel_timer(state)
    clf = Repo.get!(CombatLogFile, state.clf.id)

    task =
      Task.Supervisor.async_nolink(WeGoNext.ImportTaskSupervisor, fn ->
        Importer.sync_log(clf)
      end)

    %{state | sync_ref: task.ref, sync_kind: :sync, clf: clf}
  end

  defp start_rotation_import(state, new_log_path) do
    state = cancel_timer(state)
    user_id = state.user_id
    Logger.info("FileWatcher: Detected new combat log #{Path.basename(new_log_path)}")

    task =
      Task.Supervisor.async_nolink(WeGoNext.ImportTaskSupervisor, fn ->
        Importer.import_log(new_log_path, user_id)
      end)

    %{state | sync_ref: task.ref, sync_kind: :rotate}
  end

  # Rotation scan: a live log qualifies while tracking a file when its
  # filename session timestamp is newer than the tracked file's; before any
  # file is tracked, when it was not present in the watch_directory snapshot.
  defp rotation_candidate(%{logs_dir: nil}), do: nil

  defp rotation_candidate(state) do
    case File.ls(state.logs_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&(live_log_with_datetime?(&1) and new_live_log?(&1, state)))
        |> Enum.max_by(&CombatLogFile.filename_datetime/1, NaiveDateTime, fn -> nil end)
        |> case do
          nil -> nil
          filename -> Path.join(state.logs_dir, filename)
        end

      {:error, _reason} ->
        nil
    end
  end

  defp live_log_with_datetime?(filename) do
    String.starts_with?(filename, "WoWCombatLog-") and String.ends_with?(filename, ".txt") and
      not is_nil(CombatLogFile.filename_datetime(filename))
  end

  defp new_live_log?(filename, %{clf: %CombatLogFile{} = clf}) do
    tracked_filename = Path.basename(clf.file_path)

    case CombatLogFile.filename_datetime(tracked_filename) do
      %NaiveDateTime{} = tracked_dt ->
        filename != tracked_filename and
          NaiveDateTime.after?(CombatLogFile.filename_datetime(filename), tracked_dt)

      nil ->
        false
    end
  end

  defp new_live_log?(filename, %{known_files: %MapSet{} = known_files}) do
    not MapSet.member?(known_files, filename)
  end

  defp new_live_log?(_filename, _state), do: false

  defp snapshot_live_logs(logs_dir) do
    case File.ls(logs_dir) do
      {:ok, files} -> files |> Enum.filter(&live_log_with_datetime?/1) |> MapSet.new()
      {:error, _reason} -> nil
    end
  end

  # A directory watch whose snapshot failed (e.g. drive not mounted yet) must
  # not treat every file as new once the directory appears; take the snapshot
  # first and only report files created after it.
  defp maybe_refresh_snapshot(%{clf: nil, known_files: nil, logs_dir: logs_dir} = state)
       when is_binary(logs_dir) do
    %{state | known_files: snapshot_live_logs(logs_dir)}
  end

  defp maybe_refresh_snapshot(state), do: state

  defp ensure_runtime_state(state) do
    state
    |> Map.put_new(:timer_ref, nil)
    |> Map.put_new(:sync_ref, nil)
    |> Map.put_new(:sync_kind, nil)
    |> Map.put_new(:known_files, nil)
    |> Map.put_new(
      :poll_interval_ms,
      Application.get_env(:we_go_next, :file_watcher_poll_interval_ms, @poll_interval_ms)
    )
  end

  defp sync_current_file(state) do
    state = cancel_timer(state)
    clf = Repo.get!(CombatLogFile, state.clf.id)

    case Importer.sync_log(clf) do
      {:ok, %{file: %CombatLogFile{} = updated_clf, new_encounters: count}} ->
        maybe_broadcast_loaded(count)
        {{:ok, count}, %{state | clf: updated_clf, logs_dir: Path.dirname(updated_clf.file_path)}}

      {:error, reason} ->
        {{:error, reason}, refresh_tracked_file(state)}
    end
  end

  defp watched_file_has_new_content?(%CombatLogFile{} = clf) do
    case Repo.get(CombatLogFile, clf.id) do
      nil ->
        false

      %CombatLogFile{} = fresh_clf ->
        (fresh_clf.last_parsed_byte || 0) < (fresh_clf.file_size || 0) or
          CombatLogFile.has_new_content?(fresh_clf)
    end
  end

  defp watch_enabled?(%CombatLogFile{id: id}) do
    match?(%CombatLogFile{source: :live, watch_enabled: true}, Repo.get(CombatLogFile, id))
  end

  defp stop_watching_state(state) do
    state
    |> cancel_timer()
    |> then(fn state -> initial_state(state.poll_interval_ms) end)
  end

  defp refresh_tracked_file(%{clf: nil} = state), do: state

  defp refresh_tracked_file(state) do
    case Repo.get(CombatLogFile, state.clf.id) do
      nil -> %{state | clf: nil, logs_dir: nil, user_id: nil}
      %CombatLogFile{} = clf -> %{state | clf: clf, logs_dir: Path.dirname(clf.file_path)}
    end
  end

  defp schedule_poll(%{clf: nil, logs_dir: nil} = state), do: cancel_timer(state)

  defp schedule_poll(%{sync_ref: sync_ref} = state) when not is_nil(sync_ref),
    do: cancel_timer(state)

  defp schedule_poll(%{poll_interval_ms: false} = state), do: cancel_timer(state)

  defp schedule_poll(state) do
    state = cancel_timer(state)
    timer_ref = Process.send_after(self(), :poll, state.poll_interval_ms)
    %{state | timer_ref: timer_ref}
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: timer_ref} = state) do
    Process.cancel_timer(timer_ref)
    %{state | timer_ref: nil}
  end

  defp cancel_timer(state), do: Map.put(state, :timer_ref, nil)

  defp maybe_broadcast_loaded(count) when count > 0 do
    Phoenix.PubSub.broadcast(WeGoNext.PubSub, "encounters", {:encounters_loaded, count})
  end

  defp maybe_broadcast_loaded(_count), do: :ok

  defp plural(1), do: ""
  defp plural(_count), do: "s"

  defp state_timer_ref(%{timer_ref: timer_ref}), do: timer_ref
  defp state_timer_ref(_state), do: nil

  defp state_sync_ref(%{sync_ref: sync_ref}), do: sync_ref
  defp state_sync_ref(_state), do: nil

  defp state_sync_kind(%{sync_kind: sync_kind}), do: sync_kind
  defp state_sync_kind(_state), do: nil

  defp state_poll_interval_ms(%{poll_interval_ms: poll_interval_ms}), do: poll_interval_ms
  defp state_poll_interval_ms(_state), do: @poll_interval_ms
end
