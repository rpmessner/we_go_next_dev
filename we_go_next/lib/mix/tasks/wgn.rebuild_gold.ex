defmodule Mix.Tasks.Wgn.RebuildGold do
  @moduledoc """
  Rebuilds tracked failures from existing imported observations.

  This task recomputes failure rows without reparsing combat logs.

  Usage:

      mix wgn.rebuild_gold
      mix wgn.rebuild_gold --encounter-id 456

  All rebuilds use the live gold mechanics catalog.
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
    encounter_ids = encounter_ids(opts)

    totals =
      case Rebuilds.rebuild_encounters(encounter_ids) do
        {:ok, totals} ->
          totals

        {:error, %{encounter_id: encounter_id, reason: reason}} ->
          Mix.raise(
            "Failed to rebuild tracked failures for pull #{encounter_id}: #{inspect(reason)}"
          )
      end

    Mix.shell().info(
      "Rebuilt tracked failures for #{length(encounter_ids)} pull(s) using the live mechanics catalog. " <>
        "Deleted #{totals.deleted} stale row(s), inserted #{totals.inserted} row(s)."
    )
  end

  defp parse_args!(args) do
    case OptionParser.parse(args,
           strict: [encounter_id: :integer],
           aliases: [e: :encounter_id]
         ) do
      {opts, [], []} ->
        opts

      {_opts, extra, []} ->
        Mix.raise("Unexpected argument(s): #{Enum.join(extra, " ")}")

      {_opts, _extra, invalid} ->
        invalid_args =
          invalid
          |> Enum.map_join(", ", fn {arg, _value} -> arg end)

        Mix.raise("Invalid option(s): #{invalid_args}")
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
end
