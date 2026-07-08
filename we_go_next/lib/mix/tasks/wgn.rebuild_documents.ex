defmodule Mix.Tasks.Wgn.RebuildDocuments do
  @moduledoc """
  Rebuilds encounter JSON documents from existing medallion read models.

  Usage:

      mix wgn.rebuild_documents
      mix wgn.rebuild_documents --encounter-id 456
  """

  use Mix.Task

  alias WeGoNext.Documents

  @shortdoc "Rebuild encounter JSON documents"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args!(args)

    case Documents.rebuild_all(opts) do
      {:ok, totals} ->
        Mix.shell().info("Rebuilt encounter documents for #{totals.encounters} pull(s).")

      {:error, %{encounter_id: encounter_id, reason: reason}} ->
        Mix.raise(
          "Failed to rebuild encounter document for pull #{encounter_id}: #{inspect(reason)}"
        )
    end
  end

  defp parse_args!(args) do
    case OptionParser.parse(args, strict: [encounter_id: :integer], aliases: [e: :encounter_id]) do
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
end
