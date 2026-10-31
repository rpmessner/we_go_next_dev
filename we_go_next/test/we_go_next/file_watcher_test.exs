defmodule WeGoNext.FileWatcherTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias WeGoNext.Accounts.User
  alias WeGoNext.{CombatLogFile, FileWatcher, Importer, Repo}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord

  setup do
    :ok = Sandbox.checkout(Repo)
    # Shared mode so the FileWatcher process and its rotation-import tasks
    # (Task.Supervisor children) can all reach the sandboxed connection.
    Sandbox.mode(Repo, {:shared, self()})

    FileWatcher.stop_watching()
    FileWatcher.set_poll_interval_ms(false)

    dir = Path.join(System.tmp_dir!(), "wgn-file-watcher-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    user =
      Repo.insert!(%User{
        name: "user-#{System.unique_integer([:positive])}",
        wow_logs_path: dir
      })

    on_exit(fn ->
      WeGoNext.FileWatcherCleanup.stop()
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir, user: user}
  end

  test "a stale sync result cannot replace a newly watched log", %{dir: dir, user: user} do
    first = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112725_120000.txt"))
    FileWatcher.watch(first)
    FileWatcher.current_file()
    ref = make_ref()

    :sys.replace_state(FileWatcher, fn {phase, data} ->
      {phase, %{data | sync_ref: ref, sync_kind: :sync, task_generation: data.generation}}
    end)

    second = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112825_120000.txt"))
    FileWatcher.watch(second)
    send(Process.whereis(FileWatcher), {ref, {:ok, %{file: first, new_encounters: 0}}})
    assert FileWatcher.current_file().id == second.id
  end

  test "boot restores a durable enabled watch", %{dir: dir, user: user} do
    file = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112725_120000.txt"))
    FileWatcher.watch(file)
    FileWatcher.current_file()
    # A raw import may have registered a newer file without selecting it.
    insert_live_log!(user, Path.join(dir, "WoWCombatLog-112825_120000.txt"))
    :ok = Supervisor.terminate_child(WeGoNext.Supervisor, FileWatcher)
    assert {:ok, _pid} = Supervisor.restart_child(WeGoNext.Supervisor, FileWatcher)
    assert %CombatLogFile{id: id} = FileWatcher.current_file()
    assert id == file.id
    assert Repo.get!(CombatLogFile, id).watch_enabled
    FileWatcher.set_poll_interval_ms(false)
  end

  test "stopping watching clears the durable watch flag", %{dir: dir, user: user} do
    file = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112725_120000.txt"))
    FileWatcher.watch(file)
    FileWatcher.current_file()
    assert :ok = FileWatcher.stop_watching()
    refute Repo.get!(CombatLogFile, file.id).watch_enabled
  end

  test "poll imports appended encounters for the watched log", %{
    dir: dir,
    user: user
  } do
    live_content = File.read!(fixture_path("combat_log_base.txt"))
    continuation_content = File.read!(fixture_path("second_encounter.txt"))

    log_path = Path.join(dir, "WoWCombatLog-112725_120000.txt")
    File.write!(log_path, live_content)

    assert {:ok, %{file: %CombatLogFile{} = live_file, new_encounters: 1}} =
             Importer.import_log(log_path, user.id)

    Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")
    FileWatcher.watch(live_file)

    assert %CombatLogFile{id: id} = FileWatcher.current_file()
    assert id == live_file.id

    File.write!(log_path, continuation_content, [:append])

    send(Process.whereis(FileWatcher), :poll)
    assert_receive {:encounters_loaded, 1}, 5_000

    assert Repo.aggregate(EncounterRecord, :count) == 2
    assert %CombatLogFile{last_parsed_byte: parsed_byte} = FileWatcher.current_file()
    assert parsed_byte == byte_size(live_content <> continuation_content)
  end

  test "rotates to a newer combat log created while tracking", %{dir: dir, user: user} do
    log_path = Path.join(dir, "WoWCombatLog-112725_120000.txt")
    File.write!(log_path, File.read!(fixture_path("combat_log_base.txt")))

    assert {:ok, %{file: %CombatLogFile{} = live_file, new_encounters: 1}} =
             Importer.import_log(log_path, user.id)

    Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")
    FileWatcher.watch(live_file)
    assert %CombatLogFile{} = FileWatcher.current_file()

    new_log_path = Path.join(dir, "WoWCombatLog-112825_190000.txt")
    File.write!(new_log_path, rotated_log_content())

    send(Process.whereis(FileWatcher), :poll)

    assert_receive {:log_rotated, %CombatLogFile{} = new_clf, 1}, 5_000
    assert new_clf.file_path == new_log_path
    assert %CombatLogFile{file_path: ^new_log_path} = FileWatcher.current_file()
    assert Repo.aggregate(EncounterRecord, :count) == 2
  end

  test "rotates to a new log even before it has completed encounters", %{
    dir: dir,
    user: user
  } do
    log_path = Path.join(dir, "WoWCombatLog-112725_120000.txt")
    File.write!(log_path, File.read!(fixture_path("combat_log_base.txt")))

    assert {:ok, %{file: %CombatLogFile{} = live_file, new_encounters: 1}} =
             Importer.import_log(log_path, user.id)

    Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")
    FileWatcher.watch(live_file)

    new_log_path = Path.join(dir, "WoWCombatLog-112825_190000.txt")

    File.write!(
      new_log_path,
      "11/28/2025 19:00:00.000-5  COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,11.0.7,PROJECT_ID,1\n"
    )

    send(Process.whereis(FileWatcher), :poll)

    assert_receive {:log_rotated, %CombatLogFile{} = new_clf, 0}, 5_000
    assert new_clf.file_path == new_log_path
    assert %CombatLogFile{file_path: ^new_log_path} = FileWatcher.current_file()
  end

  test "watch_directory imports logs created after watching starts", %{dir: dir, user: user} do
    preexisting_path = Path.join(dir, "WoWCombatLog-110125_120000.txt")
    File.write!(preexisting_path, File.read!(fixture_path("combat_log_base.txt")))

    Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")

    FileWatcher.watch_directory(dir, user.id)
    assert {:directory, %{logs_dir: ^dir}} = :sys.get_state(FileWatcher)

    # Pre-existing files are snapshot as known: polling must not import them.
    send(Process.whereis(FileWatcher), :poll)
    refute_receive {:log_rotated, _clf, _count}, 500
    assert FileWatcher.current_file() == nil

    new_log_path = Path.join(dir, "WoWCombatLog-112825_190000.txt")
    File.write!(new_log_path, rotated_log_content())

    send(Process.whereis(FileWatcher), :poll)

    assert_receive {:log_rotated, %CombatLogFile{} = new_clf, 1}, 5_000
    assert new_clf.file_path == new_log_path
    assert %CombatLogFile{file_path: ^new_log_path} = FileWatcher.current_file()
    assert Repo.get_by(CombatLogFile, file_path: preexisting_path) == nil
  end

  defp rotated_log_content do
    "combat_log_base.txt"
    |> fixture_path()
    |> File.read!()
    |> String.replace("11/27/2025", "11/28/2025")
  end

  test "poll clears a watched log disabled in the database", %{dir: dir, user: user} do
    log_path = Path.join(dir, "WoWCombatLog-disabled.txt")
    File.write!(log_path, File.read!(fixture_path("combat_log_base.txt")))

    assert {:ok, %{file: %CombatLogFile{} = live_file}} =
             Importer.import_log(log_path, user.id)

    FileWatcher.watch(live_file)
    assert %CombatLogFile{id: id} = FileWatcher.current_file()
    assert id == live_file.id

    CombatLogFile
    |> Repo.get!(live_file.id)
    |> CombatLogFile.changeset(%{watch_enabled: false})
    |> Repo.update!()

    refute Repo.get!(CombatLogFile, live_file.id).watch_enabled
    assert %CombatLogFile{id: id} = FileWatcher.current_file()
    assert id == live_file.id
    send(Process.whereis(FileWatcher), :poll)
    assert FileWatcher.current_file() == nil
  end

  test "only the user's newest live log can be watched", %{dir: dir, user: user} do
    first = insert_live_log!(user, Path.join(dir, "WoWCombatLog-first.txt"))
    second = insert_live_log!(user, Path.join(dir, "WoWCombatLog-second.txt"))

    assert {:error, :not_newest_live_log} = FileWatcher.watch(first)
    refute Repo.get!(CombatLogFile, second.id).watch_enabled

    FileWatcher.watch(second)
    refute Repo.get!(CombatLogFile, first.id).watch_enabled
    assert Repo.get!(CombatLogFile, second.id).watch_enabled
    assert %CombatLogFile{id: second_id} = FileWatcher.current_file()
    assert second_id == second.id
  end

  test "no writes expires an in-flight watch without clearing the displayed log", %{
    dir: dir,
    user: user
  } do
    file = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112725_120000.txt"))
    Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")

    pid =
      start_supervised!(
        {FileWatcher,
         name: :watch_clock, restore: false, idle_timeout_ms: 30, poll_interval_ms: false}
      )

    :ok = :gen_statem.call(pid, {:display, file})
    :ok = :gen_statem.call(pid, {:watch, file})
    ref = make_ref()

    :sys.replace_state(pid, fn {_phase, data} ->
      {:syncing, %{data | sync_ref: ref, sync_kind: :sync, task_generation: data.generation}}
    end)

    assert_receive {:watch_stopped, id, :expire}, 1_000
    send(pid, {ref, {:ok, %{file: file, new_encounters: 0}}})
    assert id == file.id
    assert :gen_statem.call(pid, :watched_file) == nil
    assert :gen_statem.call(pid, :displayed_file).id == file.id
    refute Repo.get!(CombatLogFile, file.id).watch_enabled
  end

  test "a write renews the idle clock, but viewing does not", %{
    dir: dir,
    user: user
  } do
    file = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112725_120000.txt"))
    FileWatcher.watch(file)
    {_, data} = :sys.get_state(FileWatcher)

    :sys.replace_state(FileWatcher, fn {phase, data} ->
      {phase, %{data | last_write: data.last_write - 60_000}}
    end)

    FileWatcher.watch(file)
    {_, same_file} = :sys.get_state(FileWatcher)
    assert same_file.last_write == data.last_write - 60_000
    File.write!(file.file_path, "appended", [:append])
    :sys.replace_state(FileWatcher, fn {_phase, data} -> {:syncing, data} end)
    send(Process.whereis(FileWatcher), :poll)
    {_, written} = :sys.get_state(FileWatcher)
    assert written.last_write > same_file.last_write
  end

  test "writes to the rotating file renew the clock while its import is in flight", %{
    dir: dir,
    user: user
  } do
    file = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112725_120000.txt"))
    FileWatcher.watch(file)
    path = Path.join(dir, "WoWCombatLog-112825_120000.txt")
    File.write!(path, "fixture")

    :sys.replace_state(FileWatcher, fn {_phase, data} ->
      data = Map.merge(data, %{activity_path: path, last_write: data.last_write - 60_000})
      {:rotating, data}
    end)

    {_, before} = :sys.get_state(FileWatcher)
    File.write!(path, "new writes", [:append])
    send(Process.whereis(FileWatcher), :poll)
    {_, after_write} = :sys.get_state(FileWatcher)
    assert after_write.last_write > before.last_write
    assert after_write.clf.id == file.id
  end

  test "busy syncs back off and task crashes have the same retry policy", %{dir: dir, user: user} do
    file = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112725_120000.txt"))
    FileWatcher.watch(file)

    for reason <- [:ingest_busy, :killed] do
      ref = make_ref()

      :sys.replace_state(FileWatcher, fn {_phase, data} ->
        {:syncing, %{data | sync_ref: ref, sync_kind: :sync, task_generation: data.generation}}
      end)

      if reason == :killed,
        do: send(Process.whereis(FileWatcher), {:DOWN, ref, :process, self(), reason}),
        else: send(Process.whereis(FileWatcher), {ref, {:error, reason}})

      assert {:backoff, data} = :sys.get_state(FileWatcher)
      assert data.failures == if(reason == :ingest_busy, do: 1, else: 2)
      assert data.retry_at > System.monotonic_time(:millisecond)
      send(Process.whereis(FileWatcher), :poll)
      assert {:backoff, %{sync_ref: nil}} = :sys.get_state(FileWatcher)
    end
  end

  test "pending medallion failures also back off even when parsing succeeded", %{
    dir: dir,
    user: user
  } do
    file = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112725_120000.txt"))
    FileWatcher.watch(file)
    ref = make_ref()

    :sys.replace_state(FileWatcher, fn {_phase, data} ->
      {:syncing, %{data | sync_ref: ref, sync_kind: :sync, task_generation: data.generation}}
    end)

    send(
      Process.whereis(FileWatcher),
      {ref,
       {:ok,
        %{
          file: Repo.get!(CombatLogFile, file.id),
          new_encounters: 0,
          medallion_results: [{:error, :silver_unavailable}]
        }}}
    )

    assert {:backoff, %{failures: 1, sync_ref: nil}} = :sys.get_state(FileWatcher)
    assert FileWatcher.current_file().id == file.id
  end

  test "viewing an older log changes display, not the watched newest log", %{dir: dir, user: user} do
    first = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112725_120000.txt"))
    second = insert_live_log!(user, Path.join(dir, "WoWCombatLog-112825_120000.txt"))
    FileWatcher.watch(second)
    assert {:ok, 0} = WeGoNext.EncounterStore.load_from_db(first.id)
    assert WeGoNext.EncounterStore.current_combat_log_file().id == first.id
    assert FileWatcher.current_file().id == second.id
    assert Repo.get!(CombatLogFile, second.id).watch_enabled
  end

  defp insert_live_log!(user, path) do
    File.write!(path, "fixture")

    %CombatLogFile{}
    |> CombatLogFile.changeset(%{
      user_id: user.id,
      file_path: path,
      source: :live,
      file_size: 7,
      file_mtime: DateTime.utc_now() |> DateTime.truncate(:second),
      head_sha256: String.duplicate("a", 64)
    })
    |> Repo.insert!()
  end

  defp fixture_path(name) do
    Path.expand("../fixtures/#{name}", __DIR__)
  end
end
