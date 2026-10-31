defmodule WeGoNext.FileIngest.Lifecycle do
  @moduledoc "Pure per-file lifecycle; IO belongs to FileIngest. See FileIngest.tla."
  use WeGoNext.StateTable

  @states ~w(idle importing syncing reimporting failed)a
  @events ~w(import sync reimport advance medallion_failed medallion_complete complete error timeout)a
  @guards [:always, :ready]
  @effects ~w(claim release fail advance mark_failed mark_complete)a
  @busy ~w(importing syncing reimporting)a
  @starts (for from <- [:idle, :failed],
               {event, to} <-
                 [import: :importing, sync: :syncing, reimport: :reimporting] do
             {from, event, :always, to, [:claim]}
           end)
  @work (for from <- @busy do
           [
             {from, :advance, :always, from, [:advance]},
             {from, :medallion_failed, :always, from, [:mark_failed]},
             {from, :medallion_complete, :always, from, [:mark_complete]},
             {from, :complete, :ready, :idle, [:release]},
             {from, :complete, :always, :failed, [:fail]},
             {from, :error, :always, :failed, [:fail]},
             {from, :timeout, :always, :failed, [:fail]}
           ]
         end)
        |> List.flatten()
  @handled @starts ++ @work
  @rows @handled ++
          (for state <- @states,
               event <- @events,
               not Enum.any?(@handled, fn {s, e, _, _, _} -> s == state and e == event end) do
             {state, event, :always, state, []}
           end)

  def initial, do: %{writers: 0, offset: 0, candidate: 0, pending: true, failed_pull: false}

  def step(state, event, ctx),
    do: WeGoNext.StateTable.step(@rows, state, event, ctx, &guard/2, &reduce/2)

  defp guard(:always, _ctx), do: true
  defp guard(:ready, ctx), do: not ctx.pending
  defp reduce(:claim, ctx), do: %{ctx | writers: 1}
  defp reduce(:release, ctx), do: %{ctx | writers: 0}
  defp reduce(:fail, ctx), do: %{ctx | writers: 0}
  defp reduce(:advance, ctx), do: %{ctx | offset: max(ctx.offset, ctx.candidate)}
  defp reduce(:mark_failed, ctx), do: %{ctx | pending: true, failed_pull: true}
  defp reduce(:mark_complete, ctx), do: %{ctx | pending: false, failed_pull: false}
end
