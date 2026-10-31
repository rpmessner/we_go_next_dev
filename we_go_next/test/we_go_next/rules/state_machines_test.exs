defmodule WeGoNext.Rules.StateMachinesTest do
  use ExUnit.Case, async: true
  alias WeGoNext.Rules.SyncFlow

  test "TLC invariants hold for every outcome prefix and rebuild option" do
    for rebuild <- [false, true], events <- outcomes(5) do
      expected = if rebuild, do: [:sync, :rebuild], else: [:sync]

      Enum.reduce(events, {:sync, SyncFlow.initial(rebuild: rebuild)}, fn event, {state, ctx} ->
        {next, updated} =
          case SyncFlow.step(state, event, ctx) do
            :invalid -> {state, ctx}
            {:ok, next, updated, _} -> {next, updated}
          end

        assert updated.completed == Enum.take(expected, length(updated.completed)),
               "CompletedPrefix"

        assert updated.failed == (next == :failed), "FailureIsExplicit"
        assert next != :rebuild or updated.completed == [:sync], "RebuildAfterSync"
        assert next != :done or updated.completed == expected, "DoneMeansRequestedWorkComplete"

        assert state not in [:failed, :done] or {state, ctx} == {next, updated},
               "TerminalIsStable"

        {next, updated}
      end)
    end
  end

  test "rebuild is exactly sync then rebuild" do
    {:ok, :rebuild, ctx, [:synced]} =
      SyncFlow.step(:sync, :succeeded, SyncFlow.initial(rebuild: true))

    assert {:ok, :done, %{completed: [:sync, :rebuild]}, [:rebuilt]} =
             SyncFlow.step(:rebuild, :succeeded, ctx)
  end

  test "table artifacts match, states are reachable, unknown inputs rejected" do
    root = Path.expand("../../../../docs/state-machines/ruleset-flow", __DIR__)
    assert File.read!(Path.join(root, "implementation-matrix.md")) == SyncFlow.matrix()
    assert File.read!(Path.join(root, "implementation.mmd")) == SyncFlow.diagram()
    assert SyncFlow.step(:unknown, :unknown, %{}) == :invalid

    reachable =
      Enum.reduce(1..4, MapSet.new([:sync]), fn _, known ->
        Enum.reduce(SyncFlow.rows(), known, fn {from, _, _, to, _}, reached ->
          if MapSet.member?(known, from), do: MapSet.put(reached, to), else: reached
        end)
      end)

    assert reachable == MapSet.new(SyncFlow.states())
  end

  defp outcomes(0), do: [[]]

  defp outcomes(n),
    do: for(event <- [:succeeded, :failed, :unknown], tail <- outcomes(n - 1), do: [event | tail])
end
