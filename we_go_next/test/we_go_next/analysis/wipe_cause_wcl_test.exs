Code.require_file("../../../../scripts/wipe_cause_reference.exs", __DIR__)

defmodule WeGoNext.Analysis.WipeCauseWCLTest do
  use ExUnit.Case, async: true

  test "Warcraft Logs: all 16 shared pulls, with each killing-blow difference explained" do
    path =
      Path.join(System.tmp_dir!(), "wipe-reference-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(WipeCauseReference.output()))
    on_exit(fn -> File.rm!(path) end)
    script = Path.expand("../../../../scripts/compare_wipe_cause_wcl.py", __DIR__)
    cache = Path.expand("../../fixtures/wipe_cause_wcl", __DIR__)
    {json, exit} = System.cmd("python3", [script, "--cache", cache, "--facts", path])
    # The script reports actual ID differences, rather than hiding WCL normalization.
    assert exit == 1
    results = Jason.decode!(json)
    assert length(results) == 16

    assert Enum.map(results, & &1["pull"]) == [
             435,
             438,
             439,
             440,
             441,
             442,
             443,
             444,
             445,
             446,
             447,
             448,
             449,
             450,
             451,
             452
           ]

    assert Enum.map(Enum.filter(results, &(&1["mismatches"] != [])), & &1["pull"]) == [451]
    mismatch = Enum.find(results, &(&1["pull"] == 451))
    assert length(mismatch["mismatches"]) == 3

    assert Enum.all?(
             mismatch["mismatches"],
             &String.contains?(&1, "gold spell 1290480, WCL 1292348 (Eternal Venom)")
           )

    unknown = Enum.find(results, &(&1["pull"] == 440))["unknown_wcl_blows"]
    assert [%{"player" => "Felthuzad", "rank" => 3}] = unknown
  end
end
