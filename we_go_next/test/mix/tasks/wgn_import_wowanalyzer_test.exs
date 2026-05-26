defmodule Mix.Tasks.Wgn.ImportWowAnalyzerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Wgn.ImportWowAnalyzer
  alias WeGoNext.Repo
  alias WeGoNext.SourceData.WowAnalyzerTimelineCandidate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
    end)

    :ok
  end

  test "imports WowAnalyzer timeline source rows from explicit root and reports counts" do
    root = make_wowanalyzer_root!()

    write_wowanalyzer_module!(
      root,
      "Boss.ts",
      """
      export const Boss = buildBoss({
        id: 3306,
        name: 'Chimaerus the Undreamt God',
        timeline: {
          abilities: [
            // Alndust Upheaval (group soak)
            { id: 1262289, type: 'cast' },
          ],
        },
      });
      """
    )

    output =
      capture_task_output(fn ->
        ImportWowAnalyzer.run([
          "--root",
          root,
          "--repo-root",
          root,
          "--repository-revision",
          "fixture-revision",
          "--build-key",
          "11.2.5",
          "--channel",
          "ptr"
        ])
      end)

    assert output =~ "Imported WowAnalyzer timeline source data from 1 root(s): 1 file(s)"
    assert output =~ "1 new source import(s)"
    assert output =~ "1 source row(s) inserted"
    assert output =~ "Source license: AGPL-3.0-or-later"

    assert Repo.aggregate(WowAnalyzerTimelineCandidate, :count) == 1
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

  defp make_wowanalyzer_root! do
    directory =
      Path.join(System.tmp_dir!(), "wgn-wowanalyzer-task-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)
    directory
  end

  defp write_wowanalyzer_module!(root, relative_path, body) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
    path
  end
end
