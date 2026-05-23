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

  test "Midnight Season 1 exposes current-tier boss metadata and fact-eligible mechanics" do
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

    assert length(MidnightSeason1.mechanics()) == 164
    assert length(criteria) == 30
    assert Enum.count(criteria, &(&1["mechanic_type"] == "avoidable")) == 29
    assert Enum.count(criteria, &(&1["mechanic_type"] == "targeted_cone")) == 1
    assert Enum.any?(criteria, &(&1["spell_id"] == 1_244_221))
    assert Enum.any?(criteria, &(&1["spell_id"] == 1_260_718))
    assert Enum.any?(criteria, &(&1["spell_id"] == 1_275_558))
    assert Enum.any?(criteria, &(&1["spell_id"] == 1_233_826))
    refute Enum.any?(criteria, &(&1["spell_id"] == 1_244_225))

    dread_breath =
      MidnightSeason1.mechanics()
      |> Enum.filter(&(&1.boss_name == "Vaelgor & Ezzorak" and &1.name == "Dread Breath"))

    assert Enum.map(dread_breath, & &1.spell_id) |> Enum.sort() == [
             1_244_221,
             1_244_225,
             1_255_612,
             1_255_979
           ]

    assert Enum.all?(dread_breath, &(&1.type == :targeted_cone))

    assert Enum.any?(criteria, fn criterion ->
             criterion["spell_id"] == 1_272_726 and
               criterion["boss_name"] == "Chimaerus the Undreamt God"
           end)
  end

  test "track metadata no longer gates supported avoidable damage mechanics" do
    mechanics = MidnightSeason1.mechanics()

    assert length(Enum.filter(mechanics, & &1.track)) == 5
    assert length(MarchOnQuelDanas.mechanics()) == 48

    assert Enum.all?(MarchOnQuelDanas.mechanics(), &(&1.track == false))
    assert MarchOnQuelDanas.rule_criteria() != []

    assert Enum.any?(mechanics, fn mechanic ->
             mechanic.spell_id == 1_245_452 and
               mechanic.name == "Corrupted Devastation" and
               mechanic.track == false and
               mechanic.sources == [:dbm]
           end)

    assert Enum.any?(mechanics, fn mechanic ->
             mechanic.spell_id == 1_251_386 and
               mechanic.name == "Safeguard Prism" and
               mechanic.track == false and
               mechanic.sources == [:dbm, :wowanalyzer]
           end)
  end

  test "indexes interruptible raid spells for silver interrupt projection" do
    spell_ids =
      Raids.interruptible_spells()
      |> Enum.map(& &1.spell_id)
      |> Enum.sort()

    assert 1_249_017 in spell_ids
    assert 1_251_386 in spell_ids
    refute 1_248_652 in spell_ids
  end
end
