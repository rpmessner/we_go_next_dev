defmodule WeGoNext.LegacyAnalyzerBoundaryTest do
  use ExUnit.Case, async: true

  @legacy_analyzer_modules ~w(
    DamageDoneAnalyzer
    DamageTakenAnalyzer
    DeathAnalyzer
    DebuffAnalyzer
    InterruptAnalyzer
    PlayerInfoAnalyzer
  )

  @allowed_reference_files MapSet.new([
                             "lib/we_go_next.ex",
                             "test/we_go_next/silver/round_trip_test.exs"
                           ])

  test "legacy analyzer references stay behind documented compatibility boundaries" do
    unexpected_references =
      source_files()
      |> Enum.reject(&legacy_analyzer_file?/1)
      |> Enum.reject(&current_test_file?/1)
      |> Enum.filter(&references_legacy_analyzer?/1)
      |> Enum.reject(&MapSet.member?(@allowed_reference_files, &1))

    assert unexpected_references == [],
           """
           Legacy analyzers are reference-only. New medallion UI, read models,
           gold facts, rules, and source-data code must use silver/gold/rules
           tables instead of analyzer output.

           Unexpected references:
           #{Enum.map_join(unexpected_references, "\n", &"  * #{&1}")}
           """
  end

  defp source_files do
    ["lib/**/*.ex", "test/**/*.exs"]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.sort()
  end

  defp legacy_analyzer_file?(path), do: String.starts_with?(path, "lib/we_go_next/analyzers/")

  defp current_test_file?(path), do: Path.expand(path) == Path.expand(__ENV__.file)

  defp references_legacy_analyzer?(path) do
    body = File.read!(path)
    Enum.any?(@legacy_analyzer_modules, &String.contains?(body, &1))
  end
end
