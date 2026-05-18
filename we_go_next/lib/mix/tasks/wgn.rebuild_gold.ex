defmodule Mix.Tasks.Wgn.RebuildGold do
  @moduledoc """
  Rebuilds gold failure facts from existing silver rows.

  This task proves the gold layer can be rebuilt from silver without reparsing
  combat logs.

  Usage:

      mix wgn.rebuild_gold
      mix wgn.rebuild_gold --ruleset-id 123
      mix wgn.rebuild_gold --encounter-id 456
  """

  use Mix.Task

  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, FactFailure}
  alias WeGoNext.Repo

  @shortdoc "Rebuild gold.fact_failure from silver rows"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args!(args)
    rebuild_opts = rebuild_opts(opts)

    encounter_ids = encounter_ids(opts)
    ruleset_label = ruleset_label(rebuild_opts)

    totals =
      Enum.reduce(encounter_ids, %{deleted: 0, inserted: 0}, fn encounter_id, totals ->
        case FactFailure.rebuild_for_encounter(encounter_id, rebuild_opts) do
          {:ok, result} ->
            %{
              deleted: totals.deleted + result.deleted,
              inserted: totals.inserted + result.inserted
            }

          {:error, reason} ->
            Mix.raise(
              "Failed to rebuild gold.fact_failure for encounter #{encounter_id}: #{inspect(reason)}"
            )
        end
      end)

    Mix.shell().info(
      "Rebuilt gold.fact_failure for #{length(encounter_ids)} encounter(s) using #{ruleset_label}. " <>
        "Deleted #{totals.deleted} stale fact row(s), inserted #{totals.inserted} fact row(s)."
    )
  end

  defp parse_args!(args) do
    case OptionParser.parse(args,
           strict: [ruleset_id: :integer, encounter_id: :integer],
           aliases: [r: :ruleset_id, e: :encounter_id]
         ) do
      {opts, [], []} ->
        opts

      {_opts, extra, []} ->
        Mix.raise("Unexpected argument(s): #{Enum.join(extra, " ")}")

      {_opts, _extra, invalid} ->
        invalid_args =
          invalid
          |> Enum.map(fn {arg, _value} -> arg end)
          |> Enum.join(", ")

        Mix.raise("Invalid option(s): #{invalid_args}")
    end
  end

  defp rebuild_opts(opts) do
    case Keyword.fetch(opts, :ruleset_id) do
      {:ok, ruleset_id} -> [ruleset_id: ruleset_id]
      :error -> [ruleset: :active]
    end
  end

  defp encounter_ids(opts) do
    case Keyword.fetch(opts, :encounter_id) do
      {:ok, encounter_id} ->
        [encounter_id]

      :error ->
        DimEncounter
        |> order_by([encounter], asc: encounter.id)
        |> select([encounter], encounter.id)
        |> Repo.all()
    end
  end

  defp ruleset_label(ruleset_id: ruleset_id), do: "ruleset_id=#{ruleset_id}"
  defp ruleset_label(ruleset: :active), do: "active ruleset"
end
