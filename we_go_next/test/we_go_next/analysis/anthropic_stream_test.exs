defmodule WeGoNext.Analysis.AnthropicStreamTest do
  use ExUnit.Case, async: true
  alias WeGoNext.Analysis.AnthropicStream, as: Stream

  test "byte-split SSE preserves signed thinking, unicode, partial Tool JSON and cumulative usage" do
    events = [
      %{"type" => "ping"},
      %{"type" => "future_event"},
      %{
        "type" => "message_start",
        "message" => %{
          "role" => "assistant",
          "usage" => %{"input_tokens" => 9, "cache_creation_input_tokens" => 23}
        }
      },
      %{
        "type" => "content_block_start",
        "index" => 0,
        "content_block" => %{"type" => "thinking", "thinking" => ""}
      },
      %{
        "type" => "content_block_delta",
        "index" => 0,
        "delta" => %{"type" => "thinking_delta", "thinking" => "check"}
      },
      %{
        "type" => "content_block_delta",
        "index" => 0,
        "delta" => %{"type" => "signature_delta", "signature" => "signed"}
      },
      %{
        "type" => "content_block_start",
        "index" => 1,
        "content_block" => %{"type" => "text", "text" => ""}
      },
      %{
        "type" => "content_block_delta",
        "index" => 1,
        "delta" => %{"type" => "text_delta", "text" => "Mittwöch"}
      },
      %{
        "type" => "content_block_start",
        "index" => 2,
        "content_block" => %{
          "type" => "tool_use",
          "id" => "t1",
          "name" => "list_pulls",
          "input" => %{}
        }
      },
      %{
        "type" => "content_block_delta",
        "index" => 2,
        "delta" => %{"type" => "input_json_delta", "partial_json" => "{\"boss\":"}
      },
      %{
        "type" => "content_block_delta",
        "index" => 2,
        "delta" => %{"type" => "input_json_delta", "partial_json" => "\"Sszorak\"}"}
      },
      %{"type" => "content_block_stop", "index" => 2},
      %{
        "type" => "message_delta",
        "delta" => %{"stop_reason" => "tool_use"},
        "usage" => %{"output_tokens" => 4}
      },
      %{"type" => "message_delta", "delta" => %{}, "usage" => %{"output_tokens" => 6}},
      %{"type" => "message_stop"}
    ]

    bytes =
      Enum.map_join(
        events,
        "",
        &("event: " <> &1["type"] <> "\r\ndata: " <> Jason.encode!(&1) <> "\r\n\r\n")
      )

    state =
      for <<byte <- bytes>>, reduce: %Stream{} do
        state -> Stream.feed(state, <<byte>>, &send(self(), &1))
      end

    assert {:ok, result} = Stream.finish(state)

    assert [
             %{"thinking" => "check", "signature" => "signed"},
             %{"text" => "Mittwöch"},
             %{"input" => %{"boss" => "Sszorak"}}
           ] = result["content"]

    assert result["usage"] == %{
             "input_tokens" => 9,
             "cache_creation_input_tokens" => 23,
             "output_tokens" => 6
           }

    assert_receive {:text_delta, "Mittwöch"}
  end

  test "incomplete, invalid and API-error streams cannot masquerade as answers" do
    for frames <- [[], [%{"type" => "error"}, %{"type" => "message_stop"}]] do
      state =
        Enum.reduce(frames, %Stream{}, fn event, state ->
          Stream.feed(state, "data: " <> Jason.encode!(event) <> "\n\n", fn _ -> :ok end)
        end)

      assert {:error, _} = Stream.finish(state)
    end

    state =
      Stream.feed(%Stream{}, "data: invalid\n\ndata: {\"type\":\"message_stop\"}\n\n", fn _ ->
        :ok
      end)

    assert {:error, _} = Stream.finish(state)
  end
end
