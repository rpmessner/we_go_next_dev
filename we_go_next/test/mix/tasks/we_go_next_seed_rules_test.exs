defmodule Mix.Tasks.WeGoNext.SeedRulesTest do
  use WeGoNext.DataCase, async: false
  import ExUnit.CaptureIO
  alias Mix.Tasks.WeGoNext.{SeedRules, SyncRaidRules}
  alias WeGoNext.Gold.DimMechanicCriterion
  alias WeGoNext.Repo

  test "default seed and sync write directly to the same live catalog" do
    output = capture_io(fn -> SeedRules.run([]) end)
    assert output =~ "Synced 32 raid mechanic(s) into the live gold catalog"
    first = Repo.all(DimMechanicCriterion) |> Enum.map(& &1.id) |> Enum.sort()
    capture_io(fn -> SyncRaidRules.run([]) end)
    assert Repo.all(DimMechanicCriterion) |> Enum.map(& &1.id) |> Enum.sort() == first
  end

  test "--rebuild runs sync then rebuild without lifecycle flags" do
    output = capture_io(fn -> SyncRaidRules.run(["--rebuild"]) end)
    assert output =~ "Synced 32 raid mechanic(s) into the live gold catalog"
    assert output =~ "Rebuilt failures:"
    assert output =~ "encounters: 0"
  end

  test "obsolete activation, promotion and version flags are rejected" do
    for flag <- ["--activate", "--promote", "--failure-ready", "--version", "--name"] do
      assert_raise Mix.Error, ~r/Invalid options/, fn -> SyncRaidRules.run([flag]) end
    end
  end

  test "JSON fixtures are not a second catalog authoring path" do
    assert_raise Mix.Error, ~r/JSON seeds are retired/, fn -> SeedRules.run(["fixture.json"]) end
  end
end
