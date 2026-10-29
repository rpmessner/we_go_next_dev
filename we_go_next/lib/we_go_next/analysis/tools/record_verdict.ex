defmodule WeGoNext.Analysis.Tools.RecordVerdict do
  @moduledoc "Prepares a verdict for the recording path; execution itself stays read-only."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{Arguments, Result}
  def name, do: "record_verdict"

  def description,
    do: "Record the operator's judgment of an answer or question, with correction text."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "session_id" => %{"type" => "string", "format" => "uuid"},
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
      data = Map.take(args, ["answer", "verdict", "correction"])
      evidence = %{source: "analysis.verdicts", session_id: session.id}
      Result.page([{data, evidence}], args, {name(), session.id}, &List.first/1)
    else
      false -> {:error, "Verdict must belong to this Analysis session"}
      error -> error
    end
  end
end
