defmodule WeGoNextWeb.PathState do
  @moduledoc "Settings path validation modes. Filesystem checks stay in the page adapter."
  use WeGoNext.StateTable
  @states [:empty, :valid, :invalid]
  @events [:empty, :valid, :invalid]
  @guards [:always]
  @effects []
  @rows for state <- @states, event <- @events, do: {state, event, :always, event, []}
  def step(state, event, ctx),
    do:
      WeGoNext.StateTable.step(@rows, state, event, ctx, fn :always, _ -> true end, fn _, ctx ->
        ctx
      end)
end
