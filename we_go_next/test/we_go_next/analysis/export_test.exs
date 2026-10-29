defmodule WeGoNext.Analysis.ExportTest do
  use ExUnit.Case, async: true
  alias WeGoNext.Analysis.Export
  @session_id "11111111-1111-4111-8111-111111111111"

  setup do
    events =
      "test/fixtures/analysis_transcript.jsonl" |> File.stream!() |> Enum.map(&Jason.decode!/1)

    call = %{
      id: 10,
      session_id: @session_id,
      tool: "deaths",
      args: %{"session_id" => @session_id, "pulls" => [42]},
      result: %{"data" => [%{"player" => "Healer"}]},
      duration_ms: 23,
      called_at: ~U[2026-09-06 12:00:01Z]
    }

    {:ok, events: events, call: call}
  end

  test "matches identical calls once each in server order and preserves results and timings", %{
    events: events,
    call: call
  } do
    assert [first, second] = Export.join(@session_id, events, [%{call | id: 11}, call])
    assert first.status == "matched"
    assert first.server.id == 10
    assert first.server.duration_ms == 23
    assert first.server.result == %{"data" => [%{"player" => "Healer"}]}
    assert first.transcript.tool_use_id == "tool-1"
    assert [%{"content" => [%{"text" => _}]}] = first.transcript.results
    assert second.server.id == 11
    assert second.transcript.tool_use_id == "tool-2"
  end

  test "keeps calls without an Analysis session id visible as unscoped", %{events: events} do
    event = %{
      "type" => "assistant",
      "message" => %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "unknown",
            "name" => "mcp__we_go_next__deaths",
            "input" => %{"pulls" => [42]}
          }
        ]
      }
    }

    record = Export.build(%{id: @session_id}, %{}, events ++ [event], [], [])
    assert [%{tool_use_id: "unknown"}] = record.unscoped_transcript_calls
    assert record.unmatched.unscoped_transcript_calls == 1
  end

  test "retains malformed Tool inputs as unscoped instead of dropping the call" do
    event = %{
      "message" => %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "malformed",
            "name" => "mcp__we_go_next__deaths",
            "input" => nil
          }
        ]
      }
    }

    record = Export.build(%{id: @session_id}, %{}, [event], [], [])
    assert [%{tool_use_id: "malformed", args: nil}] = record.unscoped_transcript_calls
  end

  test "does not match another Analysis session with the same Tool and args", %{
    events: events,
    call: call
  } do
    assert [first, second] =
             Export.join(@session_id, events, [%{call | session_id: "other-session"}])

    assert first.status == "unmatched_transcript"
    assert second.status == "unmatched_transcript"
  end

  test "does not join different Tool names with identical args", %{events: events, call: call} do
    assert [first, second, server] =
             Export.join(@session_id, events, [%{call | tool: "failures"}])

    assert first.status == "unmatched_transcript"
    assert second.status == "unmatched_transcript"
    assert server.status == "unmatched_server"
    assert server.server.tool == "failures"
  end

  test "reports unmatched transcript calls", %{events: events, call: call} do
    assert [matched, unmatched] = Export.join(@session_id, events, [call])
    assert matched.status == "matched"
    assert unmatched.status == "unmatched_transcript"
    assert unmatched.server == nil
    assert unmatched.transcript.tool_use_id == "tool-2"
  end

  test "reports unmatched server rows rather than matching different args", %{
    events: events,
    call: call
  } do
    different = %{call | id: 12, args: %{"session_id" => @session_id, "pulls" => [99]}}
    assert [_, _, unmatched] = Export.join(@session_id, events, [call, different])
    assert unmatched.status == "unmatched_server"
    assert unmatched.server.id == 12
    assert unmatched.transcript == nil
  end
end
