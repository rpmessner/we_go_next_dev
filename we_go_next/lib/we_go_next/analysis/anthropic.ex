defmodule WeGoNext.Analysis.Anthropic do
  @moduledoc "Anthropic Messages over Req. No SDK, implicit retry, or paid call outside an explicit question."
  alias WeGoNext.Analysis.{AnthropicStream, Registry}

  def request(system, messages, model, notify, opts \\ []) do
    case System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" ->
        send_request(body(system, messages, model, opts), key, notify, opts)

      _ ->
        {:error, "ANTHROPIC_API_KEY is not set"}
    end
  end

  def body(system, messages, model, opts \\ []) do
    cache = %{type: "ephemeral", ttl: "1h"}

    tools =
      Registry.tools()
      |> Enum.reject(&(&1.name() == "start_session"))
      |> Enum.map(fn tool ->
        %{name: tool.name(), description: tool.description(), input_schema: tool.input_schema()}
      end)
      |> List.update_at(-1, &Map.put(&1, :cache_control, cache))

    %{
      model: model,
      max_tokens: 8192,
      stream: true,
      system: [%{type: "text", text: system, cache_control: cache}],
      tools: tools,
      tool_choice: tool_choice(opts),
      cache_control: cache,
      messages: messages
    }
  end

  defp tool_choice(opts) do
    if Keyword.get(opts, :answer_only, false),
      do: %{type: "none"},
      else: %{type: "auto", disable_parallel_tool_use: true}
  end

  defp send_request(body, key, notify, opts) do
    into = fn {:data, chunk}, {request, response} ->
      stream = Map.get(response.private, :analysis_stream, %AnthropicStream{})
      stream = AnthropicStream.feed(stream, chunk, notify)
      {:cont, {request, Req.Response.put_private(response, :analysis_stream, stream)}}
    end

    options =
      Keyword.merge(Keyword.get(opts, :req_options, []),
        url: "https://api.anthropic.com/v1/messages",
        headers: [{"x-api-key", key}, {"anthropic-version", "2023-06-01"}],
        json: body,
        retry: false,
        receive_timeout: 600_000,
        into: into
      )

    case Req.post(options) do
      {:ok, %{status: 200, private: %{analysis_stream: stream}}} -> AnthropicStream.finish(stream)
      {:ok, %{status: status}} -> {:error, "Messages API HTTP #{status}"}
      {:error, _} -> {:error, "Messages API connection failed"}
    end
  rescue
    _ -> {:error, "Messages API request failed"}
  end
end
