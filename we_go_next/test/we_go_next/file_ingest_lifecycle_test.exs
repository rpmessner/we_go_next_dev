defmodule WeGoNext.FileIngestLifecycleTest do
  use ExUnit.Case, async: true
  alias WeGoNext.FileIngest.Lifecycle

  test "a failed pull cannot be silently marked complete" do
    {:ok, state, ctx, _} = Lifecycle.step(:idle, :import, Lifecycle.initial())
    {:ok, state, ctx, _} = Lifecycle.step(state, :medallion_failed, ctx)
    assert {:ok, :failed, %{pending: true}, _} = Lifecycle.step(state, :complete, ctx)
  end

  test "one writer, monotonic progress, and no skipped failed pull for arbitrary events" do
    :rand.seed(:exsss, {130, 231, 901})

    for _ <- 1..400 do
      Enum.reduce(1..100, {:idle, Lifecycle.initial()}, fn _, {state, ctx} ->
        event = Enum.random(Lifecycle.events())
        candidate = :rand.uniform(1000)
        previous = ctx.offset
        {:ok, next, ctx, _} = Lifecycle.step(state, event, Map.put(ctx, :candidate, candidate))
        assert ctx.offset >= previous
        assert ctx.writers in [0, 1]
        assert next in [:importing, :syncing, :reimporting] == (ctx.writers == 1)
        if next == :idle, do: refute(ctx.failed_pull)

        if event == :timeout and state in [:importing, :syncing, :reimporting],
          do: assert(next == :failed)

        {next, ctx}
      end)
    end
  end

  test "golden table and diagram match the executable lifecycle" do
    root = "../docs/state-machines/file-ingest"
    assert File.read!(Path.join(root, "implementation-matrix.md")) == Lifecycle.matrix()
    assert File.read!(Path.join(root, "implementation.mmd")) == Lifecycle.diagram()
  end
end
