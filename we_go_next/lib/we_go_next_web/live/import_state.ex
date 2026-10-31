defmodule WeGoNextWeb.ImportState do
  @moduledoc "Pure page projection of the durable ingest receipt. Progress cannot revive a terminal import."
  use WeGoNext.StateTable
  @states [:idle, :importing, :failed, :timed_out]
  @events [:idle, :importing, :failed, :timed_out, :progress]
  @guards [:always]
  @effects [:snapshot, :progress]
  @rows (for state <- @states, event <- @events do
           case {state, event} do
             {:importing, :progress} -> {state, event, :always, state, [:progress]}
             {_, :progress} -> {state, event, :always, state, []}
             _ -> {state, event, :always, event, [:snapshot]}
           end
         end)

  def initial,
    do: %{state: :idle, token: nil, path: nil, percent: 0, encounters_found: 0, error: nil}

  def step(state, event, ctx),
    do: WeGoNext.StateTable.step(@rows, state, event, ctx, &guard/2, &reduce/2)

  def project(previous, receipt, now) do
    {event, error} = classify(receipt, now)
    token = if receipt, do: receipt.token
    previous = if previous.token == token, do: previous, else: initial()
    snapshot = %{previous | token: token, path: if(receipt, do: receipt.path), error: error}
    {:ok, state, ctx, _} = step(previous.state, event, %{view: previous, snapshot: snapshot})
    %{ctx.view | state: state}
  end

  def progress(view, payload) do
    {:ok, _, ctx, _} = step(view.state, :progress, %{view: view, payload: payload})
    ctx.view
  end

  defp classify(nil, _), do: {:idle, nil}
  defp classify(%{status: "complete"}, _), do: {:idle, nil}

  defp classify(%{status: "failed", error: ":ingest_timeout"}, _),
    do: {:timed_out, "Import timed out. Try importing the log again."}

  defp classify(%{status: "failed", error: error}, _),
    do: {:failed, "Failed to import log: #{error}"}

  defp classify(%{status: "importing", deadline: deadline}, now) do
    if DateTime.compare(now, deadline) == :lt,
      do: {:importing, nil},
      else: {:timed_out, "Import timed out. Try importing the log again."}
  end

  defp guard(:always, _), do: true
  defp reduce(:snapshot, ctx), do: %{ctx | view: ctx.snapshot}

  defp reduce(:progress, %{payload: payload} = ctx) do
    percent =
      if payload.total_bytes > 0,
        do: round(payload.bytes_read / payload.total_bytes * 100),
        else: 0

    %{
      ctx
      | view: %{
          ctx.view
          | percent: min(max(percent, 0), 100),
            encounters_found: payload.encounters_found
        }
    }
  end
end
