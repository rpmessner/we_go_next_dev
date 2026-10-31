defmodule WeGoNext.FileWatcher do
  @moduledoc """
  Singleton live-log watch adapter. Selection for display is independent of the
  watched file. Durable watch changes are acknowledged only after persistence;
  task replies are accepted only for the current watch generation.

  `file_watcher_idle_timeout_ms` defaults to 30 minutes. Its monotonic clock starts
  when watching starts (including boot), and is reset only by observed file writes.
  Failed syncs, including `:ingest_busy`, retry with bounded exponential backoff.
  """
  @behaviour :gen_statem
  import Ecto.Query
  require Logger

  alias WeGoNext.{CombatLogFile, FileIngest, FileWatchLifecycle, Importer, Repo}

  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  def start_link(opts \\ []) do
    :gen_statem.start_link({:local, Keyword.get(opts, :name, __MODULE__)}, __MODULE__, opts, [])
  end

  def watch(%CombatLogFile{source: :live} = clf), do: call({:watch, clf})
  def watch(%CombatLogFile{}), do: {:error, :watch_disabled}

  def watch(path) when is_binary(path) do
    case Repo.get_by(CombatLogFile, file_path: path) do
      nil -> {:error, :not_found}
      clf -> watch(clf)
    end
  end

  def watch_directory(dir, user_id), do: call({:directory, dir, user_id})
  def stop_watching, do: call(:stop)
  def stop_watching(%CombatLogFile{id: id}), do: call({:stop, id})
  def current_file, do: call(:watched_file)
  def displayed_file, do: call(:displayed_file)

  def subscribe_display_changes,
    do: Phoenix.PubSub.subscribe(WeGoNext.PubSub, "displayed_log")

  def display(%CombatLogFile{} = clf), do: call({:display, clf})
  def clear_display, do: call({:display, nil})
  def refresh_if_tracking(%CombatLogFile{} = clf), do: call({:refresh, clf})

  @doc false
  def set_poll_interval_ms(ms) when ms == false or (is_integer(ms) and ms > 0),
    do: call({:poll_interval, ms})

  defp call(message), do: :gen_statem.call(__MODULE__, message, 30_000)

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init(opts) do
    data =
      Map.merge(FileWatchLifecycle.initial(), %{
        clf: nil,
        displayed: nil,
        candidate: nil,
        result: nil,
        logs_dir: nil,
        user_id: nil,
        known_files: nil,
        sync_ref: nil,
        sync_kind: nil,
        signature: nil,
        activity_path: nil,
        last_write: now(),
        idle_ms: Keyword.get(opts, :idle_timeout_ms, config(:idle_timeout_ms, 30 * 60_000)),
        poll_ms: Keyword.get(opts, :poll_interval_ms, config(:poll_interval_ms, 5_000)),
        retry_at: nil,
        poll_at: now()
      })

    if Keyword.get(opts, :restore, true) do
      {:ok, :idle, data, [{:next_event, :internal, :restore}]}
    else
      {:ok, :idle, data}
    end
  end

  @impl true
  def handle_event(:internal, :restore, phase, data) do
    case Repo.all(from(f in CombatLogFile, where: f.watch_enabled and f.source == :live))
         |> Enum.max_by(&log_order_key/1, fn -> nil end) do
      nil -> {:keep_state, data}
      clf -> select(phase, data, clf, nil, false)
    end
  end

  def handle_event({:call, from}, {:watch, clf}, phase, data),
    do: select(phase, data, clf, from)

  def handle_event({:call, from}, :stop, phase, data),
    do: stop(phase, data, from)

  def handle_event({:call, from}, {:stop, id}, phase, data) do
    if data.tracked == id do
      stop(phase, data, from)
    else
      Repo.update_all(from(f in CombatLogFile, where: f.id == ^id), set: [watch_enabled: false])
      reply(phase, data, from, :ok)
    end
  end

  def handle_event({:call, from}, :watched_file, phase, data),
    do: reply(phase, data, from, data.clf)

  def handle_event({:call, from}, :displayed_file, phase, data) do
    displayed = if data.displayed, do: Repo.get(CombatLogFile, data.displayed.id)
    reply(phase, %{data | displayed: displayed}, from, displayed)
  end

  def handle_event({:call, from}, {:display, clf}, phase, data) do
    Phoenix.PubSub.broadcast(WeGoNext.PubSub, "displayed_log", :display_changed)
    reply(phase, %{data | displayed: clf}, from, :ok)
  end

  def handle_event({:call, from}, {:refresh, clf}, phase, data) do
    tracking = data.tracked == clf.id
    data = if tracking, do: %{data | clf: clf}, else: data

    if tracking and (clf.source != :live or not clf.watch_enabled) do
      {phase, data} = transition(phase, :stop, data)
      broadcast({:watch_stopped, clf.id, :refresh})
      reply(phase, data, from, true)
    else
      reply(phase, data, from, tracking)
    end
  end

  def handle_event({:call, from}, {:poll_interval, ms}, phase, data),
    do: reply(phase, %{data | poll_ms: ms, poll_at: now()}, from, :ok)

  def handle_event({:call, from}, {:directory, dir, user_id}, phase, data) do
    data = %{data | candidate: %{dir: dir, user_id: user_id}}
    {phase, data} = transition(phase, :directory, data)
    reply(phase, data, from, :ok)
  end

  def handle_event(type, :poll, phase, data) when type in [:info, {:timeout, :poll}] do
    interval = if is_integer(data.poll_ms), do: data.poll_ms, else: 5_000
    poll(phase, observe_write(%{data | poll_at: now() + interval}))
  end

  def handle_event({:timeout, :idle}, :expire, phase, data) do
    data = %{observe_write(data) | now: now()}
    {:ok, _next, _ctx, effects} = FileWatchLifecycle.step(phase, :expire, data)

    if :disable in effects,
      do: stop(phase, data, nil, :expire),
      else: continue(phase, data)
  end

  def handle_event(:info, {ref, result}, phase, %{sync_ref: ref} = data)
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    task_result(phase, data, result)
  end

  def handle_event(:info, {:DOWN, ref, :process, _pid, reason}, phase, %{sync_ref: ref} = data),
    do: task_result(phase, data, {:error, reason})

  def handle_event(_type, _event, phase, data), do: continue(phase, data)

  defp select(phase, data, clf, from, newest_only \\ true) do
    case claim_watch(clf, newest_only) do
      {:ok, claimed} ->
        {phase, data} = transition(phase, :watch, %{data | candidate: claimed})
        broadcast({:watch_changed, claimed.id})
        reply(phase, data, from, :ok)

      {:error, reason} ->
        reply(phase, data, from, {:error, reason})
    end
  end

  defp stop(phase, data, from, event \\ :stop) do
    # No task is killed: FileIngest remains the owner of any in-flight write.
    # Forgetting the monitor makes its eventual result unable to change tracking.
    case Repo.transaction(fn ->
           Repo.update_all(from(f in CombatLogFile, where: f.watch_enabled),
             set: [watch_enabled: false]
           )
         end) do
      {:ok, _} ->
        if data.enabled or not is_nil(data.logs_dir),
          do: broadcast({:watch_stopped, data.tracked, event})

        {phase, data} = transition(phase, event, data)
        reply(phase, data, from, :ok)

      {:error, reason} ->
        reply(phase, data, from, {:error, reason})
    end
  end

  defp poll(phase, data) do
    if data.clf && not enabled?(data.clf.id) do
      stop(phase, data, nil)
    else
      {phase, data} = transition(phase, :retry, data)
      {:ok, ^phase, data, effects} = FileWatchLifecycle.step(phase, :poll, data)

      if :inspect in effects, do: poll_ready(phase, data), else: continue(phase, data)
    end
  end

  defp poll_ready(phase, data) do
    # Rotation takes priority over catching up the old log, so a busy or failing
    # old file cannot starve a newly created one.
    candidate = rotation_candidate(data)
    fresh = if data.clf, do: Repo.get(CombatLogFile, data.clf.id)

    {phase, data} =
      cond do
        candidate -> transition(phase, :rotate, %{data | candidate: candidate})
        fresh && Importer.sync_needed?(fresh) -> transition(phase, :sync, %{data | clf: fresh})
        true -> {phase, maybe_refresh_snapshot(data)}
      end

    continue(phase, data)
  end

  defp task_result(phase, data, {:ok, %{file: clf} = result}) do
    case maybe_claim_rotation(data.sync_kind, clf) do
      {:ok, clf} ->
        event =
          if Enum.any?(Map.get(result, :medallion_results, []), &match?({:error, _}, &1)),
            do: :partial_failure,
            else: :success

        {phase, data} = transition(phase, event, %{data | result: %{result | file: clf}})
        continue(phase, data)

      {:error, reason} ->
        task_result(phase, data, {:error, reason})
    end
  end

  defp task_result(phase, data, {:error, reason}) do
    Logger.warning("FileWatcher: Sync failed: #{inspect(reason)}")
    {phase, data} = transition(phase, :failure, data)
    continue(phase, data)
  end

  defp maybe_claim_rotation(:rotate, clf), do: claim_watch(clf)
  defp maybe_claim_rotation(_, clf), do: {:ok, clf}

  defp transition(phase, event, data) do
    {:ok, next, data, effects} = FileWatchLifecycle.step(phase, event, %{data | now: now()})
    {next, Enum.reduce(effects, data, &effect/2)}
  end

  defp effect(:select, data) do
    data = data |> observe_write() |> forget_task()
    clf = data.candidate
    last_write = if data.clf && data.clf.id == clf.id, do: data.last_write, else: now()

    %{
      data
      | clf: clf,
        logs_dir: Path.dirname(clf.file_path),
        user_id: clf.user_id,
        known_files: nil,
        signature: signature(clf.file_path),
        activity_path: clf.file_path,
        last_write: last_write,
        retry_at: nil
    }
  end

  defp effect(:directory, data) do
    %{
      data
      | logs_dir: data.candidate.dir,
        user_id: data.candidate.user_id,
        known_files: snapshot_live_logs(data.candidate.dir),
        last_write: now()
    }
  end

  defp effect(:disable, data) do
    data = forget_task(data)

    %{
      data
      | clf: nil,
        logs_dir: nil,
        user_id: nil,
        known_files: nil,
        retry_at: nil,
        activity_path: nil
    }
  end

  defp effect(:sync, data) do
    task = FileIngest.start_sync(data.clf)
    %{data | sync_ref: task.ref, sync_kind: :sync, task_generation: data.generation}
  end

  defp effect(:rotate, data) do
    path = data.candidate
    data = observe_path(data, path)
    user_id = data.user_id

    task =
      Task.Supervisor.async_nolink(WeGoNext.ImportTaskSupervisor, fn ->
        Importer.import_log(path, user_id)
      end)

    %{data | sync_ref: task.ref, sync_kind: :rotate, task_generation: data.generation}
  end

  defp effect(:complete, data) do
    clf = data.result.file
    count = data.result.new_encounters
    if count > 0, do: broadcast({:encounters_loaded, count})

    if data.sync_kind == :rotate do
      broadcast({:log_rotated, clf, count})
    end

    data = forget_task(data)

    %{
      data
      | clf: clf,
        logs_dir: Path.dirname(clf.file_path),
        user_id: clf.user_id,
        known_files: nil,
        retry_at: nil
    }
  end

  defp effect(:fail, data) do
    data = forget_task(data)
    base = if is_integer(data.poll_ms), do: data.poll_ms, else: 5_000
    %{data | retry_at: now() + min(base * Integer.pow(2, data.failures), 300_000)}
  end

  defp effect(:reset, data), do: data

  defp forget_task(data) do
    if data.sync_ref, do: Process.demonitor(data.sync_ref, [:flush])
    %{data | sync_ref: nil, sync_kind: nil, task_generation: nil}
  end

  defp reply(phase, data, nil, _result), do: continue(phase, data)

  defp reply(phase, data, from, result),
    do: {:next_state, phase, data, [{:reply, from, result} | timers(phase, data)]}

  defp continue(phase, data), do: {:next_state, phase, data, timers(phase, data)}

  defp timers(_phase, %{logs_dir: nil}) do
    [{{:timeout, :poll}, :infinity, :poll}, {{:timeout, :idle}, :infinity, :expire}]
  end

  defp timers(_phase, data) do
    poll = if data.poll_ms == false, do: :infinity, else: max(data.poll_at - now(), 0)
    idle = max(data.idle_ms - (now() - data.last_write), 0)
    [{{:timeout, :poll}, poll, :poll}, {{:timeout, :idle}, idle, :expire}]
  end

  defp observe_write(%{activity_path: nil} = data), do: data
  defp observe_write(data), do: observe_path(data, data.activity_path)

  defp observe_path(data, path) do
    signature = signature(path)

    if signature && (path != data.activity_path or signature != data.signature),
      do: %{data | signature: signature, activity_path: path, last_write: now()},
      else: data
  end

  defp signature(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> {stat.size, stat.mtime, stat.ctime}
      _ -> nil
    end
  end

  defp enabled?(id),
    do: match?(%CombatLogFile{source: :live, watch_enabled: true}, Repo.get(CombatLogFile, id))

  defp claim_watch(clf, newest_only \\ true) do
    Repo.transaction(fn ->
      fresh = Repo.get(CombatLogFile, clf.id) || Repo.rollback(:not_found)

      newest =
        Repo.all(
          from(f in CombatLogFile, where: f.user_id == ^fresh.user_id and f.source == :live)
        )
        |> Enum.max_by(&log_order_key/1, fn -> nil end)

      if fresh.source != :live, do: Repo.rollback(:watch_disabled)

      if newest_only and (is_nil(newest) or newest.id != fresh.id),
        do: Repo.rollback(:not_newest_live_log)

      Repo.update_all(from(f in CombatLogFile, where: f.watch_enabled),
        set: [watch_enabled: false]
      )

      fresh
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.force_change(:watch_enabled, true)
      |> Repo.update!()
    end)
  end

  defp log_order_key(clf) do
    datetime = CombatLogFile.filename_datetime(clf.file_path)
    {if(datetime, do: NaiveDateTime.to_erl(datetime), else: {{0, 1, 1}, {0, 0, 0}}), clf.id}
  end

  defp rotation_candidate(%{logs_dir: nil}), do: nil

  defp rotation_candidate(data) do
    case File.ls(data.logs_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&(live_log_with_datetime?(&1) and new_live_log?(&1, data)))
        |> Enum.max_by(&CombatLogFile.filename_datetime/1, NaiveDateTime, fn -> nil end)
        |> case do
          nil -> nil
          filename -> Path.join(data.logs_dir, filename)
        end

      _ ->
        nil
    end
  end

  defp live_log_with_datetime?(filename) do
    String.starts_with?(filename, "WoWCombatLog-") and String.ends_with?(filename, ".txt") and
      not is_nil(CombatLogFile.filename_datetime(filename))
  end

  defp new_live_log?(filename, %{clf: %CombatLogFile{} = clf}) do
    case CombatLogFile.filename_datetime(clf.file_path) do
      %NaiveDateTime{} = tracked ->
        NaiveDateTime.after?(CombatLogFile.filename_datetime(filename), tracked)

      nil ->
        false
    end
  end

  defp new_live_log?(filename, %{known_files: %MapSet{} = known}),
    do: not MapSet.member?(known, filename)

  defp new_live_log?(_, _), do: false

  defp snapshot_live_logs(dir) do
    case File.ls(dir) do
      {:ok, files} -> files |> Enum.filter(&live_log_with_datetime?/1) |> MapSet.new()
      _ -> nil
    end
  end

  defp maybe_refresh_snapshot(%{clf: nil, known_files: nil, logs_dir: dir} = data)
       when is_binary(dir), do: %{data | known_files: snapshot_live_logs(dir)}

  defp maybe_refresh_snapshot(data), do: data
  defp broadcast(message), do: Phoenix.PubSub.broadcast(WeGoNext.PubSub, "encounters", message)

  defp config(:idle_timeout_ms, default),
    do: Application.get_env(:we_go_next, :file_watcher_idle_timeout_ms, default)

  defp config(:poll_interval_ms, default),
    do: Application.get_env(:we_go_next, :file_watcher_poll_interval_ms, default)

  defp now, do: System.monotonic_time(:millisecond)
end
