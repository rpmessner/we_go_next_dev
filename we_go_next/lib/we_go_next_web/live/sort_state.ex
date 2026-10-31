defmodule WeGoNextWeb.SortState do
  @moduledoc "Encounter list sort preference, including session restoration."
  use WeGoNext.StateTable
  @states [:asc, :desc]
  @events [:toggle, :restore_asc, :restore_desc]
  @guards [:always]
  @effects [:store]
  @rows [
    {:asc, :toggle, :always, :desc, [:store]},
    {:desc, :toggle, :always, :asc, [:store]},
    {:asc, :restore_asc, :always, :asc, []},
    {:desc, :restore_asc, :always, :asc, []},
    {:asc, :restore_desc, :always, :desc, []},
    {:desc, :restore_desc, :always, :desc, []}
  ]
  def step(state, event, ctx),
    do:
      WeGoNext.StateTable.step(@rows, state, event, ctx, fn :always, _ -> true end, fn _, ctx ->
        ctx
      end)
end
