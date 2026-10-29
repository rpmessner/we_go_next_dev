defmodule WeGoNext.Analysis do
  @moduledoc "Analysis sessions and recorded, bounded Tool calls, separate from the medallion."
  import Ecto.Query
  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Analysis.{Arguments, Executor, Registry, Result, Session, ToolCall}

  def start_session(args \\ %{}) do
    with {:ok, log} <- resolve_log(args["log"]) do
      Repo.insert(%Session{
        started_at: DateTime.utc_now(),
        combat_log_file_id: log.id,
        boss: args["boss"]
      })
    end
  end

  def call_tool(name, args) when is_binary(name) and is_map(args) do
    start = System.monotonic_time(:millisecond)
    session = find_session(args["session_id"])
    outcome = invoke(Registry.fetch(name), args, session)
    {result, error} = recorded_result(outcome)

    Repo.insert!(%ToolCall{
      session_id: session && session.id,
      tool: name,
      args: args,
      result: result,
      result_size: byte_size(Jason.encode!(result)),
      duration_ms: System.monotonic_time(:millisecond) - start,
      truncated: Map.get(result, :truncated, false),
      error: error,
      called_at: DateTime.utc_now()
    })

    outcome
  rescue
    _ -> {:error, "Tool call could not be recorded"}
  end

  defp invoke(nil, _, _), do: {:error, "Unknown Tool"}
  defp invoke(_, _, nil), do: {:error, "Unknown Analysis session; invoke analysis-session first"}

  defp invoke(tool, args, session) do
    with :ok <- Arguments.validate(args, tool.input_schema()),
         {:ok, result} <- Executor.run(tool, args, session),
         true <- valid_envelope?(result) do
      {:ok, result}
    else
      false -> {:error, "Tool returned an invalid or oversized result"}
      {:error, _} = error -> error
      _ -> {:error, "Tool returned an invalid result"}
    end
  rescue
    _ -> {:error, "Tool returned an invalid result"}
  end

  defp valid_envelope?(result) when is_map(result) do
    Map.has_key?(result, :data) and is_list(result[:evidence]) and is_boolean(result[:truncated]) and
      (is_nil(result[:next_cursor]) or is_binary(result[:next_cursor])) and
      byte_size(Jason.encode!(result)) <= Result.cap()
  end

  defp valid_envelope?(_), do: false

  defp find_session(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Session, uuid)
      :error -> nil
    end
  end

  defp recorded_result({:ok, result}), do: {result, nil}

  defp recorded_result({:error, reason}), do: {error_result(reason), reason}

  def error_result(reason),
    do: %{data: nil, evidence: [], truncated: false, next_cursor: nil, error: reason}

  defp resolve_log(nil) do
    case Repo.one(
           from(l in CombatLogFile,
             where: not is_nil(l.last_parsed_at),
             order_by: [desc: l.last_parsed_at, desc: l.id],
             limit: 1
           )
         ) do
      nil -> {:error, "No imported log is available"}
      log -> {:ok, log}
    end
  end

  defp resolve_log(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 ->
        case Repo.get(CombatLogFile, id) do
          nil -> {:error, "Log not found"}
          log -> {:ok, log}
        end

      _ ->
        {:error, "log must be a combat_log_files id"}
    end
  end

  defp resolve_log(_), do: {:error, "log must be a combat_log_files id"}
end
