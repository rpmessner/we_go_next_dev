defmodule WeGoNext.Analysis.Tools.RecordVerdict do
  @moduledoc "Prepares a verdict for the recording path; execution itself stays read-only."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{Arguments, Result}
  def name, do: "record_verdict"

  def description,
    do:
      "Record the operator's judgment with correction text. For in-app answers, supply question_id; otherwise answer must exactly identify one stored answer."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "session_id" => %{"type" => "string", "format" => "uuid"},
        "question_id" => %{"type" => "string", "format" => "uuid"},
        "answer" => %{"type" => "string", "minLength" => 1, "maxLength" => 3000},
        "verdict" => %{"type" => "string", "enum" => ["correct", "partly", "wrong"]},
        "correction" => %{"type" => "string", "maxLength" => 3000}
      },
      "required" => ["session_id", "answer", "verdict", "correction"],
      "additionalProperties" => false
    }
  end

  def run(args, session) do
    with :ok <- Arguments.validate(args, input_schema()),
         true <- args["session_id"] == session.id do
      data = Map.take(args, ["question_id", "answer", "verdict", "correction"])
      evidence = %{source: "analysis.verdicts", session_id: session.id}
      Result.page([{data, evidence}], args, {name(), session.id}, &List.first/1)
    else
      false -> {:error, "Verdict must belong to this Analysis session"}
      error -> error
    end
  end
end
