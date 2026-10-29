defmodule WeGoNext.Analysis.Tools.SessionContext do
  @moduledoc "Compact, paginated snapshot of the Analysis session log."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{ReadModel, Result, Tool}
  def name, do: "session_context"

  def description,
    do:
      "Get the session log, pulls, real roster (class/spec/role), and medallion freshness. Compact snapshot, paginated around 3 KB; follow next_cursor for remaining pulls/roster."

  def input_schema, do: Tool.schema()

  def run(args, context) do
    log = ReadModel.log(context)
    pulls = ReadModel.pulls(context)
    roster = ReadModel.roster(pulls)

    base = %{
      log: %{id: log.id, file: Path.basename(log.file_path), last_imported_at: log.last_parsed_at},
      freshness: ReadModel.freshness(pulls, log)
    }

    rows =
      Enum.map(pulls, &{{:pull, &1}, ReadModel.evidence(&1)}) ++
        Enum.map(
          roster,
          &{{:player, Map.drop(&1, [:pull_id, :timestamp])},
           %{
             source: "silver.player_info + gold.dim_encounter",
             pull_id: &1.pull_id,
             timestamp: &1.timestamp
           }}
        )

    Result.page(rows, args, {name(), context.id}, &snapshot(&1, base), 3_072)
  end

  defp snapshot(rows, base) do
    pulls = for {:pull, pull} <- rows, do: pull
    public_ids = Enum.map(pulls, & &1.public_encounter_id)
    gold_ids = Enum.map(pulls, & &1.pull_id)
    freshness = base.freshness

    page_freshness =
      Map.merge(freshness, %{
        unimported_pull_count: length(freshness.unimported_pull_ids),
        stale_failure_pull_count: length(freshness.stale_failure_pull_ids),
        unimported_pull_ids: Enum.filter(freshness.unimported_pull_ids, &(&1 in public_ids)),
        stale_failure_pull_ids: Enum.filter(freshness.stale_failure_pull_ids, &(&1 in gold_ids)),
        id_scope: "this page; counts cover the session log"
      })

    Map.merge(base, %{
      freshness: page_freshness,
      pulls: pulls,
      roster: for({:player, p} <- rows, do: p)
    })
  end
end
