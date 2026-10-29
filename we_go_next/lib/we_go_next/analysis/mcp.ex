defmodule WeGoNext.Analysis.MCP do
  @moduledoc "Stateless MCP JSON-RPC dispatcher; Analysis sessions are minted only by the prompt."
  alias WeGoNext.Analysis
  alias WeGoNext.Analysis.Registry
  @protocol "2025-03-26"
  @prompt %{
    name: "analysis-session",
    description: "Start a log-scoped Analysis session",
    arguments: [
      %{
        name: "log",
        description: "combat_log_files id; defaults to most recently imported log",
        required: false
      },
      %{name: "boss", description: "Optional boss name or encounter id", required: false}
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

    if valid_prompt_args?(args) do
      start_prompt(args)
    else
      {:error, -32_602, "Prompt arguments must be strings: log (optional id), boss (optional)"}
    end
  end

  defp handle(method, _) when method in ["tools/call", "prompts/get"],
    do: {:error, -32_602, "Invalid parameters"}

  defp handle(_, _), do: {:error, -32_601, "Method not found"}

  defp valid_prompt_args?(args) when is_map(args),
    do: Enum.all?(args, fn {k, v} -> k in ["log", "boss"] and is_binary(v) end)

  defp valid_prompt_args?(_), do: false

  defp start_prompt(args) do
    instructions =
      :we_go_next |> :code.priv_dir() |> Path.join("analysis/analyst.md") |> File.read!()

    case Analysis.start_session(args) do
      {:ok, session} ->
        text =
          instructions <>
            "\nAnalysis session id: #{session.id}\nLog id: #{session.combat_log_file_id}\nTarget boss: #{session.boss || "all"}\n"

        {:ok,
         %{
           description: "Analysis session #{session.id}",
           messages: [%{role: "user", content: %{type: "text", text: text}}]
         }}

      {:error, reason} ->
        {:error, -32_602, reason}
    end
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
