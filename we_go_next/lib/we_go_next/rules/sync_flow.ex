defmodule WeGoNext.Rules.SyncFlow do
  @moduledoc "Pure staged sync. Completed stages are committed, not rolled back on a later failure."
  use WeGoNext.StateTable

  @states ~w(sync rebuild done failed)a
  @events [:succeeded, :failed]
  @guards [:always, :rebuild_requested]
  @effects [:synced, :rebuilt, :record_failure, :reject]
  @transitions [
    {:sync, :succeeded, :rebuild_requested, :rebuild, [:synced]},
    {:sync, :succeeded, :always, :done, [:synced]},
    {:rebuild, :succeeded, :always, :done, [:rebuilt]}
  ]
  @rows @transitions ++
          Enum.map(~w(sync rebuild)a, fn state ->
            {state, :failed, :always, :failed, [:record_failure]}
          end) ++
          for(
            state <- [:done, :failed],
            event <- @events,
            do: {state, event, :always, state, [:reject]}
          )

  def initial(opts \\ []) do
    rebuild = Keyword.get(opts, :rebuild, false)

    %{
      rebuild: rebuild,
      completed: [],
      failed: false
    }
  end

  def step(state, event, ctx) do
    case WeGoNext.StateTable.step(@rows, state, event, ctx, &guard/2, &reduce/2) do
      {:ok, _, _, [:reject]} -> :invalid
      result -> result
    end
  end

  defp guard(:always, _ctx), do: true
  defp guard(:rebuild_requested, ctx), do: ctx.rebuild

  defp reduce(:synced, ctx), do: complete(ctx, :sync)
  defp reduce(:rebuilt, ctx), do: complete(ctx, :rebuild)
  defp reduce(:record_failure, ctx), do: %{ctx | failed: true}
  defp reduce(:reject, ctx), do: ctx
  defp complete(ctx, stage), do: %{ctx | completed: ctx.completed ++ [stage]}
end
