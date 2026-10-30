defmodule WeGoNext.Analysis.QuestionLifecycleTest do
  use ExUnit.Case, async: true
  alias WeGoNext.Analysis.QuestionLifecycle, as: Machine

  test "AskAgent arms the question timer" do
    assert {:ok, :thinking, %{timer: true}, [:arm_timer, :request_model]} =
             Machine.step(:draft, :ask_agent, Machine.initial())
  end

  test "the five TLA rules hold after every prefix of random event sequences" do
    :rand.seed(:exsss, {731, 192, 519})

    for kind <- [:builtin, :agent], _sequence <- 1..400 do
      Enum.reduce(1..300, {:draft, Machine.initial(kind: kind, cap: 3, raised_cap: 6)}, fn _,
                                                                                           {state,
                                                                                            ctx} ->
        event = Enum.at(Machine.events(), :rand.uniform(length(Machine.events())) - 1)
        {:ok, state, ctx, _} = Machine.step(state, event, ctx)
        assert kind != :builtin or ctx.model_calls == 0, "BuiltinNeverCallsModel"
        assert ctx.turns <= ctx.cap, "StaysWithinBudget"
        assert state not in [:thinking, :calling_tool, :writing] or ctx.timer, "RunningHasTimer"
        assert ctx.tool_in_flight or ctx.recorded == ctx.tool_calls, "EveryToolCallRecorded"
        assert ctx.tool_calls - ctx.recorded == if(ctx.tool_in_flight, do: 1, else: 0)
        assert not ctx.verdict or state == :judged, "VerdictOnlyOnAnswers"
        {state, ctx}
      end)
    end
  end

  test "late Tool returns are recorded after timeout and Continue waits for them" do
    {state, ctx} = run([:ask_agent, :tool_requested, :timeout, :continue])
    assert state == :limit_hit
    refute ctx.raised
    assert ctx.tool_in_flight
    {:ok, :limit_hit, ctx, [:record_tool]} = Machine.step(state, :tool_returned, ctx)
    assert ctx.recorded == 1

    assert {:ok, :thinking, %{raised: true, timer: true}, _} =
             Machine.step(:limit_hit, :continue, ctx)

    for stop <- [:cancel, :timeout] do
      {state, ctx} = run([:ask_agent, :tool_requested, stop, :tool_returned])
      assert state in [:cancelled, :limit_hit]
      assert ctx.recorded == 1
    end
  end

  test "the answer gets the last turn and timeout stops writing; Retry re-arms" do
    {state, ctx} = run([:ask_agent, :tool_requested, :tool_returned])
    assert {:ok, ^state, ^ctx, []} = Machine.step(state, :tool_requested, ctx)
    {:ok, :writing, ctx, _} = Machine.step(state, :answer_started, ctx)
    assert ctx.turns == 2
    assert {:ok, :limit_hit, %{timer: false}, _} = Machine.step(:writing, :timeout, ctx)
    {state, ctx} = run([:ask_agent, :api_error, :timeout, :retry])
    assert state == :thinking
    assert ctx.timer
  end

  test "table artifacts match, every state is reachable, unknown events are invalid" do
    root = Path.expand("../../../../docs/ai-analysis/statecharts/question-lifecycle", __DIR__)
    assert File.read!(Path.join(root, "implementation-matrix.md")) == Machine.matrix()
    assert File.read!(Path.join(root, "implementation.mmd")) == Machine.diagram()

    reachable =
      Enum.reduce(1..10, MapSet.new([:draft]), fn _, known ->
        Enum.reduce(Machine.rows(), known, fn {from, _, _, to, _}, acc ->
          if MapSet.member?(known, from), do: MapSet.put(acc, to), else: acc
        end)
      end)

    assert reachable == MapSet.new(Machine.states())
    assert Machine.step(:draft, :unknown, Machine.initial()) == :invalid
  end

  test "validator rejects a missing pair and unknown effect at compilation" do
    assert_raise ArgumentError, ~r/Unhandled/, fn ->
      Code.compile_string("""
      defmodule MissingPair do
        use WeGoNext.StateTable
        @states [:draft]
        @events [:ask]
        @guards [:always]
        @effects []
        @rows []
      end
      """)
    end

    assert_raise ArgumentError, ~r/Unknown/, fn ->
      WeGoNext.StateTable.validate!([:draft], [:ask], [:always], [], [
        {:draft, :ask, :always, :draft, [:typo]}
      ])
    end
  end

  defp run(events) do
    Enum.reduce(events, {:draft, Machine.initial(cap: 2, raised_cap: 4)}, fn event,
                                                                             {state, ctx} ->
      {:ok, state, ctx, _} = Machine.step(state, event, ctx)
      {state, ctx}
    end)
  end
end
