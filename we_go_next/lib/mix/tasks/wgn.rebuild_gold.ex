defmodule Mix.Tasks.Wgn.RebuildGold do
  @moduledoc """
  Rebuilds tracked failures from existing imported observations.

  This task recomputes failure rows without reparsing combat logs.

  Usage:

      mix wgn.rebuild_gold
      mix wgn.rebuild_gold --definition-set-id 123
      mix wgn.rebuild_gold --encounter-id 456

  `--definition-set-id` is a compatibility-only option for targeted backfills.
  """

  use Mix.Task

  alias WeGoNext.Gold.{DimEncounter, Rebuilds}
  alias WeGoNext.Repo
  import Ecto.Query

  @shortdoc "Rebuild tracked failures from imported observations"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args!(args)
    rebuild_opts = rebuild_opts(opts)

    encounter_ids = encounter_ids(opts)
    ruleset_label = ruleset_label(rebuild_opts)

    totals =
      case Rebuilds.rebuild_encounters(encounter_ids, rebuild_opts) do
        {:ok, totals} ->
          totals

        {:error, %{encounter_id: encounter_id, reason: reason}} ->
          Mix.raise(
            "Failed to rebuild tracked failures for pull #{encounter_id}: #{inspect(reason)}"
          )
      end

    Mix.shell().info(
      "Rebuilt tracked failures for #{length(encounter_ids)} pull(s) using #{ruleset_label}. " <>
        "Deleted #{totals.deleted} stale row(s), inserted #{totals.inserted} row(s)."
    )
  end

  defp parse_args!(args) do
    case OptionParser.parse(args,
           strict: [definition_set_id: :integer, ruleset_id: :integer, encounter_id: :integer],
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
    cond do
      definition_set_id = Keyword.get(opts, :definition_set_id) ->
        [ruleset_id: definition_set_id]

      ruleset_id = Keyword.get(opts, :ruleset_id) ->
        [ruleset_id: ruleset_id]

      true ->
        [ruleset: :active]
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

  defp ruleset_label(ruleset_id: ruleset_id), do: "definition_set_id=#{ruleset_id}"
  defp ruleset_label(ruleset: :active), do: "current mechanic definitions"
end
