defmodule WeGoNext.Analysis.Tools.ListPulls do
  @moduledoc "Pull catalogue scoped to an Analysis session's log."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{ReadModel, Result, Tool}
  def name, do: "list_pulls"

  def description,
    do:
      "List pulls within the Analysis session log, optionally by boss name/id or night (YYYY-MM-DD UTC). Pull ids are gold ids; null means not imported into the medallion. Follow next_cursor with identical filters."

  def input_schema,
    do:
      Tool.schema(%{
        "boss" => %{"type" => "string"},
        "night" => %{"type" => "string", "format" => "date"}
      })

  def run(args, context) do
    rows =
      context
      |> ReadModel.pulls()
      |> Enum.filter(&matches?(&1, args))
      |> Enum.map(&{&1, ReadModel.evidence(&1)})

    Result.page(rows, args, {name(), context.id})
  end

  defp matches?(pull, args) do
    boss = args["boss"]
    night = args["night"]

    (is_nil(boss) or boss in [pull.boss, pull.boss_id]) and
      (is_nil(night) or
         (pull.start_time && Date.to_iso8601(DateTime.to_date(pull.start_time))) == night)
  end
end
