defmodule WeGoNext.FileWatchLifecycle do
  @moduledoc "Pure watch transitions; the FileWatcher adapter owns persistence, tasks and timeouts."
  use WeGoNext.StateTable

  @states ~w(idle directory tracking syncing rotating backoff idle_off)a
  @events ~w(watch directory stop sync rotate success failure partial_failure retry expire poll)a
  @guards ~w(always current current_result candidate retry_file retry_directory expired)a
  @effects ~w(select directory disable sync rotate complete fail reset inspect)a

  @transitions [
    {:tracking, :poll, :always, :tracking, [:inspect]},
    {:directory, :poll, :always, :directory, [:inspect]},
    {:idle, :directory, :always, :directory, [:directory]},
    {:idle_off, :directory, :always, :directory, [:directory]},
    {:directory, :rotate, :always, :rotating, [:rotate]},
    {:tracking, :sync, :always, :syncing, [:sync]},
    {:tracking, :rotate, :always, :rotating, [:rotate]},
    {:syncing, :success, :current_result, :tracking, [:complete, :reset]},
    {:rotating, :success, :current_result, :tracking, [:complete, :reset]},
    {:syncing, :partial_failure, :current_result, :backoff, [:complete, :fail]},
    {:rotating, :partial_failure, :current_result, :backoff, [:complete, :fail]},
    {:syncing, :failure, :current, :backoff, [:fail]},
    {:rotating, :failure, :current, :backoff, [:fail]},
    {:backoff, :retry, :retry_file, :tracking, []},
    {:backoff, :retry, :retry_directory, :directory, []}
  ]
  @rows @transitions ++
          Enum.flat_map(@states, fn state ->
            [
              {state, :watch, :candidate, :tracking, [:select, :reset]},
              {state, :watch, :always, state, []},
              {state, :stop, :always, :idle_off, [:disable]},
              {state, :expire, :expired, :idle_off, [:disable]},
              {state, :expire, :always, state, []}
            ] ++
              for event <- @events,
                  event not in [:watch, :stop, :expire],
                  not Enum.any?(@transitions, fn {s, e, g, _, _} ->
                    s == state and e == event and g == :always
                  end) do
                {state, event, :always, state, []}
              end
          end)

  def initial do
    %{
      tracked: nil,
      enabled: false,
      generation: 0,
      task_generation: nil,
      failures: 0,
      candidate: nil,
      result: nil,
      now: 0,
      last_write: 0,
      idle_ms: 1_800_000,
      retry_at: nil
    }
  end

  def step(state, event, ctx),
    do: WeGoNext.StateTable.step(@rows, state, event, ctx, &guard/2, &reduce/2)

  defp guard(:always, _ctx), do: true

  defp guard(:current, ctx),
    do: not is_nil(ctx.task_generation) and ctx.task_generation == ctx.generation

  defp guard(:retry_file, ctx), do: not is_nil(ctx.tracked) and retry_ready?(ctx)
  defp guard(:retry_directory, ctx), do: is_nil(ctx.tracked) and retry_ready?(ctx)
  defp guard(:expired, ctx), do: ctx.now - ctx.last_write >= ctx.idle_ms
  defp guard(:candidate, ctx), do: match?(%{id: id} when not is_nil(id), ctx.candidate)

  defp guard(:current_result, ctx),
    do: guard(:current, ctx) and match?(%{file: %{id: id}} when not is_nil(id), ctx.result)

  defp retry_ready?(ctx), do: is_nil(ctx.retry_at) or ctx.now >= ctx.retry_at

  defp reduce(:select, ctx),
    do: %{ctx | tracked: ctx.candidate.id, enabled: true, generation: ctx.generation + 1}

  defp reduce(:disable, ctx),
    do: %{ctx | tracked: nil, enabled: false, generation: ctx.generation + 1}

  defp reduce(:directory, ctx), do: %{ctx | generation: ctx.generation + 1}

  defp reduce(effect, ctx) when effect in [:sync, :rotate],
    do: %{ctx | task_generation: ctx.generation}

  defp reduce(:reset, ctx), do: %{ctx | failures: 0}
  defp reduce(:fail, ctx), do: %{ctx | failures: min(ctx.failures + 1, 8)}
  defp reduce(:complete, ctx), do: %{ctx | tracked: ctx.result.file.id, enabled: true}
  defp reduce(_, ctx), do: ctx
end
