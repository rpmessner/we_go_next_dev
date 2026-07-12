defmodule WeGoNext.FileWatcherTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias WeGoNext.Accounts.User
  alias WeGoNext.{CombatLogFile, FileWatcher, Importer, Repo}
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.allow(Repo, self(), Process.whereis(FileWatcher))

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
      FileWatcher.stop_watching()
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir, user: user}
  end

  test "sync_now imports appended encounters for the watched current log", %{
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

    assert {:ok, 1} = FileWatcher.sync_now()
    assert_receive {:encounters_loaded, 1}

    assert Repo.aggregate(EncounterRecord, :count) == 2
    assert %CombatLogFile{last_parsed_byte: parsed_byte} = FileWatcher.current_file()
    assert parsed_byte == byte_size(live_content <> continuation_content)
  end

  test "sync_now clears a watched log disabled in the database", %{dir: dir, user: user} do
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
    assert FileWatcher.sync_now() in [{:error, :watch_disabled}, {:ok, 0}]
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

  defp insert_live_log!(user, path) do
    File.write!(path, "fixture")

    %CombatLogFile{}
    |> CombatLogFile.changeset(%{
      user_id: user.id,
      file_path: path,
      source: :live,
      head_sha256: String.duplicate("a", 64)
    })
    |> Repo.insert!()
  end

  defp fixture_path(name) do
    Path.expand("../fixtures/#{name}", __DIR__)
  end
end
