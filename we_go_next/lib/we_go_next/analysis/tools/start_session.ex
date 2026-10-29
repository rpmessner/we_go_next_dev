defmodule WeGoNext.Analysis.Tools.StartSession do
  @moduledoc "Prompt-less startup; the sole session-creation exception to read-only Tool execution."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{Result, Startup}

  def name, do: "start_session"

  def description,
    do:
      "Start an Analysis session without an MCP prompt. Optional boss name/id and imported log id/filename fragment; blanks use defaults. Returns the session id and analyst instructions with loaded Playbooks, or log choices without creating a session."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "boss" => %{"type" => "string"},
        "log" => %{"type" => "string"}
      },
      "required" => [],
      "additionalProperties" => false
    }
  end

  def run(args, _session) do
    response = Startup.response(args)

    evidence = %{
      source: "analysis.sessions + analysis priv instructions",
      session_id: response.session_id
    }

    Result.page([{response, evidence}], args, {name(), response.session_id}, &hd/1)
  end
end
