defmodule WeGoNext.Analysis.QuestionRunner do
  @moduledoc "Supervised per-question effect adapter. IO runs here, never in the lifecycle table."
  @behaviour :gen_statem
  import Ecto.Query
  alias WeGoNext.Analysis
  alias WeGoNext.Analysis.{Anthropic, Message, QuestionLifecycle, Startup}
  alias WeGoNext.Repo

  def child_spec(args),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [args]}, restart: :temporary}

  def start_link({question, session, opts}) do
    name = {:via, Registry, {Analysis.QuestionRegistry, question.id}}
    :gen_statem.start_link(name, __MODULE__, {question, session, opts}, [])
  end

  def event(id, event), do: :gen_statem.call(via(id), {:event, event})
  def snapshot(id), do: :gen_statem.call(via(id), :snapshot)
  defp via(id), do: {:via, Registry, {Analysis.QuestionRegistry, id}}
  def topic(id), do: "analysis_question:#{id}"
  def subscribe(id), do: Phoenix.PubSub.subscribe(WeGoNext.PubSub, topic(id))

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init({question, session, opts}) do
    data = %{
      question: question,
      session: session,
      ctx: QuestionLifecycle.initial(opts),
      opts: opts,
      task: nil,
      pending: nil,
      stream_token: nil,
      answer: nil,
      error: nil,
      system:
        Startup.instructions(session) <>
          "\nThis in-app Analysis session is already started. Do not call start_session. " <>
          "Begin with session_context using the Analysis session id above.\n"
    }

    append(data, "user", [
      %{"type" => "text", "text" => question.text <> "\nScope: " <> Jason.encode!(question.scope)}
    ])

    event = if data.ctx.kind == :builtin, do: :ask_builtin, else: :ask_agent
    {:ok, :draft, data, [{:next_event, :internal, event}]}
  end

  @impl true
  def handle_event({:call, from}, :snapshot, state, data),
    do: {:keep_state_and_data, [{:reply, from, {state, data.question}}]}

  def handle_event({:call, from}, {:event, event}, state, data)
      when event in [:cancel, :continue, :retry, :record_verdict] do
    {next, data, actions} = transition(state, event, data)
    {:next_state, next, data, [{:reply, from, :ok} | actions]}
  end

  def handle_event({:call, from}, _, _, _),
    do: {:keep_state_and_data, [{:reply, from, {:error, :invalid_event}}]}

  def handle_event(:internal, event, state, data) do
    {next, data, actions} = transition(state, event, data)
    {:next_state, next, data, actions}
  end

  def handle_event({:timeout, :question}, :expired, state, data) do
    {next, data, actions} = transition(state, :timeout, data)
    {:next_state, next, data, actions}
  end

  def handle_event(
        :info,
        {:stream, token, delta},
        _state,
        %{stream_token: token, pending: :model} = data
      ) do
    broadcast(data, delta)
    :keep_state_and_data
  end

  def handle_event(:info, {ref, result}, state, %{task: %{ref: ref}, pending: pending} = data) do
    Process.demonitor(ref, [:flush])
    complete(pending, result, state, %{data | task: nil})
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _, _},
        state,
        %{task: %{ref: ref}, pending: pending} = data
      ) do
    complete(pending, {:error, "Analysis worker failed"}, state, %{data | task: nil})
  end

  def handle_event(:info, _, _, _), do: :keep_state_and_data

  defp complete(:model, {:ok, response}, state, data) do
    append(data, "assistant", response["content"], response)
    broadcast(data, {:usage, response["usage"] || %{}})

    case response["stop_reason"] do
      "tool_use" ->
        calls = Enum.filter(response["content"], &(&1["type"] == "tool_use"))
        start_tools(calls, state, data)

      "end_turn" ->
        answer =
          response["content"]
          |> Enum.filter(&(&1["type"] == "text"))
          |> Enum.map_join("\n", & &1["text"])

        data = %{data | answer: answer, error: nil}
        {next, data, actions} = transition(state, :answer_started, data)
        {:next_state, next, data, actions ++ [{:next_event, :internal, :answer_done}]}

      _ ->
        fail(state, data, "Messages API did not finish an answer or request Tools")
    end
  end

  defp complete(:model, {:error, reason}, state, data), do: fail(state, data, reason)

  defp complete({:tools, _}, results, state, data) when is_list(results) do
    append(data, "user", results)
    {next, data, actions} = transition(state, :tool_returned, data)
    {:next_state, next, data, actions}
  end

  defp complete({:tools, calls}, {:error, reason}, state, data) do
    results =
      Enum.map(
        calls,
        &%{
          "type" => "tool_result",
          "tool_use_id" => &1["id"],
          "content" => reason,
          "is_error" => true
        }
      )

    complete({:tools, calls}, results, state, data)
  end

  defp complete(:builtin, result, state, data) do
    answer = Jason.encode!(result)
    append(data, "assistant", [%{"type" => "text", "text" => answer}])
    data = %{data | answer: answer}
    {next, data, actions} = transition(state, :computed, data)
    {:next_state, next, data, actions}
  end

  defp start_tools([%{"id" => id, "name" => name, "input" => input}] = calls, state, data)
       when is_binary(id) and is_binary(name) and is_map(input) do
    data = %{data | pending: {:tools, calls}}
    {next, data, actions} = transition(state, :tool_requested, data)

    if next == state do
      reject_tools(calls, state, data, "Model requested Tools without available Tool budget")
    else
      {:next_state, next, data, actions}
    end
  end

  defp start_tools(calls, state, data),
    do:
      reject_tools(
        calls,
        state,
        data,
        "Messages API must request exactly one valid Tool per turn"
      )

  defp reject_tools(calls, state, data, reason) do
    results =
      Enum.map(
        calls,
        &%{
          "type" => "tool_result",
          "tool_use_id" => &1["id"],
          "content" => reason,
          "is_error" => true
        }
      )

    if results != [], do: append(data, "user", results)
    fail(state, data, reason)
  end

  defp fail(state, data, reason) do
    data = %{data | error: reason}
    {next, data, actions} = transition(state, :api_error, data)
    {:next_state, next, data, actions}
  end

  defp transition(state, event, data) do
    {:ok, next, ctx, effects} = QuestionLifecycle.step(state, event, data.ctx)
    data = %{data | ctx: ctx}
    {data, actions} = Enum.reduce(effects, {data, []}, &effect/2)

    question =
      data.question
      |> Ecto.Changeset.change(
        state: Atom.to_string(next),
        lifecycle: ctx,
        answer: data.answer,
        error: data.error
      )
      |> Repo.update!()

    data = %{data | question: question}
    broadcast(data, {:state, next})
    if :finish_answer in effects, do: broadcast(data, {:answer, data.answer})
    {next, data, actions}
  end

  defp effect(:arm_timer, {data, actions}),
    do:
      {data,
       actions ++
         [{{:timeout, :question}, Keyword.get(data.opts, :timeout_ms, 600_000), :expired}]}

  defp effect(:stop_timer, {data, actions}),
    do: {data, actions ++ [{{:timeout, :question}, :infinity, :expired}]}

  defp effect(:request_model, {data, actions}) do
    if data.ctx.turns >= data.ctx.cap do
      {data, actions ++ [{:next_event, :internal, :over_limit}]}
    else
      messages = messages(data.question.id)
      owner = self()
      token = make_ref()
      opts = Keyword.put(data.opts, :answer_only, data.ctx.turns + 1 >= data.ctx.cap)

      task =
        Task.Supervisor.async_nolink(Analysis.TaskSupervisor, fn ->
          Anthropic.request(
            data.system,
            messages,
            data.question.model,
            &send(owner, {:stream, token, &1}),
            opts
          )
        end)

      # Stream tags are unique per request; late deltas cannot leak into Retry.
      data = %{data | task: task, pending: :model}
      {Map.put(data, :stream_token, token), actions}
    end
  end

  defp effect(:start_tool, {%{pending: {:tools, calls}} = data, actions}) do
    session_id = data.session.id

    task =
      Task.Supervisor.async_nolink(Analysis.TaskSupervisor, fn ->
        Enum.map(calls, &run_tool(&1, session_id))
      end)

    {%{data | task: task}, actions}
  end

  defp effect(:compute, {data, actions}) do
    {tool, args} = Keyword.fetch!(data.opts, :builtin_tool)
    session_id = data.session.id

    task =
      Task.Supervisor.async_nolink(Analysis.TaskSupervisor, fn ->
        case Analysis.call_tool(tool, Map.put(args, "session_id", session_id)) do
          {:ok, result} -> result
          {:error, reason} -> Analysis.error_result(reason)
        end
      end)

    {%{data | task: task, pending: :builtin}, actions}
  end

  defp effect(:stop_model, {%{pending: :model, task: %Task{} = task} = data, actions}) do
    Task.shutdown(task, :brutal_kill)
    {%{data | task: nil, pending: nil}, actions}
  end

  defp effect(_, acc), do: acc

  defp append(data, role, content, response \\ %{}) do
    Repo.insert!(%Message{
      session_id: data.session.id,
      question_id: data.question.id,
      role: role,
      content: content,
      usage: response["usage"] || %{},
      stop_reason: response["stop_reason"]
    })
  end

  defp run_tool(call, session_id) do
    args = Map.put(call["input"], "session_id", session_id)

    {content, error?} =
      case Analysis.call_tool(call["name"], args) do
        {:ok, envelope} -> {Jason.encode!(envelope), false}
        {:error, reason} -> {reason, true}
      end

    %{
      "type" => "tool_result",
      "tool_use_id" => call["id"],
      "content" => content,
      "is_error" => error?
    }
  end

  defp messages(id),
    do:
      Repo.all(from(m in Message, where: m.question_id == ^id, order_by: m.id))
      |> Enum.map(&%{role: &1.role, content: &1.content})

  defp broadcast(data, event),
    do:
      Phoenix.PubSub.broadcast(
        WeGoNext.PubSub,
        topic(data.question.id),
        {:analysis_question, data.question.id, event}
      )
end
