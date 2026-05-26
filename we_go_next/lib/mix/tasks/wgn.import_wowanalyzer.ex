defmodule Mix.Tasks.Wgn.ImportWowAnalyzer do
  @moduledoc """
  Imports WowAnalyzer encounter timeline metadata into source-data tables.

  The import records WowAnalyzer source provenance and parsed timeline source
  rows only. It does not sync active mechanics or rebuild failures.

  Usage:

      mix wgn.import_wowanalyzer
      mix wgn.import_wowanalyzer --root /path/to/WoWAnalyzer/src/game/raids/vs_dr_mqd
      mix wgn.import_wowanalyzer --build-key 11.2.5 --channel ptr
  """

  use Mix.Task

  alias WeGoNext.SourceData

  @shortdoc "Import WowAnalyzer timeline source rows"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args!(args)

    case SourceData.import_wowanalyzer_sources(opts) do
      {:ok, summary} ->
        Mix.shell().info(format_summary(summary))

      {:error, {:missing_roots, roots}} ->
        Mix.raise("Missing WowAnalyzer root(s): #{Enum.join(roots, ", ")}")

      {:error, {path, reason}} ->
        Mix.raise("Failed to import #{path}: #{inspect(reason)}")

      {:error, reason} ->
        Mix.raise("Failed to import WowAnalyzer source data: #{inspect(reason)}")
    end
  end

  defp parse_args!(args) do
    case OptionParser.parse(args,
           strict: [
             root: :string,
             repo_root: :string,
             product: :string,
             channel: :string,
             build_version: :string,
             build_key: :string,
             locale: :string,
             source_system: :string,
             repository_revision: :string,
             repository_license: :string,
             raid_slug: :string,
             raid_name: :string
           ]
         ) do
      {opts, [], []} ->
        normalize_opts(opts)

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

  defp normalize_opts(opts) do
    roots = Keyword.get_values(opts, :root)
    opts = Keyword.delete(opts, :root)

    if roots == [] do
      opts
    else
      Keyword.put(opts, :roots, roots)
    end
  end

  defp format_summary(summary) do
    "Imported WowAnalyzer timeline source data from #{length(summary.roots)} root(s): " <>
      "#{summary.files_imported} file(s), " <>
      "#{summary.source_imports_inserted} new source import(s), " <>
      "#{summary.source_imports_updated} refreshed source import(s), " <>
      "#{summary.candidates_inserted} source row(s) inserted, " <>
      "#{summary.candidates_updated} source row(s) refreshed. " <>
      "Source license: #{summary.repository_license}."
  end
end
