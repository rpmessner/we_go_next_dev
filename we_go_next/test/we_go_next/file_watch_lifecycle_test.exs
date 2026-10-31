defmodule WeGoNext.FileWatchLifecycleTest do
  use ExUnit.Case, async: true
  alias WeGoNext.FileWatchLifecycle, as: Machine

  test "every declared pair is total even before event data arrives" do
    for state <- Machine.states(), event <- Machine.events() do
      assert {:ok, _, _, _} = Machine.step(state, event, Machine.initial())
    end
  end

  test "idle and retry deadlines are guarded by the table" do
    ctx = %{Machine.initial() | candidate: %{id: 1}, now: 10, retry_at: 20}
    {:ok, :tracking, ctx, _} = Machine.step(:idle, :watch, ctx)
    assert {:ok, :backoff, ^ctx, []} = Machine.step(:backoff, :retry, ctx)
    assert {:ok, :tracking, _, []} = Machine.step(:backoff, :retry, %{ctx | now: 20})
    assert {:ok, :tracking, ^ctx, []} = Machine.step(:tracking, :expire, ctx)

    assert {:ok, :idle_off, %{enabled: false}, [:disable]} =
             Machine.step(:tracking, :expire, %{ctx | now: ctx.idle_ms})
  end

  test "model invariants hold after every random event prefix" do
    :rand.seed(:exsss, {18, 7, 2026})

    for _ <- 1..400 do
      Enum.reduce(1..200, {:idle, Machine.initial(), 0}, fn _, {phase, ctx, latest} ->
        event = Enum.random(Machine.events())
        candidate = %{id: latest + 1}
        result = %{file: %{id: latest + 1}}
        ctx = Map.merge(ctx, %{candidate: candidate, result: result, now: ctx.now + 60_000})
        previous = ctx.tracked
        {:ok, phase, ctx, effects} = Machine.step(phase, event, ctx)
        latest = if :select in effects or :complete in effects, do: ctx.tracked, else: latest
        assert ctx.enabled == not is_nil(ctx.tracked), "Agreement"
        assert is_nil(previous) or is_nil(ctx.tracked) or ctx.tracked >= previous, "NeverRevert"
        assert phase not in [:idle, :idle_off, :directory] or not ctx.enabled, "Restored"
        expired = event == :expire and ctx.now - ctx.last_write >= ctx.idle_ms
        assert not expired or not ctx.enabled, "AutoOff"
        assert ctx.failures in 0..8
        {phase, ctx, latest}
      end)
    end
  end

  test "late results are ignored after switching and stopping, even across a new sync" do
    ctx = Map.merge(Machine.initial(), %{candidate: %{id: 1}, result: %{file: %{id: 1}}})
    {:ok, :tracking, ctx, _} = Machine.step(:idle, :watch, ctx)
    {:ok, :syncing, ctx, _} = Machine.step(:tracking, :sync, ctx)
    old_generation = ctx.task_generation

    for event <- [:watch, :stop, :expire] do
      {:ok, phase, ctx, _} =
        Machine.step(:syncing, event, %{ctx | candidate: %{id: 2}, now: ctx.idle_ms})

      stale = %{ctx | task_generation: old_generation}
      assert {:ok, ^phase, ^stale, []} = Machine.step(phase, :success, stale)
      assert {:ok, ^phase, ^stale, []} = Machine.step(phase, :failure, stale)
      assert {:ok, ^phase, ^stale, []} = Machine.step(phase, :partial_failure, stale)
    end
  end

  test "generated matrix and chart match the table and all states are reachable" do
    root = Path.expand("../../../docs/state-machines/watch", __DIR__)
    assert File.read!(Path.join(root, "implementation-matrix.md")) == Machine.matrix()
    assert File.read!(Path.join(root, "implementation.mmd")) == Machine.diagram()

    reachable =
      Enum.reduce(1..8, MapSet.new([:idle]), fn _, known ->
        Enum.reduce(Machine.rows(), known, fn {from, _, _, to, _}, acc ->
          if MapSet.member?(known, from), do: MapSet.put(acc, to), else: acc
        end)
      end)

    assert reachable == MapSet.new(Machine.states())
    assert Machine.step(:idle, :unknown, Machine.initial()) == :invalid
  end
end
