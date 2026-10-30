defmodule WeGoNext.GameData.RaidsTest do
  use ExUnit.Case, async: true

  alias WeGoNext.GameData.Raids

  alias WeGoNext.GameData.Raids.{
    Dreamrift,
    MarchOnQuelDanas,
    Mechanic,
    MidnightSeason1,
    Voidspire
  }

  alias WeGoNext.Mechanics.Taxonomy

  test "indexes code-defined raid catalogs" do
    assert Enum.map(Raids.all(), & &1.slug) == [
             "the_voidspire",
             "the_dreamrift",
             "march_on_quel_danas",
             "the_venomous_abyss",
             "midnight_lairs"
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

    assert Enum.all?(dread_breath, &(&1.mechanic_type == :targeted_cone))

    assert Enum.any?(criteria, fn criterion ->
             criterion["spell_id"] == 1_272_726 and
               criterion["boss_name"] == "Chimaerus the Undreamt God"
           end)
  end

  test "current-tier mechanics are authored configs with taxonomy-derived defaults" do
    mechanics = MidnightSeason1.mechanics()

    assert Enum.all?(mechanics, &match?(%Mechanic{}, &1))

    assert Enum.all?(mechanics, fn mechanic ->
             classification = Taxonomy.fetch!(mechanic.mechanic_type)

             mechanic.definition_origin == :authored_catalog and
               mechanic.default_actionability == classification.actionability and
               mechanic.default_fact_eligibility == classification.fact_eligibility and
               is_list(mechanic.source_annotations)
           end)

    assert length(MarchOnQuelDanas.mechanics()) == 48

    assert MarchOnQuelDanas.rule_criteria() != []

    oblivions_wrath = Enum.find(mechanics, &(&1.spell_id == 1_260_718))

    assert %Mechanic{
             name: "Oblivion's Wrath",
             boss_encounter_id: "3176",
             mechanic_type: :avoidable,
             evidence_family: :damage_taken,
             definition_origin: :authored_catalog,
             source_annotations: [:dbm, :local_logs],
             default_actionability: :actionable,
             default_fact_eligibility: :supported
           } = oblivions_wrath

    assert Mechanic.rule_seed_eligible?(oblivions_wrath)

    assert Enum.any?(MidnightSeason1.rule_criteria(), fn criterion ->
             criterion["spell_id"] == oblivions_wrath.spell_id and
               criterion["mechanic_type"] == "avoidable"
           end)
  end

  test "expected Void Fall observations remain non-fact authored configs" do
    void_fall =
      MidnightSeason1.mechanics()
      |> Enum.filter(&(&1.boss_encounter_id == "3176" and &1.name == "Void Fall"))

    assert Enum.map(void_fall, & &1.spell_id) |> Enum.sort() == [1_258_880, 1_266_786]

    assert Enum.all?(void_fall, fn mechanic ->
             mechanic.mechanic_type == :unknown and
               mechanic.evidence_family == :cast and
               mechanic.definition_origin == :authored_catalog and
               mechanic.default_actionability == :unknown and
               mechanic.default_fact_eligibility == :observation_only and
               not Mechanic.rule_seed_eligible?(mechanic)
           end)

    void_fall_spell_ids = MapSet.new(void_fall, & &1.spell_id)

    refute Enum.any?(MidnightSeason1.rule_criteria(), fn criterion ->
             MapSet.member?(void_fall_spell_ids, criterion["spell_id"])
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
