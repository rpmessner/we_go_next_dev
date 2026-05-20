defmodule WeGoNext.GameData.RaidsTest do
  use ExUnit.Case, async: true

  alias WeGoNext.GameData.Raids
  alias WeGoNext.GameData.Raids.{Dreamrift, MarchOnQuelDanas, MidnightSeason1, Voidspire}

  test "indexes code-defined raid catalogs" do
    assert Enum.map(Raids.all(), & &1.slug) == [
             "the_voidspire",
             "the_dreamrift",
             "march_on_quel_danas"
           ]

    assert Raids.by_slug("midnight_season_1") == MidnightSeason1
    assert Raids.by_slug("the_voidspire") == Voidspire
    assert Raids.by_slug("voidspire") == Voidspire
    assert Raids.by_slug("the_dreamrift") == Dreamrift
    assert Raids.by_slug("march_on_quel_danas") == MarchOnQuelDanas
    assert Raids.by_dbm_module_map_id(1307) == Voidspire
    assert Raids.by_dbm_module_map_id(1308) == MarchOnQuelDanas
    assert Raids.by_dbm_module_map_id(1314) == Dreamrift
    assert Raids.by_slug("missing") == nil
  end

  test "Midnight Season 1 exposes current-tier boss metadata and syncable rule criteria" do
    assert %{name: "Midnight Season 1", slug: "midnight_season_1"} = MidnightSeason1.info()

    assert Enum.map(MidnightSeason1.bosses(), & &1.encounter_id) == [
             3176,
             3177,
             3178,
             3179,
             3180,
             3181,
             3306,
             3182,
             3183
           ]

    criteria = MidnightSeason1.rule_criteria()

    assert Enum.all?(criteria, &(&1["mechanic_type"] == "avoidable"))
    assert Enum.map(criteria, & &1["threshold"]) |> Enum.uniq() == [%{"max_hits" => 0}]

    assert Enum.any?(criteria, fn criterion ->
             criterion["spell_id"] == 1_272_726 and
               criterion["boss_name"] == "Chimaerus the Undreamt God"
           end)
  end
end
