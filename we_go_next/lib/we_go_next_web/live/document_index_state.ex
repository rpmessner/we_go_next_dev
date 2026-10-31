defmodule WeGoNextWeb.DocumentIndexState do
  @moduledoc "Encounter document index availability. Error details are data, not another mode."
  use WeGoNext.StateTable
  @states [:ready, :empty, :unavailable]
  @events [:ready, :empty, :unavailable]
  @guards [:always]
  @effects []
  @rows for state <- @states, event <- @events, do: {state, event, :always, event, []}
  def step(state, event, ctx),
    do:
      WeGoNext.StateTable.step(@rows, state, event, ctx, fn :always, _ -> true end, fn _, ctx ->
        ctx
      end)

  def project(previous, result) do
    {event, error} =
      case result do
        {:error, reason} -> {:unavailable, reason}
        state when state in [:ready, :empty] -> {state, nil}
      end

    {:ok, state, _, []} = step(previous, event, %{})
    %{state: state, error: error}
  end
end
