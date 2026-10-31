defmodule WeGoNextWeb.LoadState do
  @moduledoc "Loading an imported log for display is separate from ingest. Late replies cannot reopen a completed load."
  use WeGoNext.StateTable
  @states [:idle, :loading, :failed]
  @events [:load, :loaded, :failed]
  @guards [:always]
  @effects [:clear_error, :set_error, :load]
  @rows [
    {:idle, :load, :always, :loading, [:clear_error, :load]},
    {:loading, :load, :always, :loading, [:clear_error, :load]},
    {:failed, :load, :always, :loading, [:clear_error, :load]},
    {:idle, :loaded, :always, :idle, []},
    {:loading, :loaded, :always, :idle, [:clear_error]},
    {:failed, :loaded, :always, :failed, []},
    {:idle, :failed, :always, :idle, []},
    {:loading, :failed, :always, :failed, [:set_error]},
    {:failed, :failed, :always, :failed, []}
  ]
  def initial, do: %{state: :idle, error: nil}

  def step(state, event, ctx),
    do: WeGoNext.StateTable.step(@rows, state, event, ctx, fn :always, _ -> true end, &reduce/2)

  defp reduce(:clear_error, ctx), do: %{ctx | error: nil}
  defp reduce(:set_error, ctx), do: %{ctx | error: "Failed to load: #{inspect(ctx.reason)}"}
  defp reduce(:load, ctx), do: ctx
end
