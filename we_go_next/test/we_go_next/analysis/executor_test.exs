defmodule WeGoNext.Analysis.ExecutorTest do
  use WeGoNextWeb.ConnCase, async: false
  import Ecto.Query
  alias WeGoNext.Analysis
  alias WeGoNext.Analysis.{Executor, Session, ToolCall}
  alias WeGoNext.CombatLogFile

  defmodule WriteTool do
    def run(_, _) do
      WeGoNext.Repo.query!(
        "INSERT INTO analysis.sessions (id, started_at, combat_log_file_id) SELECT gen_random_uuid(), now(), id FROM combat_log_files LIMIT 1"
      )

      {:ok, %{data: [], evidence: [], truncated: false, next_cursor: nil}}
    end
  end

  defmodule SlowTool do
    def run(_, _) do
      receive do
        :never -> {:error, "unexpected"}
      end
    end
  end

  defmodule CrashTool do
    def run(_, _), do: raise("sensitive internal detail")
  end

  setup do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "analysis-executor"})

    log =
      Repo.insert!(%CombatLogFile{
        user_id: user.id,
        file_path: "/executor.txt",
        last_parsed_at: ~U[2026-09-06 12:00:00Z]
      })

    session = Repo.insert!(%Session{started_at: DateTime.utc_now(), combat_log_file_id: log.id})
    {:ok, session: session}
  end

  test "records the full bounded Tool result", %{session: session} do
    assert {:ok, result} = Analysis.call_tool("list_pulls", %{"session_id" => session.id})
    assert result.data == []
    call = Repo.one!(ToolCall)
    assert call.session_id == session.id
    assert call.tool == "list_pulls"
    assert call.result == Jason.decode!(Jason.encode!(result))
    assert call.result_size == byte_size(Jason.encode!(result))
    assert call.duration_ms >= 0
    assert call.error == nil
  end

  test "database writes fail inside the Tool transaction", %{session: session} do
    assert {:error, reason} = Executor.run(WriteTool, %{}, session)
    assert reason == "Tool database operation failed (read_only_sql_transaction)"
    assert Repo.aggregate(Session, :count) == 1
  end

  @tag capture_log: true
  test "the five-second deadline cancels the Tool", %{session: session} do
    start = System.monotonic_time(:millisecond)
    assert {:error, "Tool timed out after 5000 ms"} = Executor.run(SlowTool, %{}, session)
    assert System.monotonic_time(:millisecond) - start < 6_000
  end

  test "supervisor unavailability becomes a recorded Tool error", %{session: session} do
    supervisor = Process.whereis(WeGoNext.Analysis.TaskSupervisor)
    Process.unregister(WeGoNext.Analysis.TaskSupervisor)

    try do
      assert {:error, "Tool execution failed"} =
               Analysis.call_tool("list_pulls", %{"session_id" => session.id})

      assert Repo.one!(ToolCall).error == "Tool execution failed"
    after
      Process.register(supervisor, WeGoNext.Analysis.TaskSupervisor)
    end
  end

  test "Tool crashes become short errors", %{session: session} do
    assert {:error, "Tool execution failed"} = Executor.run(CrashTool, %{}, session)
  end

  test "invalid args and unknown sessions are recorded as errors", %{session: session} do
    assert {:error, _} =
             Analysis.call_tool("list_pulls", %{"session_id" => session.id, "night" => 1})

    assert {:error, _} = Analysis.call_tool("list_pulls", %{"session_id" => Ecto.UUID.generate()})
    assert Repo.aggregate(from(c in ToolCall, where: not is_nil(c.error)), :count) == 2
  end
end
