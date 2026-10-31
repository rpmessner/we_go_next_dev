defmodule WeGoNext.FileIngestTest do
  use ExUnit.Case, async: false
  alias WeGoNext.{CombatLogFile, FileIngest, Repo}
  alias WeGoNext.Accounts.User

  setup context do
    if context[:unboxed] do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    else
      Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    end

    user = Repo.insert!(%User{name: "ingest-#{System.unique_integer([:positive])}"})
    file = Repo.insert!(%CombatLogFile{file_path: "/tmp/ingest-#{user.id}", user_id: user.id})

    if context[:unboxed] do
      on_exit(fn ->
        Repo.delete!(Repo.get!(CombatLogFile, file.id))
        Repo.delete!(Repo.get!(User, user.id))
        Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
      end)
    end

    %{clf: file}
  end

  test "a stale caller resumes from locked database progress", %{clf: file} do
    file |> Ecto.Changeset.change(last_parsed_byte: 100) |> Repo.update!()
    assert {:ok, 100} = FileIngest.run(file, :sync, &{:ok, &1.last_parsed_byte})
  end

  test "a second writer cannot enter while a file is claimed", %{clf: file} do
    parent = self()

    first =
      Task.async(fn ->
        FileIngest.run(file, :import, fn _ ->
          send(parent, {:claimed, self()})

          receive do
            :finish -> {:ok, :finished}
          end
        end)
      end)

    assert_receive {:claimed, writer}
    assert {:error, :ingest_busy} = FileIngest.run(file, :sync, fn _ -> {:ok, :second} end)
    send(writer, :finish)
    assert {:ok, :finished} = Task.await(first)
  end

  @tag :unboxed
  @tag capture_log: true
  test "a dead caller cannot leave its writer running", %{clf: file} do
    parent = self()

    caller =
      Task.async(fn ->
        FileIngest.run(file, :sync, fn _ ->
          send(parent, {:writer, self()})

          receive do
            :never -> {:ok, :unexpected}
          end
        end)
      end)

    assert_receive {:writer, writer}
    ref = Process.monitor(writer)
    on_exit(fn -> if Process.alive?(writer), do: Process.exit(writer, :kill) end)
    Task.shutdown(caller, :brutal_kill)
    assert_receive {:DOWN, ^ref, :process, ^writer, :killed}, 1_000
    await_release(file)
  end

  @tag :unboxed
  @tag capture_log: true
  test "a hung writer times out and releases the file", %{clf: file} do
    parent = self()

    assert {:error, :ingest_timeout} =
             FileIngest.run(
               file,
               :import,
               fn _ ->
                 send(parent, {:writer, self()})

                 receive do
                   :never -> {:ok, :unexpected}
                 end
               end,
               timeout: 20
             )

    assert_receive {:writer, pid}
    refute Process.alive?(pid)
    await_release(file)
    assert {:ok, :next} = FileIngest.run(file, :sync, fn _ -> {:ok, :next} end)
  end

  defp await_release(file) do
    # Wait for PostgreSQL to release the killed connection, not a timed sleep.
    Repo.checkout(fn ->
      Repo.query!("SELECT pg_advisory_lock($1, $2)", [18_003, file.id])
      Repo.query!("SELECT pg_advisory_unlock($1, $2)", [18_003, file.id])
    end)

    Logger.flush()
  end
end
