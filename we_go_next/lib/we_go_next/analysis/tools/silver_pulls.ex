defmodule WeGoNext.Analysis.Tools.SilverPulls do
  @moduledoc false
  alias WeGoNext.Analysis.{ReadModel, Tool}

  def schema(filters \\ %{}) do
    %{"required" => required} =
      schema =
      Tool.schema(
        Map.put(filters, "pulls", %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 100,
          "items" => %{"type" => "integer", "minimum" => 1}
        })
      )

    Map.put(schema, "required", required ++ ["pulls"])
  end

  def select(args, context) do
    pulls = ReadModel.pulls(context)
    ids = Enum.map(pulls, & &1.pull_id) |> Enum.reject(&is_nil/1)

    if Enum.all?(args["pulls"], &(&1 in ids)) do
      {:ok, Enum.filter(pulls, &(&1.pull_id in args["pulls"]))}
    else
      {:error, "Every pull must be an imported gold pull id in this Analysis session log"}
    end
  end
end
