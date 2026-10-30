defmodule WeGoNext.Analysis.BuiltInQuestions do
  @moduledoc "Deterministic built-in bindings. The question picker can use these without a model."
  @questions [%{id: "wipe_cause", title: "Why did this pull wipe?", tool: "wipe_cause"}]

  def all, do: @questions

  def answer(id, args) do
    case Enum.find(@questions, &(&1.id == id)) do
      nil -> {:error, "Unknown built-in question"}
      question -> WeGoNext.Analysis.call_tool(question.tool, args)
    end
  end
end
