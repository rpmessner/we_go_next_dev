defmodule WeGoNext.Analysis.PullScope do
  @moduledoc "Required pull arguments and session-log membership for medallion Tools."
  alias WeGoNext.Analysis.{ReadModel, Tool}

  def schema(field, extra \\ %{}) do
    id = %{"type" => "integer", "minimum" => 1}

    property =
      if field == "pull",
        do: id,
        else: %{"type" => "array", "items" => id, "minItems" => 1, "maxItems" => 1000}

    Tool.schema(Map.put(extra, field, property))
    |> Map.put("required", ["session_id", field])
  end

  def fetch(ids, session) do
    pulls = session |> ReadModel.pulls() |> Enum.filter(&(&1.pull_id in ids))

    if Enum.sort(Enum.uniq(ids)) == Enum.sort(Enum.map(pulls, & &1.pull_id)) do
      {:ok, pulls}
    else
      {:error, "Pull not found in this Analysis session log"}
    end
  end

  def evidence(pull, source, ms \\ nil) do
    %{
      pull_id: pull.pull_id,
      source: source,
      timestamp: pull.start_time,
      ms_into_fight: ms
    }
  end
end
