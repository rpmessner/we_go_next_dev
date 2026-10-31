defmodule WeGoNext.Analysis.QuestionRunner do
  @moduledoc "Supervised per-question effect adapter. IO runs here, never in the lifecycle table."
  @behaviour :gen_statem
  import Ecto.Query
  alias WeGoNext.Analysis
  alias WeGoNext.Analysis.{Anthropic, Message, Question, QuestionLifecycle, Startup}
  alias WeGoNext.Repo

  def child_spec(args),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [args]}, restart: :temporary}

  def start_link({question, session, opts}) do
    name = {:via, Registry, {Analysis.QuestionRegistry, question.id}}
    :gen_statem.start_link(name, __MODULE__, {question, session, opts}, [])
  end

  def event(id, event, opts \\ [])

  def event(id, event, opts) when event in [:cancel, :continue, :retry, :record_verdict],
    do: call_event(id, event, opts, 1)

  def event(_, _, _), do: {:error, :invalid_event}

  defp call_event(id, event, opts, retries) do
    with {:ok, pid} <- ensure_started(id, opts) do
      :gen_statem.call(pid, {:event, event})
    end
  catch
    :exit, {reason, {:gen_statem, :call, _}} when reason in [:normal, :noproc] and retries > 0 ->
      call_event(id, event, opts, retries - 1)
  end

  def snapshot(id) do
    case Registry.whereis_name({Analysis.QuestionRegistry, id}) do
      pid when is_pid(pid) -> :gen_statem.call(pid, :snapshot)
      :undefined -> stored_snapshot(id)
    end
  catch
    :exit, {reason, {:gen_statem, :call, _}} when reason in [:normal, :noproc] ->
      stored_snapshot(id)
  end

  defp stored_snapshot(id) do
    case Analysis.get_question(id) do
      nil -> {:error, :not_found}
      question -> {state(question), question}
    end
  end

  defp ensure_started(id, opts) do
    case Registry.whereis_name({Analysis.QuestionRegistry, id}) do
      pid when is_pid(pid) -> {:ok, pid}
      :undefined -> start_stored(Analysis.get_question(id), opts)
    end
  end

  defp start_stored(nil, _opts), do: {:error, :not_found}

  defp start_stored(question, opts) do
    question =
      if state(question) in [:thinking, :calling_tool, :writing] or
           question.lifecycle["tool_in_flight"] == true,
         do: recover_snapshot(question),
         else: question

    session = Repo.get!(Analysis.Session, question.session_id)

    books =
      Analysis.Playbooks.for_boss(
        Analysis.Playbooks.load(),
        session.boss,
        Analysis.ReadModel.pulls(session)
      )

    session = %{session | playbooks: books}

    case DynamicSupervisor.start_child(
           Analysis.QuestionSupervisor,
           {__MODULE__, {question, session, opts}}
         ) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      result -> result
    end
  end

  defp state(question),
    do: Enum.find(QuestionLifecycle.states(), &(Atom.to_string(&1) == question.state))

  @doc false
  def notify_snapshot(question) do
    Phoenix.PubSub.broadcast(
      WeGoNext.PubSub,
      topic(question.id),
      {:analysis_question, question.id, {:state, state(question)}}
    )
  end

  @doc false
  def record_verdict_snapshot!(question) do
    ctx = QuestionLifecycle.restore(question.lifecycle)
    {:ok, next, ctx, effects} = QuestionLifecycle.step(state(question), :record_verdict, ctx)
    if :verdict not in effects, do: Repo.rollback(:question_not_answered)

    question
    |> Ecto.Changeset.change(state: to_string(next), lifecycle: ctx)
    |> Repo.update!()
  end

  @doc "Recovers interrupted snapshots without running any effect or replaying a paid request."
  def recover_orphans do
    Repo.all(
      from(q in Question,
        where:
          q.state in ["thinking", "calling_tool", "writing"] or
            fragment("?->>'tool_in_flight' = 'true'", q.lifecycle)
      )
    )
    |> Enum.each(fn question ->
      if Registry.whereis_name({Analysis.QuestionRegistry, question.id}) == :undefined do
        recover_snapshot(question)
      end
    end)

    :ok
  end

  defp recover_snapshot(question) do
    {:ok, question} =
      Repo.transaction(fn ->
        question = Repo.one!(from(q in Question, where: q.id == ^question.id, lock: "FOR UPDATE"))
        ctx = QuestionLifecycle.restore(question.lifecycle)
        record_interrupted_tool(question)

        {:ok, next, ctx, _} = QuestionLifecycle.step(state(question), :recover, ctx)

        question
        |> Ecto.Changeset.change(
          state: to_string(next),
          lifecycle: ctx,
          error:
            if(next == :failed,
              do: "Analysis interrupted by a process restart; Retry to resume",
              else: question.error
            )
        )
        |> Repo.update!()
      end)

    question
  end

  defp record_interrupted_tool(question) do
    messages = Repo.all(from(m in Message, where: m.question_id == ^question.id, order_by: m.id))
    recorded = for m <- messages, b <- m.content, b["type"] == "tool_result", do: b["tool_use_id"]
    calls = messages |> Enum.filter(&(&1.role == "assistant")) |> List.last()

    results =
      for call <- if(calls, do: calls.content, else: []),
          call["type"] == "tool_use",
          call["id"] not in recorded do
        %{
          "type" => "tool_result",
          "tool_use_id" => call["id"],
          "content" => "Tool execution interrupted; outcome unknown. Not automatically replayed.",
          "is_error" => true
        }
      end

    if results != [] do
      Repo.insert!(%Message{
        session_id: question.session_id,
        question_id: question.id,
        role: "user",
        content: results
      })
    end
  end

  def topic(id), do: "analysis_question:#{id}"
  def subscribe(id), do: Phoenix.PubSub.subscribe(WeGoNext.PubSub, topic(id))

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init({question, session, opts}) do
    data = %{
      question: question,
      session: session,
      ctx:
        if(question.state == "draft",
          do: QuestionLifecycle.initial(opts),
          else: QuestionLifecycle.restore(question.lifecycle)
        ),
      opts: opts,
      task: nil,
      pending: nil,
      stream_token: nil,
      answer: question.answer,
      error: question.error,
      system:
        Startup.instructions(session) <>
          "\nThis in-app Analysis session is already started. Do not call start_session. " <>
          "Begin with session_context using the Analysis session id above.\n"
    }

    if question.state == "draft" do
      append(data, "user", [
        %{
          "type" => "text",
          "text" => question.text <> "\nScope: " <> Jason.encode!(question.scope)
        }
      ])

      event = if data.ctx.kind == :builtin, do: :ask_builtin, else: :ask_agent
      {:ok, :draft, data, [{:next_event, :internal, event}]}
    else
      {:ok, state(question), data}
    end
  end

  @impl true
  def handle_event(type, event, state, data) do
    dispatch(type, event, state, data)
  rescue
    error in [
      Ecto.ConstraintError,
      Ecto.InvalidChangesetError,
      Ecto.StaleEntryError,
      Postgrex.Error,
      DBConnection.ConnectionError
    ] ->
      storage_failure(type, state, data, error)
  end

  defp storage_failure(type, state, data, error) do
    require Logger

    Logger.error(
      "Analysis question #{data.question.id} persistence failed: #{inspect(error.__struct__)}"
    )

    reason = "Could not persist Analysis question"
    completed_tool? = type == :info and match?({:tools, _}, data.pending)
    event = if data.ctx.tool_in_flight and not completed_tool?, do: :timeout, else: :recover
    {:ok, next, ctx, effects} = QuestionLifecycle.step(state, event, data.ctx)
    {data, _} = Enum.reduce(effects, {%{data | ctx: ctx, error: reason}, []}, &effect/2)
    persist_failure(data, next, completed_tool?)
    broadcast(data, {:error, reason})

    replies =
      case type do
        {:call, from} -> [{:reply, from, {:error, reason}}]
        _ -> []
      end

    if ctx.tool_in_flight do
      {:next_state, next, data, replies}
    else
      {:stop_and_reply, :normal, replies, data}
    end
  end

  defp persist_failure(data, next, completed_tool?) do
    Repo.transaction(fn ->
      if completed_tool?, do: record_interrupted_tool(data.question)

      data.question
      |> Ecto.Changeset.change(state: to_string(next), lifecycle: data.ctx, error: data.error)
      |> Repo.update!(mode: :savepoint)
    end)
  rescue
    _ -> :unavailable
  end

  defp dispatch({:call, from}, :snapshot, state, data),
    do: {:keep_state_and_data, [{:reply, from, {state, data.question}}]}

  defp dispatch({:call, from}, {:event, event}, state, data)
       when event in [:cancel, :continue, :retry, :record_verdict] do
    {next, data, actions} = transition(state, event, data)
    {:next_state, next, data, [{:reply, from, :ok} | actions]}
  end

  defp dispatch({:call, from}, _, _, _),
    do: {:keep_state_and_data, [{:reply, from, {:error, :invalid_event}}]}

  defp dispatch(:internal, :stop_if_terminal, state, data) do
    if state in [:answered, :judged, :failed, :cancelled, :limit_hit] and
         not data.ctx.tool_in_flight do
      {:stop, :normal, data}
    else
      :keep_state_and_data
    end
  end

  defp dispatch(:internal, event, state, data) do
    {next, data, actions} = transition(state, event, data)
    {:next_state, next, data, actions}
  end

  defp dispatch({:timeout, :question}, :expired, state, data) do
    {next, data, actions} = transition(state, :timeout, data)
    {:next_state, next, data, actions}
  end

  defp dispatch(
         :info,
         {:stream, token, delta},
         _state,
         %{stream_token: token, pending: :model} = data
       ) do
    broadcast(data, delta)
    :keep_state_and_data
  end

  defp dispatch(:info, {ref, result}, state, %{task: %{ref: ref}, pending: pending} = data) do
    Process.demonitor(ref, [:flush])
    complete(pending, result, state, %{data | task: nil})
  end

  defp dispatch(
         :info,
         {:DOWN, ref, :process, _, _},
         state,
         %{task: %{ref: ref}, pending: pending} = data
       ) do
    complete(pending, {:error, "Analysis worker failed"}, state, %{data | task: nil})
  end

  defp dispatch(:info, _, _, _), do: :keep_state_and_data

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

    question =
      data.question
      |> Ecto.Changeset.change(
        state: Atom.to_string(next),
        lifecycle: ctx,
        answer: data.answer,
        error: data.error
      )
      |> Repo.update!(mode: :savepoint)

    data = %{data | question: question}
    {data, actions} = Enum.reduce(effects, {data, []}, &effect/2)
    broadcast(data, {:state, next})
    if :finish_answer in effects, do: broadcast(data, {:answer, data.answer})
    {next, data, actions ++ [{:next_event, :internal, :stop_if_terminal}]}
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
    Repo.insert!(
      %Message{
        session_id: data.session.id,
        question_id: data.question.id,
        role: role,
        content: content,
        usage: response["usage"] || %{},
        stop_reason: response["stop_reason"]
      },
      mode: :savepoint
    )
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
