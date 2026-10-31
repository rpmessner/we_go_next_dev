defmodule WeGoNext.Analysis do
  @moduledoc "Analysis sessions and recorded, bounded Tool calls, separate from the medallion."
  import Ecto.Query
  alias WeGoNext.Repo

  alias WeGoNext.Analysis.{
    Arguments,
    Executor,
    Startup,
    Registry,
    Result,
    Session,
    ToolCall,
    Verdict
  }

  def start_session(args \\ %{}), do: Startup.start(args)

  @doc "Starts a supervised headless question. Scope uses log/boss and optional pull ids; model is an operator choice."
  def ask(scope, text, opts \\ [])
      when is_map(scope) and is_binary(text) and byte_size(text) > 0 do
    with {:ok, session} <- question_session(scope, opts) do
      model = Keyword.get(opts, :model, session.model)

      if model != session.model do
        {:error, "Model must match this Analysis session's operator choice"}
      else
        question =
          Repo.insert!(%WeGoNext.Analysis.Question{
            session_id: session.id,
            scope: scope,
            text: text,
            model: model
          })

        if Keyword.get(opts, :subscribe, false), do: subscribe_question(question.id)

        case DynamicSupervisor.start_child(
               WeGoNext.Analysis.QuestionSupervisor,
               {WeGoNext.Analysis.QuestionRunner, {question, session, opts}}
             ) do
          {:ok, pid} -> {:ok, question, pid}
          {:error, _} -> {:error, "Could not start question process"}
        end
      end
    end
  end

  def get_question(id), do: Repo.get(WeGoNext.Analysis.Question, id)

  def question_event(id, event, opts \\ []),
    do: WeGoNext.Analysis.QuestionRunner.event(id, event, opts)

  def subscribe_question(id), do: WeGoNext.Analysis.QuestionRunner.subscribe(id)

  defp question_session(scope, opts) do
    case Keyword.get(opts, :session_id) do
      nil ->
        args = scope |> Map.take(["log", "boss"]) |> Map.new(fn {k, v} -> {k, to_string(v)} end)

        with {:ok, session} <- start_session(args) do
          session
          |> Ecto.Changeset.change(model: Keyword.get(opts, :model, session.model))
          |> Repo.update()
        end

      id ->
        case find_session(id) do
          nil ->
            {:error, "Unknown Analysis session"}

          session ->
            books =
              WeGoNext.Analysis.Playbooks.for_boss(
                WeGoNext.Analysis.Playbooks.load(),
                session.boss,
                WeGoNext.Analysis.ReadModel.pulls(session)
              )

            {:ok, %{session | playbooks: books}}
        end
    end
  end

  def call_tool(name, args) when is_binary(name) and is_map(args) do
    start = System.monotonic_time(:millisecond)
    session = find_session(args["session_id"])
    outcome = invoke(Registry.fetch(name), args, session)
    session = started_session(name, session, outcome)
    {result, error} = recorded_result(outcome)
    duration_ms = System.monotonic_time(:millisecond) - start
    record_playbook_load(name, session, outcome)

    {:ok, question} =
      Repo.transaction(fn ->
        question = record_verdict(name, outcome, session)

        Repo.insert!(%ToolCall{
          session_id: session && session.id,
          tool: name,
          args: args,
          result: result,
          result_size: byte_size(Jason.encode!(result)),
          duration_ms: duration_ms,
          truncated: Map.get(result, :truncated, false),
          error: error,
          called_at: DateTime.utc_now()
        })

        question
      end)

    if is_struct(question, WeGoNext.Analysis.Question),
      do: WeGoNext.Analysis.QuestionRunner.notify_snapshot(question)

    outcome
  rescue
    _ -> {:error, "Tool call could not be recorded"}
  end

  defp record_playbook_load("get_playbook", session, {:ok, result}) do
    Repo.transaction(fn ->
      current = Repo.one!(from(s in Session, where: s.id == ^session.id, lock: "FOR UPDATE"))

      loaded =
        Enum.map(result.evidence, &%{"id" => &1.playbook_id, "git_commit" => &1.git_commit})

      books = Enum.uniq(current.loaded_playbooks ++ loaded)
      current |> Ecto.Changeset.change(loaded_playbooks: books) |> Repo.update!()
    end)
  end

  defp record_playbook_load(_, _, _), do: :ok

  defp started_session("start_session", _, {:ok, %{data: %{session_id: id}}}),
    do: find_session(id)

  defp started_session(_, session, _), do: session

  defp record_verdict("record_verdict", {:ok, %{data: data}}, session) do
    question = record_question_verdict(session, data)

    Repo.insert!(%Verdict{
      session_id: session.id,
      answer: data["answer"],
      verdict: data["verdict"],
      correction: data["correction"],
      recorded_at: DateTime.utc_now()
    })

    question
  end

  defp record_verdict(_, _, _), do: :ok

  defp record_question_verdict(session, data) do
    questions =
      Repo.all(
        from(q in WeGoNext.Analysis.Question,
          where: q.session_id == ^session.id,
          lock: "FOR UPDATE"
        )
      )

    matches =
      case data["question_id"] do
        nil -> Enum.filter(questions, &(&1.answer == data["answer"]))
        id -> Enum.filter(questions, &(&1.id == id))
      end

    case {questions, matches, data["question_id"]} do
      {[], _, nil} -> :ok
      {_, [question], _} -> WeGoNext.Analysis.QuestionRunner.record_verdict_snapshot!(question)
      _ -> Repo.rollback(:ambiguous_question_verdict)
    end
  end

  defp invoke(nil, _, _), do: {:error, "Unknown Tool"}

  defp invoke(WeGoNext.Analysis.Tools.StartSession = tool, args, _),
    do: execute_tool(tool, args, nil)

  defp invoke(_, _, nil), do: {:error, "Unknown Analysis session; invoke analysis-session first"}

  defp invoke(tool, args, session), do: execute_tool(tool, args, session)

  defp execute_tool(tool, args, session) do
    with :ok <- Arguments.validate(args, tool.input_schema()),
         {:ok, result} <- Executor.run(tool, args, session),
         true <- valid_envelope?(result) do
      {:ok, result}
    else
      false -> {:error, "Tool returned an invalid or oversized result"}
      {:error, _} = error -> error
      _ -> {:error, "Tool returned an invalid result"}
    end
  rescue
    _ -> {:error, "Tool returned an invalid result"}
  end

  defp valid_envelope?(result) when is_map(result) do
    Map.has_key?(result, :data) and is_list(result[:evidence]) and is_boolean(result[:truncated]) and
      (is_nil(result[:next_cursor]) or is_binary(result[:next_cursor])) and
      byte_size(Jason.encode!(result)) <= Result.cap()
  end

  defp valid_envelope?(_), do: false

  defp find_session(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Session, uuid)
      :error -> nil
    end
  end

  defp recorded_result({:ok, result}), do: {result, nil}

  defp recorded_result({:error, reason}), do: {error_result(reason), reason}

  def error_result(reason),
    do: %{data: nil, evidence: [], truncated: false, next_cursor: nil, error: reason}
end
