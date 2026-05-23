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

  defp fixture_path(name) do
    Path.expand("../fixtures/#{name}", __DIR__)
  end
end
