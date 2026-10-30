defmodule WeGoNext.GameData.CurrentTierTest do
  use ExUnit.Case, async: true

  alias WeGoNext.GameData.Raids
  alias WeGoNext.GameData.Raids.{Mechanic, VenomousAbyss}

  test "unverified bosses remain observations rather than damage failure rules" do
    unverified =
      Enum.reject(VenomousAbyss.mechanics(), &(&1.boss_encounter_id in ["3420", "3421"]))

    assert Enum.sort(Enum.uniq(Enum.map(unverified, & &1.boss_encounter_id))) ==
             ~w(3429 3445 3455 3470 3492 3497)

    for mechanic <- unverified do
      assert mechanic.notes =~ "UNVERIFIED"
      refute Mechanic.rule_seed_eligible?(mechanic)
    end
  end

  test "current-tier lookup includes the progression raid without dropping Season 1" do
    catalog = Raids.by_slug("current_tier")
    assert catalog != nil

    for encounter_id <- [3176, 3306, 3182, 3420, 3421, 3429, 3497, 3470, 3445, 3455, 3492, 3379] do
      assert Raids.by_boss_encounter_id(encounter_id)
      assert Enum.any?(apply(catalog, :bosses, []), &(&1.encounter_id == encounter_id))
    end

    criteria = apply(catalog, :rule_criteria, [])

    assert Enum.filter(criteria, &(&1["boss_encounter_id"] == "3420"))
           |> Enum.map(& &1["spell_id"])
           |> Enum.sort() == [1_287_083, 1_296_667]

    assert Enum.filter(criteria, &(&1["boss_encounter_id"] == "3421"))
           |> Enum.map(& &1["spell_id"])
           |> Enum.sort() == [1_292_807, 1_293_295, 1_306_876]

    assert Enum.any?(criteria, &(&1["spell_id"] == 1_258_677))
    refute Enum.any?(criteria, &(&1["spell_id"] in [1_294_976, 1_290_480, 1_290_662, 1_292_806]))
  end
end
