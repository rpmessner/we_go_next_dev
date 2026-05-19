defmodule Mix.Tasks.Wgn.ImportDbmTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Wgn.ImportDbm
  alias WeGoNext.Repo
  alias WeGoNext.SourceData.DbmMechanicCandidate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
    end)

    :ok
  end

  test "imports DBM candidates from explicit roots and reports counts" do
    root = make_dbm_root!("DBM-Raids-Midnight")

    write_dbm_module!(
      root,
      "Boss.lua",
      """
      local mod = DBM:NewMod(2737, "DBM-Raids-Midnight", 3, 1307)
      mod:SetRevision("1")
      mod:SetEncounterID(3180)
      local specWarnOne = mod:NewSpecialWarningInterrupt(111, "HasInterrupt", nil, nil, 1, 2)
      """
    )

    output =
      capture_task_output(fn ->
        ImportDbm.run(["--root", root, "--build-key", "11.2.5", "--channel", "ptr"])
      end)

    assert output =~ "Imported DBM source data from 1 root(s): 1 file(s)"
    assert output =~ "1 new source import(s)"
    assert output =~ "1 candidate(s) inserted"

    assert Repo.aggregate(DbmMechanicCandidate, :count) == 1
  end

  defp capture_task_output(fun) do
    capture_io(fn ->
      fun.()
      flush_shell_messages()
    end)
  end

  defp flush_shell_messages do
    receive do
      {:mix_shell, :info, [message]} ->
        IO.puts(message)
        flush_shell_messages()
    after
      0 -> :ok
    end
  end

  defp make_dbm_root!(name) do
    directory =
      Path.join([
        System.tmp_dir!(),
        "wgn-dbm-task-#{System.unique_integer([:positive])}",
        name
      ])

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(Path.dirname(directory)) end)
    directory
  end

  defp write_dbm_module!(root, relative_path, body) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
    path
  end
end
