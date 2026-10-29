defmodule WeGoNext.Analysis.Executor do
  @moduledoc "Enforces Tool deadlines and read-only transactions, except approved session creation."
  alias WeGoNext.Repo
  @timeout 5_000

  def run(tool, args, session) do
    task =
      Task.Supervisor.async_nolink(WeGoNext.Analysis.TaskSupervisor, fn ->
        execute(tool, args, session)
      end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, "Tool timed out after 5000 ms"}
      {:exit, _} -> {:error, "Tool execution failed"}
    end
  catch
    :exit, _ -> {:error, "Tool execution failed"}
  end

  defp execute(WeGoNext.Analysis.Tools.StartSession = tool, args, _session),
    do: tool.run(args, nil)

  defp execute(tool, args, session) do
    case Repo.transaction(
           fn ->
             Repo.query!("SET TRANSACTION READ ONLY")
             Repo.query!("SET LOCAL statement_timeout = '5000ms'")
             tool.run(args, session)
           end,
           timeout: @timeout + 1_000
         ) do
      {:ok, result} -> result
      {:error, _} -> {:error, "Tool transaction failed"}
    end
  rescue
    error in Postgrex.Error ->
      {:error, "Tool database operation failed (#{error.postgres[:code]})"}

    _ ->
      {:error, "Tool execution failed"}
  catch
    _, _ -> {:error, "Tool execution failed"}
  end
end
