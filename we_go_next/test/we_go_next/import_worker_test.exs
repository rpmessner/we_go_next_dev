defmodule WeGoNext.ImportWorkerTest do
  use ExUnit.Case, async: false
  alias WeGoNext.{CombatLogFile, ImportWorker, Repo}
  alias WeGoNext.Accounts.User

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    dir = Path.join(System.tmp_dir!(), "wgn-worker-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "WoWCombatLog-112725_120000.txt")
    File.cp!("test/fixtures/combat_log_base.txt", path)
    user = Repo.insert!(%User{name: "worker-#{System.unique_integer([:positive])}"})

    on_exit(fn ->
      WeGoNext.FileWatcher.stop_watching()
      import Ecto.Query
      Repo.delete_all(from(d in WeGoNext.Gold.DimEncounter, where: d.source_file_path == ^path))
      Repo.delete_all(from(f in CombatLogFile, where: f.user_id == ^user.id))
      Repo.delete!(Repo.get!(User, user.id))
      File.rm_rf!(dir)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    %{user: user, path: path}
  end

  @tag capture_log: true
  test "a deadline terminates loading and persists a failed receipt", %{user: user, path: path} do
    parent = self()

    blocker =
      Task.async(fn ->
        Repo.transaction(fn ->
          Repo.query!("LOCK TABLE encounters IN ACCESS EXCLUSIVE MODE")
          send(parent, :locked)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :locked
    on_exit(fn -> if Process.alive?(blocker.pid), do: Process.exit(blocker.pid, :kill) end)
    Phoenix.PubSub.subscribe(WeGoNext.PubSub, ImportWorker.progress_topic(user.id))
    assert :ok = ImportWorker.start_import(user.id, path, timeout: 100, generate_document: false)
    assert_receive {:import_complete, {:error, :ingest_timeout}}, 2_000
    assert is_nil(ImportWorker.get_status(user.id))

    assert %{status: "failed", error: ":ingest_timeout"} =
             Repo.get_by!(WeGoNext.FileIngest.Operation, user_id: user.id)

    send(blocker.pid, :release)
    Task.await(blocker)
    wait_for_tasks()
  end

  test "status and completion survive ImportWorker restart", %{user: user, path: path} do
    parent = self()

    blocker =
      Task.async(fn ->
        Repo.transaction(fn ->
          Repo.query!("LOCK TABLE encounters IN ACCESS EXCLUSIVE MODE")
          send(parent, :locked)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :locked
    on_exit(fn -> if Process.alive?(blocker.pid), do: Process.exit(blocker.pid, :kill) end)
    Phoenix.PubSub.subscribe(WeGoNext.PubSub, ImportWorker.progress_topic(user.id))
    assert :ok = ImportWorker.start_import(user.id, path, generate_document: false)
    assert_receive {:import_started, token}
    assert token == Repo.get_by!(WeGoNext.FileIngest.Operation, user_id: user.id).token
    :ok = Supervisor.terminate_child(WeGoNext.Supervisor, ImportWorker)
    {:ok, _} = Supervisor.restart_child(WeGoNext.Supervisor, ImportWorker)
    assert %{status: :importing, path: ^path} = ImportWorker.get_status(user.id)
    send(blocker.pid, :release)
    Task.await(blocker)
    assert_receive {:import_complete, {:ok, 1}}, 5_000
    assert is_nil(ImportWorker.get_status(user.id))
    wait_for_tasks()
  end

  defp wait_for_tasks do
    for pid <- Task.Supervisor.children(WeGoNext.ImportTaskSupervisor) do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5_000
    end
  end
end
