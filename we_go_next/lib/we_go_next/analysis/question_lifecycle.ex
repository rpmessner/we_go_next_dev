defmodule WeGoNext.Analysis.QuestionLifecycle do
  @moduledoc "Pure, total question lifecycle. Action names correspond to QuestionLifecycle.tla."
  use WeGoNext.StateTable

  @states ~w(draft computing thinking calling_tool writing answered judged limit_hit failed cancelled)a
  @events ~w(ask_builtin computed ask_agent tool_requested over_limit tool_returned answer_started answer_done timeout api_error retry cancel continue record_verdict done)a
  @guards ~w(always builtin agent tool_budget exhausted answer_budget in_flight timer can_continue)a
  @effects ~w(arm_timer request_model compute charge start_tool record_tool stop_timer stop_model raise_cap verdict finish_answer)a
  @running ~w(thinking calling_tool writing)a

  @transitions [
    {:draft, :ask_builtin, :builtin, :computing, [:compute]},
    {:draft, :ask_agent, :agent, :thinking, [:arm_timer, :request_model]},
    {:computing, :computed, :always, :answered, [:finish_answer]},
    {:thinking, :tool_requested, :tool_budget, :calling_tool, [:charge, :start_tool]},
    {:thinking, :over_limit, :exhausted, :limit_hit, [:stop_model]},
    {:thinking, :answer_started, :answer_budget, :writing, [:charge]},
    {:writing, :answer_done, :always, :answered, [:stop_timer, :finish_answer]},
    {:thinking, :api_error, :always, :failed, [:stop_model]},
    {:writing, :api_error, :always, :failed, [:stop_model]},
    {:failed, :retry, :always, :thinking, [:arm_timer, :request_model]},
    {:thinking, :cancel, :always, :cancelled, [:stop_model]},
    {:calling_tool, :cancel, :always, :cancelled, [:stop_model]},
    {:writing, :cancel, :always, :cancelled, [:stop_model]},
    {:limit_hit, :continue, :can_continue, :thinking, [:raise_cap, :arm_timer, :request_model]},
    {:answered, :record_verdict, :always, :judged, [:verdict]},
    {:judged, :record_verdict, :always, :judged, [:verdict]}
  ]

  # Explicit ignored pairs. Guarded transitions have a final ignore row as well.
  # The validator requires every pair, so deleting a row is a compile-time error.
  @ignored %{
    draft:
      ~w(ask_builtin computed ask_agent tool_requested over_limit answer_started answer_done api_error retry cancel continue record_verdict done)a,
    computing:
      ~w(ask_builtin ask_agent tool_requested over_limit answer_started answer_done api_error retry cancel continue record_verdict done)a,
    thinking:
      ~w(ask_builtin computed ask_agent tool_requested over_limit answer_started answer_done retry continue record_verdict done)a,
    calling_tool:
      ~w(ask_builtin computed ask_agent tool_requested over_limit answer_started answer_done api_error retry continue record_verdict done)a,
    writing:
      ~w(ask_builtin computed ask_agent tool_requested over_limit answer_started retry continue record_verdict done)a,
    answered:
      ~w(ask_builtin computed ask_agent tool_requested over_limit answer_started answer_done api_error retry cancel continue done)a,
    judged:
      ~w(ask_builtin computed ask_agent tool_requested over_limit answer_started answer_done api_error retry cancel continue done)a,
    limit_hit:
      ~w(ask_builtin computed ask_agent tool_requested over_limit answer_started answer_done api_error retry cancel continue record_verdict done)a,
    failed:
      ~w(ask_builtin computed ask_agent tool_requested over_limit answer_started answer_done api_error cancel continue record_verdict done)a,
    cancelled:
      ~w(ask_builtin computed ask_agent tool_requested over_limit answer_started answer_done api_error retry cancel continue record_verdict done)a
  }

  @rows @transitions ++
          Enum.flat_map(@states, fn state ->
            returned_to = if state == :calling_tool, do: :thinking, else: state

            returned_effects =
              if state == :calling_tool, do: [:record_tool, :request_model], else: [:record_tool]

            timed_out = if state in @running, do: :limit_hit, else: state

            [
              {state, :tool_returned, :in_flight, returned_to, returned_effects},
              {state, :tool_returned, :always, state, []},
              {state, :timeout, :timer, timed_out, [:stop_timer, :stop_model]},
              {state, :timeout, :always, state, []}
            ] ++ Enum.map(Map.fetch!(@ignored, state), &{state, &1, :always, state, []})
          end)

  def initial(opts \\ []) do
    %{
      kind: Keyword.get(opts, :kind, :agent),
      turns: 0,
      cap: Keyword.get(opts, :cap, 40),
      raised_cap: Keyword.get(opts, :raised_cap, 80),
      raised: false,
      tool_in_flight: false,
      tool_calls: 0,
      recorded: 0,
      timer: false,
      model_calls: 0,
      verdict: false
    }
  end

  def step(state, event, ctx),
    do: WeGoNext.StateTable.step(@rows, state, event, ctx, &guard/2, &reduce/2)

  defp guard(:always, _), do: true
  defp guard(:builtin, ctx), do: ctx.kind == :builtin
  defp guard(:agent, ctx), do: ctx.kind == :agent
  defp guard(:tool_budget, ctx), do: ctx.turns + 1 < ctx.cap
  defp guard(:exhausted, ctx), do: ctx.turns >= ctx.cap
  defp guard(:answer_budget, ctx), do: ctx.turns < ctx.cap
  defp guard(:in_flight, ctx), do: ctx.tool_in_flight
  defp guard(:timer, ctx), do: ctx.timer
  defp guard(:can_continue, ctx), do: not ctx.raised and not ctx.tool_in_flight

  defp reduce(:arm_timer, ctx), do: %{ctx | timer: true}
  defp reduce(:stop_timer, ctx), do: %{ctx | timer: false}
  defp reduce(:charge, ctx), do: %{ctx | turns: ctx.turns + 1, model_calls: ctx.model_calls + 1}
  defp reduce(:start_tool, ctx), do: %{ctx | tool_in_flight: true, tool_calls: ctx.tool_calls + 1}
  defp reduce(:record_tool, ctx), do: %{ctx | tool_in_flight: false, recorded: ctx.recorded + 1}
  defp reduce(:raise_cap, ctx), do: %{ctx | raised: true, cap: ctx.raised_cap}
  defp reduce(:verdict, ctx), do: %{ctx | verdict: true}
  defp reduce(_, ctx), do: ctx
end
