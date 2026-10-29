defmodule WeGoNext.Analysis.Tools.GetPlaybook do
  @moduledoc "Fetch a reviewed Playbook by catalogue id."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{Playbooks, Result, Tool}
  def name, do: "get_playbook"

  def description,
    do:
      "Read an active Playbook by id from list_playbooks. Join body parts in order; follow next_cursor with the same id to finish loading it."

  def input_schema,
    do: Tool.schema(%{"id" => %{"type" => "string"}}) |> Map.put("required", ["session_id", "id"])

  def run(args, session) do
    case Enum.find(Playbooks.load(), &(&1.id == args["id"] and &1.status == "active")) do
      nil ->
        {:error, "Active Playbook not found"}

      book ->
        rows =
          ~r/.{1,1500}/us
          |> Regex.scan(book.body)
          |> Enum.with_index(1)
          |> Enum.map(fn {[body], part} ->
            {Map.merge(Playbooks.metadata(book), %{body: body, part: part}),
             %{playbook_id: book.id, git_commit: book.git_commit}}
          end)

        Result.page(rows, args, {name(), session.id})
    end
  end
end
