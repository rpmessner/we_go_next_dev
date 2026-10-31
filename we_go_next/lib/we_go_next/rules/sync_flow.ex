defmodule WeGoNext.Rules.SyncFlow do
  @moduledoc "Pure staged sync. Completed stages are committed, not rolled back on a later failure."
  use WeGoNext.StateTable

  @states ~w(sync activate promote rebuild done failed)a
  @events [:succeeded, :failed]
  @guards [:always, :activate_requested, :promote_requested, :rebuild_requested]
  @effects [:synced, :activated, :promoted, :rebuilt, :record_failure, :reject]
  @transitions [
    {:sync, :succeeded, :activate_requested, :activate, [:synced]},
    {:sync, :succeeded, :promote_requested, :promote, [:synced]},
    {:sync, :succeeded, :always, :done, [:synced]},
    {:activate, :succeeded, :promote_requested, :promote, [:activated]},
    {:activate, :succeeded, :always, :done, [:activated]},
    {:promote, :succeeded, :rebuild_requested, :rebuild, [:promoted]},
    {:promote, :succeeded, :always, :done, [:promoted]},
    {:rebuild, :succeeded, :always, :done, [:rebuilt]}
  ]
  @rows @transitions ++
          Enum.map(~w(sync activate promote rebuild)a, fn state ->
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
      activate: rebuild or Keyword.get(opts, :activate, false),
      promote: rebuild or Keyword.get(opts, :promote, false),
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
  defp guard(:activate_requested, ctx), do: ctx.activate
  defp guard(:promote_requested, ctx), do: ctx.promote
  defp guard(:rebuild_requested, ctx), do: ctx.rebuild

  defp reduce(:synced, ctx), do: complete(ctx, :sync)
  defp reduce(:activated, ctx), do: complete(ctx, :activate)
  defp reduce(:promoted, ctx), do: complete(ctx, :promote)
  defp reduce(:rebuilt, ctx), do: complete(ctx, :rebuild)
  defp reduce(:record_failure, ctx), do: %{ctx | failed: true}
  defp reduce(:reject, ctx), do: ctx
  defp complete(ctx, stage), do: %{ctx | completed: ctx.completed ++ [stage]}
end
