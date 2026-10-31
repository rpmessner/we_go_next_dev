defmodule WeGoNext.Rules.StateMachinesTest do
  use ExUnit.Case, async: true

  alias WeGoNext.Rules.{RulesetLifecycle, SyncFlow}

  test "lifecycle TLA rules hold across random two-ruleset event sequences" do
    :rand.seed(:exsss, {127, 193, 719})

    for first <- RulesetLifecycle.states(),
        second <- RulesetLifecycle.states(),
        [first, second] != [:active, :active] do
      Enum.reduce(1..500, {[first, second], :active in [first, second]}, fn _, {states, ever} ->
        index = :rand.uniform(2) - 1
        event = Enum.random([:sync, :activate, :archive, :reset])
        current = Enum.at(states, index)
        transition = RulesetLifecycle.step(current, event)
        assert event != :sync or match?({:ok, ^current, _, []}, transition), "SyncNeverDemotes"

        assert current not in [:archived, :active] or event != :reset or transition == :invalid,
               "NoResetToDraft"

        assert current != :active or event != :archive or transition == :invalid

        updated = apply_transition(states, index, transition)
        assert Enum.count(updated, &(&1 == :active)) <= 1, "AtMostOneActive"
        assert not ever or :active in updated, "NeverLoseActive"
        {updated, ever or :active in updated}
      end)
    end
  end

  test "flow TLA rules hold for every option combination and random outcome prefixes" do
    :rand.seed(:exsss, {813, 217, 321})

    for activate <- [false, true],
        promote <- [false, true],
        rebuild <- [false, true],
        _sequence <- 1..100 do
      opts = [activate: activate, promote: promote, rebuild: rebuild]

      expected =
        [:sync] ++
          if(activate or rebuild, do: [:activate], else: []) ++
          if(promote or rebuild, do: [:promote], else: []) ++
          if(rebuild, do: [:rebuild], else: [])

      Enum.reduce(1..20, {:sync, SyncFlow.initial(opts)}, fn _, {state, ctx} ->
        event = Enum.random([:succeeded, :succeeded, :failed, :unknown])

        {next, updated} =
          case SyncFlow.step(state, event, ctx) do
            :invalid -> {state, ctx}
            {:ok, next, updated, _} -> {next, updated}
          end

        assert updated.completed == Enum.take(expected, length(updated.completed)),
               "CompletedPrefix"

        assert updated.failed == (next == :failed), "FailureIsExplicit"

        assert next != :rebuild or
                 (:activate in updated.completed and :promote in updated.completed),
               "RebuildAfterPromotion"

        assert next != :done or updated.completed == expected
        {next, updated}
      end)
    end
  end

  test "successful rebuild runs exactly sync, activate, promote, rebuild" do
    {state, ctx} =
      Enum.reduce(1..4, {:sync, SyncFlow.initial(rebuild: true)}, fn _, {state, ctx} ->
        {:ok, next, ctx, _} = SyncFlow.step(state, :succeeded, ctx)
        {next, ctx}
      end)

    assert state == :done
    assert ctx.completed == [:sync, :activate, :promote, :rebuild]
  end

  test "table artifacts match and unknown states or events are rejected" do
    for {machine, directory} <- [
          {RulesetLifecycle, "ruleset-lifecycle"},
          {SyncFlow, "ruleset-flow"}
        ] do
      root = Path.expand("../../../../docs/state-machines/#{directory}", __DIR__)
      assert File.read!(Path.join(root, "implementation-matrix.md")) == machine.matrix()
      assert File.read!(Path.join(root, "implementation.mmd")) == machine.diagram()
      assert machine.step(:unknown, :unknown, %{}) == :invalid

      initial = if machine == RulesetLifecycle, do: :draft, else: :sync

      reachable =
        Enum.reduce(1..length(machine.states()), MapSet.new([initial]), fn _, known ->
          Enum.reduce(machine.rows(), known, fn {from, _, _, to, _}, reached ->
            if MapSet.member?(known, from), do: MapSet.put(reached, to), else: reached
          end)
        end)

      assert reachable == MapSet.new(machine.states())
    end
  end

  defp apply_transition(states, _index, :invalid), do: states

  defp apply_transition(states, index, {:ok, next, _, effects}) do
    states =
      if :activate in effects do
        Enum.map(states, fn
          :active ->
            {:ok, :archived, _, [:archive]} =
              RulesetLifecycle.step(:active, :replace, %{replacement: true})

            :archived

          other ->
            other
        end)
      else
        states
      end

    List.replace_at(states, index, next)
  end
end
