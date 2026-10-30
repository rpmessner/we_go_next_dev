defmodule WeGoNext.GameData.Raids.MidnightLairs do
  @moduledoc "Curated Midnight Lairs coverage, currently Nymrissa Wavecaller."

  alias WeGoNext.GameData.Raids.CatalogHelpers

  def info do
    %{
      name: "Midnight Lairs",
      slug: "midnight_lairs",
      product: "wow",
      channel: "retail",
      zone_ids: [2987],
      dbm_module_map_ids: [],
      tier: "Midnight Season 2"
    }
  end

  def bosses, do: [CatalogHelpers.boss("Nymrissa Wavecaller", 3379, nil, nil, 2987)]

  def damage_targets do
    %{
      3379 => %{
        boss: [252_959],
        priority: [253_032],
        verified: true,
        notes:
          "Nymrissa.lua:8 boss (Verify comment resolved by Sept 6 GUID); :40 Alluring Bubble adds. Sept 6 Bubblefin Shorerunner 253032 casts Alluring Bubble 1260012; authored priority kill target."
      }
    }
  end

  def mechanics do
    [
      entry(
        1_258_677,
        "Swirling Whirlpools",
        :avoidable,
        :damage_taken,
        "Nymrissa.lua: 1258668 dodge annotation. Real impact 1258677 is ST: 11 hits on eight players, not raid-wide."
      ),
      entry(1_282_937, "Iceblade Flurry", :tank_mechanic, :cast, "Nymrissa.lua: tank_hit."),
      entry(
        1_282_945,
        "Iceblade Flurry",
        :tank_mechanic,
        :damage_taken,
        "Real ST damage on two players, consistent with the assigned tank hit."
      ),
      entry(
        1_260_843,
        "Abyssal Rain",
        :unknown,
        :damage_taken,
        "Raid-wide AOE pressure in the September 6 pull; not avoidable damage."
      ),
      entry(
        1_313_393,
        "Chilling Frost",
        :unknown,
        :damage_taken,
        "BigWigs warning alone does not establish avoidability; no individual blame rule."
      ),
      entry(
        1_257_654,
        "Lingering Frost",
        :unknown,
        :damage_taken,
        "Observed AOE damage, but no explicit dodge annotation; leave unclassified."
      )
    ]
  end

  def rule_criteria, do: CatalogHelpers.rule_criteria(mechanics())

  defp entry(spell_id, name, type, family, notes) do
    CatalogHelpers.mechanic(
      info().name,
      info().slug,
      %{
        boss_name: "Nymrissa Wavecaller",
        boss_encounter_id: 3379,
        spell_id: spell_id,
        name: name,
        mechanic_type: type,
        evidence_family: family,
        source_annotations:
          if(family == :damage_taken, do: [:bigwigs, :combat_log], else: [:bigwigs])
      },
      notes: notes
    )
  end
end
