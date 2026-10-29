defmodule WeGoNext.Analysis.Tools.ListPlaybooks do
  @moduledoc "Active Playbook discovery."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{Playbooks, Result, Tool}
  def name, do: "list_playbooks"

  def description,
    do:
      "List active Playbooks, optionally filtered by question_family. Fetch instructions with get_playbook."

  def input_schema do
    Tool.schema(%{
      "question_family" => %{
        "type" => "string",
        "enum" => ~w(wipes deaths mechanics coaching own-play)
      }
    })
  end

  def run(args, session) do
    rows =
      Playbooks.load()
      |> Enum.filter(
        &(&1.status == "active" and
            (is_nil(args["question_family"]) or args["question_family"] in &1.question_families))
      )
      |> Enum.map(&{Playbooks.metadata(&1), %{playbook_id: &1.id, git_commit: &1.git_commit}})

    Result.page(rows, args, {name(), session.id})
  end
end
