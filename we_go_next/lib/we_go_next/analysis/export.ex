defmodule WeGoNext.Analysis.Export do
  @moduledoc "Versioned Analysis session export and a pure transcript-to-recording join."

  @doc "Matches each transcript Tool use once, by session, normalized name, args and occurrence order."
  def join(session_id, events, server_calls) do
    calls =
      server_calls
      |> Enum.filter(&(&1.session_id == session_id))
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&plain/1)

    {joined, remaining} =
      events
      |> transcript_calls(session_id)
      |> Enum.map_reduce(calls, fn call, remaining ->
        index = Enum.find_index(remaining, &(&1.tool == call.tool and &1.args === call.args))
        {server, rest} = pop_match(remaining, index)
        status = if server, do: "matched", else: "unmatched_transcript"
        {%{status: status, transcript: call, server: server}, rest}
      end)

    joined ++ Enum.map(remaining, &%{status: "unmatched_server", transcript: nil, server: &1})
  end

  @doc "One JSONL record per session. Messages retain transcript-wide scope, never inferred session ownership."
  def build(session, context, events, calls, verdicts) do
    joined = join(session.id, events, calls)
    unscoped = transcript_calls(events, nil)

    %{
      schema_version: 1,
      type: "analysis_session",
      session: plain(session),
      context: context,
      messages_scope: "source_transcripts",
      messages: Enum.filter(events, &is_map(&1["message"])),
      tool_calls: joined,
      unscoped_transcript_calls: unscoped,
      verdicts: Enum.map(verdicts, &plain/1),
      unmatched: %{
        transcript_calls: Enum.count(joined, &(&1.status == "unmatched_transcript")),
        server_calls: Enum.count(joined, &(&1.status == "unmatched_server")),
        unscoped_transcript_calls: length(unscoped)
      }
    }
  end

  @doc "Exports persisted in-app messages in the v1 envelope, with exact Analysis-session scope."
  def build_in_app(session, context, messages, calls, verdicts) do
    events =
      Enum.map(messages, fn message ->
        %{
          "uuid" => to_string(message.id),
          "sessionId" => session.id,
          "question_id" => message.question_id,
          "timestamp" => DateTime.to_iso8601(message.inserted_at),
          "_source" => %{path: "analysis.messages:#{session.id}", line: message.id},
          "message" => %{
            "role" => message.role,
            "content" => message.content,
            "usage" => message.usage,
            "stop_reason" => message.stop_reason
          }
        }
      end)

    # Execution pins session_id to the owning Analysis session. Keep the original
    # wire input in messages, but join using the effective, scoped executor args.
    scoped = Enum.map(events, &scope_event(&1, session.id))

    record = build(session, context, scoped, calls, verdicts)
    %{record | messages_scope: "analysis_session", messages: events}
  end

  defp scope_event(event, session_id) do
    update_in(event, ["message", "content"], fn blocks ->
      Enum.map(blocks, &scope_block(&1, session_id))
    end)
  end

  defp scope_block(%{"type" => "tool_use", "input" => input} = block, session_id),
    do: Map.put(block, "input", Map.put(input, "session_id", session_id))

  defp scope_block(block, _session_id), do: block

  defp transcript_calls(events, session_id) do
    results = transcript_results(events)

    for event <- events,
        block <- content(event),
        block["type"] == "tool_use",
        analysis_session_id(block["input"]) == session_id do
      %{
        tool_use_id: block["id"],
        tool: tool_name(block["name"]),
        wire_name: block["name"],
        args: block["input"],
        message_uuid: event["uuid"],
        transcript_session_id: event["sessionId"],
        source: event["_source"],
        timestamp: event["timestamp"],
        results: Map.get(results, identity(event, block["id"]), [])
      }
    end
  end

  defp analysis_session_id(%{"session_id" => id}), do: id
  defp analysis_session_id(_), do: nil

  defp transcript_results(events) do
    for event <- events, block <- content(event), block["type"] == "tool_result", reduce: %{} do
      acc ->
        result =
          Map.merge(block, %{"timestamp" => event["timestamp"], "message_uuid" => event["uuid"]})

        Map.update(acc, identity(event, block["tool_use_id"]), [result], &(&1 ++ [result]))
    end
  end

  defp identity(event, id) do
    source =
      case event["_source"] do
        %{path: path} -> path
        source -> source
      end

    {source, event["sessionId"], id}
  end

  defp content(%{"message" => %{"content" => blocks}}) when is_list(blocks),
    do: Enum.filter(blocks, &is_map/1)

  defp content(_), do: []

  defp tool_name("mcp__" <> _ = name), do: name |> String.split("__") |> List.last()
  defp tool_name(name), do: name

  defp pop_match(calls, nil), do: {nil, calls}
  defp pop_match(calls, index), do: List.pop_at(calls, index)

  defp plain(%module{} = value), do: Map.take(value, module.__schema__(:fields))
  defp plain(value), do: value
end
