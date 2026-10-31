defmodule WeGoNextWeb.LogSelectionState do
  @moduledoc "Encounter list selection modes. Import/reimport affordances derive from one selection."
  use WeGoNext.StateTable
  @states [:all, :available, :imported]
  @events [:all, :available, :imported]
  @guards [:always]
  @effects []
  @rows for state <- @states, event <- @events, do: {state, event, :always, event, []}
  def step(state, event, ctx),
    do:
      WeGoNext.StateTable.step(@rows, state, event, ctx, fn :always, _ -> true end, fn _, ctx ->
        ctx
      end)

  def select(state, path, logs) do
    event =
      cond do
        path in [nil, "all"] -> :all
        Enum.any?(logs, &(&1.file_path == path)) -> :imported
        true -> :available
      end

    {:ok, next, _, []} = step(state, event, %{})
    next
  end
end
