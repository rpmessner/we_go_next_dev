defmodule WeGoNext.Analysis.VerdictTest do
  use WeGoNext.DataCase, async: false
  alias WeGoNext.{Analysis, Repo}
  alias WeGoNext.Analysis.{Session, ToolCall, Verdict}
  alias WeGoNext.Analysis.Tools.RecordVerdict

  setup do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "verdict-test"})
    log = Repo.insert!(%WeGoNext.CombatLogFile{user_id: user.id, file_path: "/verdict.txt"})
    session = Repo.insert!(%Session{combat_log_file_id: log.id, started_at: DateTime.utc_now()})

    args = %{
      "session_id" => session.id,
      "answer" => "Q1: the tank died first",
      "verdict" => "wrong",
      "correction" => "The healer died first"
    }

    {:ok, session: session, args: args}
  end

  test "run prepares the operator verdict without writing inside the Tool", %{
    session: session,
    args: args
  } do
    assert {:ok, result} = RecordVerdict.run(args, session)
    assert result.data == Map.take(args, ["answer", "verdict", "correction"])
    assert result.evidence == [%{source: "analysis.verdicts", session_id: session.id}]
    refute result.truncated
    assert result.next_cursor == nil
    assert Repo.aggregate(Verdict, :count) == 0
  end

  test "recording stores the verdict linked to its session and judged answer", %{
    session: session,
    args: args
  } do
    assert {:ok, result} = Analysis.call_tool("record_verdict", args)
    assert result.data["verdict"] == "wrong"

    %{rows: [[id, answer, verdict, correction]]} =
      Repo.query!("SELECT session_id::text, answer, verdict, correction FROM analysis.verdicts")

    assert id == session.id
    assert answer == args["answer"]
    assert verdict == "wrong"
    assert correction == "The healer died first"
    assert Repo.one!(ToolCall).tool == "record_verdict"
  end

  test "record_verdict advances the persisted question through its lifecycle", %{
    session: session,
    args: args
  } do
    question =
      Repo.insert!(%Analysis.Question{
        session_id: session.id,
        model: session.model,
        text: "Why?",
        state: "answered",
        answer: args["answer"],
        lifecycle: Analysis.QuestionLifecycle.initial()
      })

    Analysis.subscribe_question(question.id)
    assert {:ok, _} = Analysis.call_tool("record_verdict", args)
    assert_receive {:analysis_question, id, {:state, :judged}}
    assert id == question.id
    judged = Analysis.get_question(question.id)
    assert judged.state == "judged"
    assert judged.lifecycle["verdict"]
    assert Repo.aggregate(Verdict, :count) == 1
  end

  test "failed verdict audit also rolls back the machine transition", %{
    session: session,
    args: args
  } do
    question =
      Repo.insert!(%Analysis.Question{
        session_id: session.id,
        model: session.model,
        text: "Why?",
        state: "answered",
        answer: args["answer"],
        lifecycle: Analysis.QuestionLifecycle.initial()
      })

    Repo.query!(
      "ALTER TABLE analysis.tool_calls ADD CONSTRAINT reject_question_verdict CHECK (tool <> 'record_verdict')"
    )

    assert {:error, "Tool call could not be recorded"} =
             Analysis.call_tool("record_verdict", args)

    assert Analysis.get_question(question.id).state == "answered"
    assert Repo.aggregate(Verdict, :count) == 0
  end

  test "an ambiguous answer never judges an arbitrary question", %{session: session, args: args} do
    for _ <- 1..2 do
      Repo.insert!(%Analysis.Question{
        session_id: session.id,
        model: session.model,
        text: "Why?",
        state: "answered",
        answer: args["answer"],
        lifecycle: Analysis.QuestionLifecycle.initial()
      })
    end

    assert {:error, "Tool call could not be recorded"} =
             Analysis.call_tool("record_verdict", args)

    assert Repo.aggregate(Verdict, :count) == 0
    assert Repo.all(Analysis.Question) |> Enum.all?(&(&1.state == "answered"))
  end

  test "question_id selects the answer explicitly when answer text is ambiguous", %{
    session: session,
    args: args
  } do
    questions =
      for _ <- 1..2 do
        Repo.insert!(%Analysis.Question{
          session_id: session.id,
          model: session.model,
          text: "Why?",
          state: "answered",
          answer: args["answer"],
          lifecycle: Analysis.QuestionLifecycle.initial()
        })
      end

    [first, selected] = questions

    assert {:ok, _} =
             Analysis.call_tool("record_verdict", Map.put(args, "question_id", selected.id))

    assert Analysis.get_question(first.id).state == "answered"
    assert Analysis.get_question(selected.id).state == "judged"
  end

  test "recorded duration excludes verdict persistence time", %{args: args} do
    Repo.query!(
      "CREATE FUNCTION analysis.delay_verdict_test() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN PERFORM pg_sleep(0.15); RETURN NEW; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER delay_verdict_test BEFORE INSERT ON analysis.verdicts FOR EACH ROW EXECUTE FUNCTION analysis.delay_verdict_test()"
    )

    start = System.monotonic_time(:millisecond)
    assert {:ok, _} = Analysis.call_tool("record_verdict", args)
    elapsed = System.monotonic_time(:millisecond) - start
    assert elapsed - Repo.one!(ToolCall).duration_ms >= 100
  end

  test "an audit insert failure rolls back the verdict with it", %{args: args} do
    Repo.query!(
      "ALTER TABLE analysis.tool_calls ADD CONSTRAINT reject_verdict_audit CHECK (tool <> 'record_verdict')"
    )

    assert {:error, "Tool call could not be recorded"} =
             Analysis.call_tool("record_verdict", args)

    assert Repo.aggregate(Verdict, :count) == 0
    assert Repo.aggregate(ToolCall, :count) == 0
  end

  test "all three judgments work, including a correct answer without correction", %{args: args} do
    for verdict <- ["correct", "partly", "wrong"] do
      assert {:ok, _} =
               Analysis.call_tool("record_verdict", %{
                 args
                 | "verdict" => verdict,
                   "correction" => ""
               })
    end

    assert Repo.aggregate(Verdict, :count) == 3
  end

  test "oversized escaped feedback fails the shared envelope cap without storing a verdict", %{
    session: session,
    args: args
  } do
    large = %{
      args
      | "answer" => String.duplicate("\"", 3000),
        "correction" => String.duplicate("\"", 3000)
    }

    assert {:error, "A single result row exceeds the Tool result cap"} =
             RecordVerdict.run(large, session)

    assert {:error, _} = Analysis.call_tool("record_verdict", large)
    assert Repo.aggregate(Verdict, :count) == 0
  end

  test "invalid verdicts and missing answer links are audited but never stored", %{args: args} do
    for invalid <- [
          Map.put(args, "verdict", "maybe"),
          Map.delete(args, "answer"),
          Map.put(args, "answer", ""),
          Map.put(args, "session_id", Ecto.UUID.generate())
        ] do
      assert {:error, _} = Analysis.call_tool("record_verdict", invalid)
    end

    assert Repo.aggregate(Verdict, :count) == 0
    assert Repo.aggregate(ToolCall, :count) == 4
  end
end
