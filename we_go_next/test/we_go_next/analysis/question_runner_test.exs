defmodule WeGoNext.Analysis.QuestionRunnerTest do
  use WeGoNext.DataCase, async: false
  import Ecto.Query
  alias WeGoNext.{Analysis, CombatLogFile, Repo}
  alias WeGoNext.Analysis.{Export, Message, QuestionRunner, ToolCall}

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Req.Test.set_req_test_to_shared()
    old = System.get_env("ANTHROPIC_API_KEY")
    System.put_env("ANTHROPIC_API_KEY", "stub-not-a-secret")

    on_exit(fn ->
      if old,
        do: System.put_env("ANTHROPIC_API_KEY", old),
        else: System.delete_env("ANTHROPIC_API_KEY")
    end)

    user = Repo.insert!(%WeGoNext.Accounts.User{name: "agent-loop"})

    log =
      Repo.insert!(%CombatLogFile{
        user_id: user.id,
        file_path: "/fixture-sept6.txt",
        last_parsed_at: ~U[2026-09-06 12:00:00Z]
      })

    %{scope: %{"log" => log.id, "boss" => "Sszorak", "pull_number" => 5}}
  end

  test "a supervised question runs Tools, preserves messages, answers and exports", %{
    scope: scope
  } do
    owner = self()

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(body)
      send(owner, {:request, body})

      respond(
        conn,
        [
          %{
            "type" => "tool_use",
            "id" => "call-1",
            "name" => "list_pulls",
            "input" => %{"boss" => "Sszorak"}
          }
        ],
        "tool_use"
      )
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:answer_request, Jason.decode!(body)})

      respond(
        conn,
        [
          %{"type" => "thinking", "thinking" => "", "signature" => "signed"},
          %{"type" => "text", "text" => "No matching pulls [list_pulls]."}
        ],
        "end_turn"
      )
    end)

    {question, pid} = ask(scope, cap: 2)
    assert is_pid(pid)
    assert_receive {:request, body}, 5_000
    assert body["model"] == "claude-opus-5-5"
    assert hd(body["system"])["cache_control"] == %{"type" => "ephemeral", "ttl" => "1h"}
    assert List.last(body["tools"])["cache_control"]["ttl"] == "1h"
    assert_receive {:answer_request, body}, 5_000
    assert body["tool_choice"]["type"] == "none"

    assert [%{"type" => "tool_result", "tool_use_id" => "call-1", "is_error" => false}] =
             List.last(body["messages"])["content"]

    await_state(question.id, :answered)
    assert Analysis.get_question(question.id).answer == "No matching pulls [list_pulls]."
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert {:answered, _} = QuestionRunner.snapshot(question.id)
    calls = Repo.all(from(c in ToolCall, where: c.session_id == ^question.session_id))
    assert [%{tool: "list_pulls", error: nil}] = calls
    assert hd(calls).args["session_id"] == question.session_id

    messages =
      Repo.all(from(m in Message, where: m.session_id == ^question.session_id, order_by: m.id))

    assert Enum.map(messages, & &1.role) == ["user", "assistant", "user", "assistant"]
    assert List.last(messages).usage["cache_read_input_tokens"] == 200
    assert hd(List.last(messages).content)["signature"] == "signed"
    session = Repo.get!(Analysis.Session, question.session_id)
    export = Export.build_in_app(session, %{}, messages, calls, [])
    assert export.schema_version == 1
    assert export.messages_scope == "analysis_session"
    assert [%{status: "matched", transcript: %{results: [_]}}] = export.tool_calls
    assert export.unmatched.server_calls == 0
    assert export.unmatched.unscoped_transcript_calls == 0
    assert {:ok, _} = Jason.encode(export)
    path = Path.join(System.tmp_dir!(), "analysis-export-#{Ecto.UUID.generate()}.jsonl")
    on_exit(fn -> File.rm(path) end)

    ExUnit.CaptureIO.capture_io(fn ->
      Mix.Tasks.Wgn.ExportAnalysis.run(["--session", question.session_id, "--output", path])
    end)

    actual = path |> File.read!() |> Jason.decode!()
    assert actual["messages_scope"] == "analysis_session"
    assert [%{"status" => "matched"}] = actual["tool_calls"]
    assert length(actual["messages"]) == 4
    assert_mixed_night_export(session)
    Req.Test.verify!()
  end

  test "HTTP errors are recorded as failed and Retry re-arms the question", %{scope: scope} do
    owner = self()

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:original_system, Jason.decode!(body)["system"]})
      Plug.Conn.send_resp(conn, 429, "private body must not be stored")
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:retry_system, Jason.decode!(body)["system"]})
      respond(conn, [%{"type" => "text", "text" => "Retried [inference]."}], "end_turn")
    end)

    {question, _} = ask(scope)
    await_state(question.id, :failed)
    assert Analysis.get_question(question.id).error == "Messages API HTTP 429"

    assert :ok =
             Analysis.question_event(question.id, :retry,
               req_options: [plug: {Req.Test, __MODULE__}]
             )

    await_state(question.id, :answered)
    assert Analysis.get_question(question.id).error == nil
    assert_receive {:original_system, original_system}
    assert_receive {:retry_system, retry_system}
    assert retry_system == original_system
    Req.Test.verify!()
  end

  test "cancel and the ten-minute timer stop an outstanding API request", %{scope: scope} do
    owner = self()

    Req.Test.stub(__MODULE__, fn conn ->
      send(owner, {:http_started, self()})

      receive do
        :release -> respond(conn, [%{"type" => "text", "text" => "too late"}], "end_turn")
      end
    end)

    for stop <- [:cancel, :timeout] do
      opts = if stop == :timeout, do: [timeout_ms: 50], else: []
      {question, _} = ask(scope, opts)
      assert_receive {:http_started, worker}, 5_000
      monitor = Process.monitor(worker)
      if stop == :cancel, do: Analysis.question_event(question.id, :cancel)
      await_state(question.id, if(stop == :cancel, do: :cancelled, else: :limit_hit))
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 5_000
      assert Analysis.get_question(question.id).answer == nil
    end
  end

  test "a deterministic built-in uses the recorded executor without the model", %{scope: scope} do
    System.delete_env("ANTHROPIC_API_KEY")
    {question, _} = ask(scope, kind: :builtin, builtin_tool: {"list_pulls", %{}})
    await_state(question.id, :answered)
    assert Analysis.get_question(question.id).lifecycle["model_calls"] == 0

    assert [%{tool: "list_pulls"}] =
             Repo.all(from(c in ToolCall, where: c.session_id == ^question.session_id))
  end

  test "a Tool error is recorded and returned to the model, not a process crash", %{scope: scope} do
    owner = self()

    Req.Test.expect(
      __MODULE__,
      &respond(
        &1,
        [%{"type" => "tool_use", "id" => "bad", "name" => "unknown", "input" => %{}}],
        "tool_use"
      )
    )

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:tool_error, List.last(Jason.decode!(body)["messages"])})
      respond(conn, [%{"type" => "text", "text" => "Cannot verify [inference]."}], "end_turn")
    end)

    {question, _} = ask(scope)
    await_state(question.id, :answered)

    assert_receive {:tool_error,
                    %{"content" => [%{"is_error" => true, "content" => "Unknown Tool"}]}}

    assert [%{error: "Unknown Tool"}] =
             Repo.all(from(c in ToolCall, where: c.session_id == ^question.session_id))
  end

  test "unexpected parallel Tool requests fail without executing unmodeled work", %{scope: scope} do
    calls =
      for id <- ["one", "two"],
          do: %{"type" => "tool_use", "id" => id, "name" => "list_pulls", "input" => %{}}

    Req.Test.expect(__MODULE__, &respond(&1, calls, "tool_use"))
    {question, _} = ask(scope)
    await_state(question.id, :failed)
    assert Analysis.get_question(question.id).error =~ "exactly one valid Tool"
    assert Repo.all(from(c in ToolCall, where: c.session_id == ^question.session_id)) == []

    result =
      Repo.one!(
        from(m in Message, where: m.question_id == ^question.id, order_by: [desc: m.id], limit: 1)
      )

    assert Enum.map(result.content, & &1["tool_use_id"]) == ["one", "two"]
    assert Enum.all?(result.content, & &1["is_error"])
  end

  test "the headless Mix task prints a recorded answer using stubbed HTTP", %{scope: scope} do
    old = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__})
    on_exit(fn -> Req.default_options(old) end)

    Req.Test.expect(
      __MODULE__,
      &respond(
        &1,
        [%{"type" => "text", "text" => "A cited answer [Sszorak pull 5, 0:12, deaths]."}],
        "end_turn"
      )
    )

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Wgn.Ask.run([
          "--log",
          to_string(scope["log"]),
          "--boss",
          "Sszorak",
          "--pull",
          "5"
        ])
      end)

    assert output =~ "A cited answer [Sszorak pull 5, 0:12, deaths]."
    assert output =~ "Analysis session"
    question = Repo.one!(from(q in Analysis.Question, order_by: [desc: q.inserted_at], limit: 1))

    assert question.text ==
             "Why did Sszorak pull 5 wipe: what was the first thing that went wrong?"

    assert question.state == "answered"
    assert Registry.lookup(Analysis.QuestionRegistry, question.id) == []
    Req.Test.verify!()
  end

  test "without a runtime key the question fails without making an HTTP request", %{scope: scope} do
    System.delete_env("ANTHROPIC_API_KEY")
    {question, _} = ask(scope)
    await_state(question.id, :failed)
    assert Analysis.get_question(question.id).error == "ANTHROPIC_API_KEY is not set"
  end

  test "a dead Registry entry cannot prevent restarting a stored question", %{scope: scope} do
    {:ok, session} = Analysis.start_session(%{"log" => to_string(scope["log"])})

    question =
      Repo.insert!(%Analysis.Question{
        session_id: session.id,
        model: session.model,
        text: "Why?",
        state: "failed",
        lifecycle: Analysis.QuestionLifecycle.initial()
      })

    [{_, partition, _, _}] = Supervisor.which_children(Analysis.QuestionRegistry)
    :sys.suspend(partition)

    try do
      owner = self()

      {dead, monitor} =
        spawn_monitor(fn ->
          Registry.register(Analysis.QuestionRegistry, question.id, nil)
          send(owner, :registered)

          receive do
            :finish -> :ok
          end
        end)

      assert_receive :registered
      send(dead, :finish)
      assert_receive {:DOWN, ^monitor, :process, ^dead, :normal}
      assert [{^dead, _}] = Registry.lookup(Analysis.QuestionRegistry, question.id)

      result =
        try do
          Analysis.question_event(question.id, :cancel)
        catch
          :exit, reason -> {:crashed, reason}
        end

      assert result == :ok
    after
      :sys.resume(partition)
    end
  end

  test "Continue restarts a stopped limit snapshot without duplicating the question", %{
    scope: scope
  } do
    owner = self()

    Req.Test.expect(__MODULE__, fn conn ->
      send(owner, :waiting_for_timeout)

      receive do
        :release -> respond(conn, [], "end_turn")
      end
    end)

    {question, pid} = ask(scope, timeout_ms: 50, cap: 2, raised_cap: 4)
    monitor = Process.monitor(pid)
    assert_receive :waiting_for_timeout, 5_000
    await_state(question.id, :limit_hit)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 1_000

    Req.Test.expect(
      __MODULE__,
      &respond(&1, [%{"type" => "text", "text" => "Continued"}], "end_turn")
    )

    assert :ok =
             Analysis.question_event(question.id, :continue,
               req_options: [plug: {Req.Test, __MODULE__}]
             )

    await_state(question.id, :answered)
    question = Analysis.get_question(question.id)
    assert question.answer == "Continued"
    assert question.lifecycle["raised"]
    assert question.lifecycle["cap"] == 4

    assert Repo.aggregate(
             from(m in Message, where: m.question_id == ^question.id and m.role == "user"),
             :count
           ) == 1

    assert :ok = Analysis.question_event(question.id, :record_verdict)
    await_state(question.id, :judged)
    assert Analysis.get_question(question.id).lifecycle["verdict"]
    Req.Test.verify!()
  end

  test "Cancel keeps the runner only until its late Tool result is appended", %{scope: scope} do
    Repo.query!(
      "CREATE FUNCTION analysis.delay_tool_test() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN PERFORM pg_sleep(0.2); RETURN NEW; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER delay_tool_test BEFORE INSERT ON analysis.tool_calls FOR EACH ROW EXECUTE FUNCTION analysis.delay_tool_test()"
    )

    Req.Test.expect(
      __MODULE__,
      &respond(
        &1,
        [%{"type" => "tool_use", "id" => "late", "name" => "list_pulls", "input" => %{}}],
        "tool_use"
      )
    )

    {question, pid} = ask(scope)
    monitor = Process.monitor(pid)
    await_state(question.id, :calling_tool)
    assert :ok = Analysis.question_event(question.id, :cancel)
    await_state(question.id, :cancelled)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
    question = Analysis.get_question(question.id)
    assert question.state == "cancelled"
    assert question.lifecycle["recorded"] == 1
    assert question.lifecycle["tool_calls"] == 1

    result =
      Repo.one!(
        from(m in Message, where: m.question_id == ^question.id, order_by: [desc: m.id], limit: 1)
      )

    assert [%{"type" => "tool_result", "tool_use_id" => "late", "is_error" => false}] =
             result.content

    Req.Test.verify!()
  end

  test "a failed transition write is visible to the caller and subscriber", %{scope: scope} do
    owner = self()

    Req.Test.stub(__MODULE__, fn conn ->
      send(owner, :request_waiting)

      receive do
        :release -> respond(conn, [], "end_turn")
      end
    end)

    {question, pid} = ask(scope)
    assert_receive :request_waiting, 5_000

    Repo.query!(
      "ALTER TABLE analysis.questions ADD CONSTRAINT reject_cancel CHECK (state <> 'cancelled')"
    )

    monitor = Process.monitor(pid)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        result =
          try do
            Analysis.question_event(question.id, :cancel)
          catch
            :exit, reason -> {:crashed, reason}
          end

        assert result == {:error, "Could not persist Analysis question"}
      end)

    assert log =~ "persistence failed"

    assert_receive {:analysis_question, id, {:error, "Could not persist Analysis question"}},
                   1_000

    assert id == question.id
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 1_000
    assert Analysis.get_question(question.id).state == "failed"
  end

  test "boot recovery makes orphaned paid work retryable without replay", %{scope: scope} do
    {:ok, session} = Analysis.start_session(%{"log" => to_string(scope["log"])})

    for state <- [:thinking, :calling_tool, :writing, :cancelled, :limit_hit] do
      {:ok, :thinking, ctx, _} =
        Analysis.QuestionLifecycle.step(:draft, :ask_agent, Analysis.QuestionLifecycle.initial())

      ctx =
        if state in [:calling_tool, :cancelled, :limit_hit] do
          {:ok, :calling_tool, ctx, _} =
            Analysis.QuestionLifecycle.step(:thinking, :tool_requested, ctx)

          if state == :calling_tool do
            ctx
          else
            event = if state == :cancelled, do: :cancel, else: :timeout
            {:ok, ^state, ctx, _} = Analysis.QuestionLifecycle.step(:calling_tool, event, ctx)
            ctx
          end
        else
          ctx
        end

      question =
        Repo.insert!(%Analysis.Question{
          session_id: session.id,
          model: session.model,
          text: "Interrupted",
          state: to_string(state),
          lifecycle: ctx
        })

      if state in [:calling_tool, :cancelled, :limit_hit] do
        Repo.insert!(%Message{
          session_id: session.id,
          question_id: question.id,
          role: "assistant",
          content: [
            %{"type" => "tool_use", "id" => "interrupted", "name" => "list_pulls", "input" => %{}}
          ]
        })
      end

      :ok = QuestionRunner.recover_orphans()
      recovered = Analysis.get_question(question.id)

      assert recovered.state ==
               if(state in [:cancelled, :limit_hit], do: to_string(state), else: "failed")

      if recovered.state == "failed", do: assert(recovered.error =~ "interrupted")
      refute recovered.lifecycle["timer"]
      refute recovered.lifecycle["tool_in_flight"]
      assert recovered.lifecycle["recorded"] == recovered.lifecycle["tool_calls"]
      assert recovered.lifecycle["model_calls"] == ctx.model_calls
      assert Registry.lookup(Analysis.QuestionRegistry, question.id) == []

      if state in [:calling_tool, :cancelled, :limit_hit] do
        assert [%{"type" => "tool_result", "tool_use_id" => "interrupted", "is_error" => true}] =
                 Repo.one!(
                   from(m in Message, where: m.question_id == ^question.id and m.role == "user")
                 ).content
      end

      count = Repo.aggregate(from(m in Message, where: m.question_id == ^question.id), :count)
      :ok = QuestionRunner.recover_orphans()

      assert Repo.aggregate(from(m in Message, where: m.question_id == ^question.id), :count) ==
               count
    end
  end

  defp ask(scope, opts \\ []) do
    {:ok, question, pid} =
      Analysis.ask(
        scope,
        "Why did Sszorak pull 5 wipe?",
        Keyword.merge([subscribe: true, req_options: [plug: {Req.Test, __MODULE__}]], opts)
      )

    on_exit(fn ->
      DynamicSupervisor.terminate_child(Analysis.QuestionSupervisor, pid)
    end)

    {question, pid}
  end

  defp assert_mixed_night_export(session) do
    mcp =
      Repo.insert!(%Analysis.Session{
        started_at: DateTime.utc_now(),
        combat_log_file_id: session.combat_log_file_id
      })

    transcript = Path.join(System.tmp_dir!(), "mcp-#{mcp.id}.jsonl")
    output = Path.join(System.tmp_dir!(), "night-#{mcp.id}.jsonl")

    File.write!(
      transcript,
      Jason.encode!(%{
        "uuid" => "external",
        "message" => %{"role" => "user", "content" => "MCP question"}
      }) <> "\n"
    )

    on_exit(fn ->
      File.rm(transcript)
      File.rm(output)
    end)

    ExUnit.CaptureIO.capture_io(fn ->
      Mix.Tasks.Wgn.ExportAnalysis.run([
        "--night",
        Date.to_iso8601(Date.utc_today()),
        "--transcript",
        transcript,
        "--output",
        output
      ])
    end)

    records =
      output
      |> File.stream!()
      |> Enum.map(&Jason.decode!/1)
      |> Map.new(&{&1["session"]["id"], &1})

    assert records[session.id]["messages_scope"] == "analysis_session"
    assert length(records[session.id]["messages"]) == 4
    assert records[mcp.id]["messages_scope"] == "source_transcripts"
    assert [%{"uuid" => "external"}] = records[mcp.id]["messages"]
  end

  defp await_state(id, expected) do
    receive do
      {:analysis_question, ^id, {:state, ^expected}} -> :ok
      {:analysis_question, ^id, _} -> await_state(id, expected)
    after
      5_000 -> flunk("question did not reach #{expected}")
    end
  end

  defp respond(conn, blocks, stop_reason) do
    events =
      [
        %{
          "type" => "message_start",
          "message" => %{
            "role" => "assistant",
            "usage" => %{"input_tokens" => 12, "cache_read_input_tokens" => 200}
          }
        }
      ] ++
        Enum.flat_map(Enum.with_index(blocks), fn {block, index} ->
          [
            %{"type" => "content_block_start", "index" => index, "content_block" => block},
            %{"type" => "content_block_stop", "index" => index}
          ]
        end) ++
        [
          %{
            "type" => "message_delta",
            "delta" => %{"stop_reason" => stop_reason},
            "usage" => %{"output_tokens" => 10}
          },
          %{"type" => "message_stop"}
        ]

    stream = Enum.map_join(events, "", &("data: " <> Jason.encode!(&1) <> "\n\n"))

    conn
    |> Plug.Conn.put_resp_content_type("text/event-stream")
    |> Plug.Conn.send_resp(200, stream)
  end
end
