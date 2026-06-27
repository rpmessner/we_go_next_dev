defmodule Mix.Tasks.Wgn.ImportWarcraftLogsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Wgn.ImportWarcraftLogs
  alias WeGoNext.Repo
  alias WeGoNext.SourceData.WarcraftLogsApiFetch

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
    end)

    :ok
  end

  test "imports saved Warcraft Logs API response JSON and reports the fetch" do
    bronze_root = fixture_directory()

    response_path =
      write_json_fixture("response.json", %{
        "data" => %{
          "reportData" => %{
            "report" => %{
              "events" => %{"data" => [%{"id" => 1, "type" => "damage"}]}
            }
          }
        }
      })

    request_path =
      write_json_fixture("request.json", %{"startTime" => 0, "endTime" => 90_000})

    query_path =
      write_text_fixture(
        "events.graphql",
        "query Events($fightIDs: [Int]) { reportData { report { events { data } } } }"
      )

    output =
      capture_task_output(fn ->
        ImportWarcraftLogs.run([
          "--file",
          response_path,
          "--report-code",
          "abc123",
          "--fight-id",
          "17",
          "--query-name",
          "Events",
          "--query-file",
          query_path,
          "--request-params-file",
          request_path,
          "--bronze-root",
          bronze_root,
          "--build-key",
          "local"
        ])
      end)

    assert output =~ "Imported Warcraft Logs API source data for report abc123 fight 17"
    assert output =~ "1 new source import"
    assert output =~ "bronze artifact"
    assert Repo.aggregate(WarcraftLogsApiFetch, :count) == 1

    fetch = Repo.one!(WarcraftLogsApiFetch)
    assert fetch.report_code == "abc123"
    assert fetch.fight_id == 17
    assert fetch.query_name == "Events"
    assert fetch.request_params == %{"endTime" => 90_000, "startTime" => 0}
    assert fetch.build_key == "local"
    assert fetch.artifact_path =~ bronze_root
    assert File.regular?(fetch.artifact_path)
  end

  test "requires report identity and fight identity" do
    response_path = write_json_fixture("response.json", %{"data" => %{}})

    assert_raise Mix.Error, ~r/requires --report-code/, fn ->
      ImportWarcraftLogs.run([
        "--file",
        response_path,
        "--fight-id",
        "17",
        "--query-name",
        "Events"
      ])
    end
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

  defp fixture_directory do
    directory =
      Path.join(System.tmp_dir!(), "wgn-warcraft-logs-task-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)
    directory
  end

  defp write_json_fixture(name, payload) do
    path = Path.join(fixture_directory(), name)
    File.write!(path, Jason.encode!(payload))
    path
  end

  defp write_text_fixture(name, body) do
    path = Path.join(fixture_directory(), name)
    File.write!(path, body)
    path
  end
end
