defmodule Mix.Tasks.Wgn.ExportAnalysisTest do
  use WeGoNext.DataCase, async: false
  alias WeGoNext.{Analysis, Repo}
  alias WeGoNext.Analysis.{Session, ToolCall}
  alias Mix.Tasks.Wgn.ExportAnalysis

  @session_id "11111111-1111-4111-8111-111111111111"

  setup do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "export-test"})
    log = Repo.insert!(%WeGoNext.CombatLogFile{user_id: user.id, file_path: "/sept6.txt"})

    session =
      Repo.insert!(%Session{
        id: @session_id,
        combat_log_file_id: log.id,
        started_at: ~U[2026-09-06 12:00:00.000000Z],
        boss: "Sszorak"
      })

    output =
      Path.join(System.tmp_dir!(), "wgn-export-#{System.unique_integer([:positive])}.jsonl")

    on_exit(fn -> File.rm(output) end)
    {:ok, session: session, log: log, output: output}
  end

  test "task exports messages, recorded results, timings, verdicts, context and unmatched counts",
       %{session: session, output: output} do
    Repo.insert!(%ToolCall{
      session_id: session.id,
      tool: "deaths",
      args: %{"session_id" => session.id, "pulls" => [42]},
      result: %{"data" => [%{"player" => "Healer"}]},
      result_size: 30,
      duration_ms: 23,
      truncated: false,
      called_at: session.started_at
    })

    assert {:ok, _} =
             Analysis.call_tool("record_verdict", %{
               "session_id" => session.id,
               "answer" => "The healer died first",
               "verdict" => "correct",
               "correction" => ""
             })

    ExportAnalysis.run([
      "--session",
      session.id,
      "--transcript",
      "test/fixtures/analysis_transcript.jsonl",
      "--output",
      output
    ])

    assert [line] = File.read!(output) |> String.split("\n", trim: true)
    record = Jason.decode!(line)
    assert record["schema_version"] == 1
    assert record["session"]["id"] == session.id
    assert record["context"]["active_log"]["file_path"] == "/sept6.txt"
    assert Enum.any?(record["messages"], &(&1["uuid"] == "answer-1"))
    assert [%{"verdict" => "correct", "answer" => "The healer died first"}] = record["verdicts"]

    assert [
             %{"status" => "matched", "server" => %{"duration_ms" => 23}},
             %{"status" => "unmatched_transcript"},
             %{"status" => "unmatched_server"}
           ] = record["tool_calls"]

    assert record["unmatched"] == %{
             "transcript_calls" => 1,
             "server_calls" => 1,
             "unscoped_transcript_calls" => 0
           }

    assert [%{"transcript" => %{"results" => [%{"content" => [_]}]}} | _] = record["tool_calls"]
  end

  test "refuses to overwrite an existing transcript or export", %{
    session: session,
    output: output
  } do
    File.write!(output, "preserve me\n")

    assert_raise Mix.Error, ~r/Cannot create export/, fn ->
      ExportAnalysis.run([
        "--session",
        session.id,
        "--transcript",
        "test/fixtures/analysis_transcript.jsonl",
        "--output",
        output
      ])
    end

    assert File.read!(output) == "preserve me\n"
  end

  test "rejects ambiguous selectors and malformed JSON before writing", %{
    session: session,
    output: output
  } do
    assert_raise Mix.Error, ~r/Choose exactly one/, fn ->
      ExportAnalysis.run(["--session", session.id, "--night", "2026-09-06"])
    end

    File.write!(output, "not json\n")

    assert_raise Mix.Error, ~r/Invalid transcript JSON object.*:1/, fn ->
      ExportAnalysis.run([
        "--session",
        session.id,
        "--transcript",
        output,
        "--output",
        output <> ".never"
      ])
    end

    refute File.exists?(output <> ".never")
  end

  test "night export includes all sessions started on the UTC date only", %{
    log: log,
    output: output
  } do
    second =
      Repo.insert!(%Session{
        combat_log_file_id: log.id,
        started_at: ~U[2026-09-06 23:59:59.000000Z]
      })

    Repo.insert!(%Session{
      combat_log_file_id: log.id,
      started_at: ~U[2026-09-07 00:00:00.000000Z]
    })

    ExportAnalysis.run([
      "--night",
      "2026-09-06",
      "--transcript",
      "test/fixtures/analysis_transcript.jsonl",
      "--output",
      output
    ])

    records = output |> File.stream!() |> Enum.map(&Jason.decode!/1)
    assert Enum.map(records, & &1["session"]["id"]) == [@session_id, second.id]
  end
end
