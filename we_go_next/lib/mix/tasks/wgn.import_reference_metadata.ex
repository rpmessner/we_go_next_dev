defmodule Mix.Tasks.Wgn.ImportReferenceMetadata do
  @moduledoc """
  Imports spell and encounter reference metadata into source-data tables.

  Usage:

      mix wgn.import_reference_metadata --build-key 11.2.5
      mix wgn.import_reference_metadata --file /path/to/reference_bundle.json --build-key 11.2.5
      mix wgn.import_reference_metadata --spell-file ../tools/spell_names.json --build-key 11.2.5

  Input files may be spell-id/name maps or bundles with `spells`,
  `encounters`, and optional `encounter_spells` arrays.
  """

  use Mix.Task

  alias WeGoNext.SourceData

  @shortdoc "Import source-data spell and encounter references"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args!(args)

    case SourceData.import_reference_metadata_files(reference_files(opts), opts) do
      {:ok, summary} ->
        Mix.shell().info(format_summary(summary))

      {:error, {_path, :build_key_required}} ->
        Mix.raise("Reference metadata import requires --build-key")

      {:error, {path, reason}} ->
        Mix.raise("Failed to import #{path}: #{inspect(reason)}")
    end
  end

  defp parse_args!(args) do
    case OptionParser.parse(args,
           strict: [
             file: :string,
             spell_file: :string,
             encounter_file: :string,
             product: :string,
             channel: :string,
             build_version: :string,
             build_key: :string,
             locale: :string,
             source_system: :string,
             source_priority: :integer
           ]
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

  defp reference_files(opts) do
    files =
      opts
      |> Keyword.get_values(:file)
      |> Kernel.++(Keyword.get_values(opts, :spell_file))
      |> Kernel.++(Keyword.get_values(opts, :encounter_file))

    if files == [] do
      [SourceData.default_spell_reference_path()]
    else
      files
    end
  end

  defp format_summary(summary) do
    "Imported reference metadata from #{summary.files_imported} file(s): " <>
      "#{summary.source_imports_inserted} new source import(s), " <>
      "#{summary.source_imports_updated} refreshed source import(s), " <>
      "#{summary.spells_inserted} spell(s) inserted, " <>
      "#{summary.spells_updated} spell(s) refreshed, " <>
      "#{summary.encounters_inserted} encounter(s) inserted, " <>
      "#{summary.encounters_updated} encounter(s) refreshed, " <>
      "#{summary.encounter_spells_inserted} encounter-spell link(s) inserted, " <>
      "#{summary.encounter_spells_updated} encounter-spell link(s) refreshed."
  end
end
