defmodule WeGoNext.Analysis.AnthropicStream do
  @moduledoc "Incremental SSE decoding, including split UTF-8/JSON chunks and preserved thinking."
  defstruct buffer: "", message: %{}, blocks: %{}, inputs: %{}, done: false, error: nil

  def feed(state, chunk, notify) do
    parts = String.split(state.buffer <> chunk, ~r/\r?\n\r?\n/)
    {frames, [buffer]} = Enum.split(parts, -1)
    Enum.reduce(frames, %{state | buffer: buffer}, &frame(&1, &2, notify))
  end

  def finish(%{done: true, error: nil} = state) do
    content = state.blocks |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
    {:ok, Map.put(state.message, "content", content)}
  end

  def finish(_), do: {:error, "Incomplete or failed Messages API stream"}

  defp frame(frame, state, notify) do
    data =
      frame
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map_join("\n", &(&1 |> String.trim_leading("data:") |> String.trim()))

    case Jason.decode(data) do
      {:ok, event} -> event(event, state, notify)
      _ when data == "" -> state
      _ -> %{state | error: :invalid_json}
    end
  end

  defp event(%{"type" => "message_start", "message" => message}, state, _),
    do: %{state | message: message}

  defp event(
         %{"type" => "content_block_start", "index" => index, "content_block" => block},
         state,
         _
       ),
       do: %{state | blocks: Map.put(state.blocks, index, block)}

  defp event(
         %{"type" => "content_block_delta", "index" => index, "delta" => delta},
         state,
         notify
       ) do
    case delta do
      %{"type" => "input_json_delta", "partial_json" => json} ->
        %{state | inputs: Map.update(state.inputs, index, json, &(&1 <> json))}

      %{"type" => type} when type in ["text_delta", "thinking_delta", "signature_delta"] ->
        key =
          Map.fetch!(
            %{
              "text_delta" => "text",
              "thinking_delta" => "thinking",
              "signature_delta" => "signature"
            },
            type
          )

        text = Map.fetch!(delta, key)
        if type == "text_delta", do: notify.({:text_delta, text})
        block = Map.update(state.blocks[index], key, text, &(&1 <> text))
        %{state | blocks: Map.put(state.blocks, index, block)}

      _ ->
        state
    end
  end

  defp event(%{"type" => "content_block_stop", "index" => index}, state, _) do
    case Map.fetch(state.inputs, index) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, input} when is_map(input) ->
            %{state | blocks: Map.update!(state.blocks, index, &Map.put(&1, "input", input))}

          _ ->
            %{state | error: :invalid_tool_input}
        end

      :error ->
        state
    end
  end

  defp event(%{"type" => "message_delta"} = event, state, _) do
    message = Map.merge(state.message, event["delta"] || %{})
    usage = Map.merge(message["usage"] || %{}, event["usage"] || %{})
    %{state | message: Map.put(message, "usage", usage)}
  end

  defp event(%{"type" => "message_stop"}, state, _), do: %{state | done: true}
  defp event(%{"type" => "error"}, state, _), do: %{state | error: :api_error}
  defp event(_, state, _), do: state
end
