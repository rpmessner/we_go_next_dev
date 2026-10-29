defmodule WeGoNext.Analysis.MCP do
  @moduledoc "Stateless MCP JSON-RPC dispatcher with shared prompt and Tool session startup."
  alias WeGoNext.Analysis
  alias WeGoNext.Analysis.{Registry, Startup}
  @protocol "2025-03-26"
  @prompt %{
    name: "analysis-session",
    description: "Start a log-scoped Analysis session",
    arguments: [
      %{name: "boss", description: "Optional boss name or encounter id", required: false},
      %{
        name: "log",
        description: "Imported log id or filename fragment; blank defaults to latest import",
        required: false
      }
    ]
  }

  def dispatch([_ | _] = requests) do
    if Enum.any?(requests, &match?(%{"method" => "initialize"}, &1)) do
      error(nil, -32_600, "Initialization cannot be batched")
    else
      case requests |> Enum.map(&dispatch/1) |> Enum.reject(&(&1 == :notification)) do
        [] -> :notification
        responses -> responses
      end
    end
  end

  def dispatch(%{"jsonrpc" => "2.0", "method" => method} = request) when is_binary(method) do
    if Map.has_key?(request, "id") do
      case handle(method, Map.get(request, "params", %{})) do
        {:ok, result} -> %{jsonrpc: "2.0", id: request["id"], result: result}
        {:error, code, message} -> error(request["id"], code, message)
      end
    else
      :notification
    end
  rescue
    _ -> error(request["id"], -32_603, "Analysis service unavailable")
  end

  def dispatch(_), do: error(nil, -32_600, "Invalid JSON-RPC request")

  def error(id, code, message),
    do: %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}

  defp handle("initialize", params) when is_map(params) do
    {:ok,
     %{
       protocolVersion: @protocol,
       capabilities: %{tools: %{}, prompts: %{}},
       serverInfo: %{name: "we-go-next-analysis", version: "0.1.0"}
     }}
  end

  defp handle("ping", _), do: {:ok, %{}}
  defp handle("tools/list", _), do: {:ok, %{tools: Registry.definitions()}}
  defp handle("prompts/list", _), do: {:ok, %{prompts: [@prompt]}}

  defp handle("tools/call", %{"name" => name} = params) when is_binary(name) do
    case Map.get(params, "arguments", %{}) do
      args when is_map(args) -> tool_result(Analysis.call_tool(name, args))
      _ -> {:error, -32_602, "Tool arguments must be an object"}
    end
  end

  defp handle("prompts/get", %{"name" => "analysis-session"} = params) do
    args = Map.get(params, "arguments", %{})

    start_prompt(args)
  end

  defp handle(method, _) when method in ["tools/call", "prompts/get"],
    do: {:error, -32_602, "Invalid parameters"}

  defp handle(_, _), do: {:error, -32_601, "Method not found"}

  defp start_prompt(args) do
    response = Startup.response(args)

    {:ok,
     %{
       description:
         if(response.session_id,
           do: "Analysis session #{response.session_id}",
           else: "Choose an imported log"
         ),
       messages: [%{role: "user", content: %{type: "text", text: response.instructions}}]
     }}
  end

  defp tool_result({:ok, result}),
    do: {:ok, %{isError: false, content: [%{type: "text", text: Jason.encode!(result)}]}}

  defp tool_result({:error, reason}),
    do:
      {:ok,
       %{
         isError: true,
         content: [%{type: "text", text: Jason.encode!(Analysis.error_result(reason))}]
       }}
end
