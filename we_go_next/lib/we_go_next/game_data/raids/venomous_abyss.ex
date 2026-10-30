defmodule WeGoNext.GameData.Raids.VenomousAbyss do
  @moduledoc """
  Curated catalog for The Venomous Abyss (instance 3004).

  Spell IDs and intent annotations are evidence from BigWigs, not imported code.
  Sszorak and Twin Fangs damage IDs were checked against the September 6 log.
  Other bosses are unverified against real logs; their entries remain observations.
  """

  alias WeGoNext.GameData.Raids.CatalogHelpers

  def info do
    %{
      name: "The Venomous Abyss",
      slug: "the_venomous_abyss",
      product: "wow",
      channel: "retail",
      zone_ids: [3004],
      dbm_module_map_ids: [],
      tier: "Midnight Season 2"
    }
  end

  def bosses do
    # BigWigs journal IDs are not DBM module IDs. Leave unknown DBM metadata nil.
    Enum.map(
      [
        {"Sszorak", 3420},
        {"The Twin Fangs", 3421},
        {"The Coiled Altar", 3429},
        {"The Lost Explorers", 3497},
        {"Nek'zali the Soulcoiler", 3470},
        {"Entombed Sentinels", 3445},
        {"Vashnik the Malignant", 3455},
        {"Ula'tek", 3492}
      ],
      fn {name, id} -> CatalogHelpers.boss(name, id, nil, nil, 3004) end
    )
  end

  def mechanics do
    verified_mechanics() ++ unverified_mechanics()
  end

  def rule_criteria, do: CatalogHelpers.rule_criteria(mechanics())

  defp verified_mechanics do
    [
      entry(3420, 1_287_083, "Tempest", :avoidable, :damage_taken,
        "Sszorak.lua: Tempest debuffFailureMoveFromCastNote. Real damage is ST, sparse per application; ticks count as hits."),
      entry(3420, 1_296_667, "Caustic Residue", :avoidable, :damage_taken,
        "Sszorak.lua: underyou warning. Real ground damage is ST, not a raid-wide pulse."),
      entry(3420, 1_277_025, "Apex Predator", :tank_mechanic, :cast,
        "Sszorak.lua: tank_combo; never blame the tank for taking the assigned combo."),
      entry(3420, 1_285_965, "Ula'tek's Presence", :unknown, :damage_taken,
        "Raid-wide AOE pressure in the real log; no individual failure attribution."),
      entry(3420, 1_285_999, "Mutilate", :unknown, :damage_taken,
        "AOE hits reach the whole raid. Tank-combo warning does not make every damage variant avoidable."),
      entry(3420, 1_285_998, "Mutilated Gash", :unknown, :damage_taken,
        "Raid-wide AOE periodic damage, distinct from the tank debuff 1277051."),
      entry(3420, 1_287_205, "Viscous Cyst", :unknown, :damage_taken,
        "BigWigs labels an add cast; observed AOE reaches the raid, not generic avoidable damage."),
      entry(3420, 1_306_120, "Venomous Surge", :unknown, :damage_taken,
        "BigWigs bombs warning; observed raid-wide AOE is not proof of individual failure."),
      entry(3420, 1_305_959, "Venomous Surge", :spread, :cast,
        "Sszorak.lua: bombs; targeted placement needs dedicated attribution, not raw damage blame."),
      entry(3420, 1_285_425, "Raging Crosswinds", :unknown, :cast,
        "BigWigs winds warning alone does not prove avoidable player damage."),
      entry(3421, 1_293_295, "Corrosive Spit", :avoidable, :damage_taken,
        "TwinFangs.lua: 1291478 avoid annotation. Sparse AOE impact 1293295, not the targeting debuff."),
      entry(3421, 1_292_807, "Stir the Depths", :avoidable, :damage_taken,
        "TwinFangs.lua: 1290956 dodge waves. Sparse hit/debuff 1292807; NOT raid-wide AOE 1292806."),
      entry(3421, 1_306_876, "Sanguine Storm", :avoidable, :damage_taken,
        "TwinFangs.lua: 1306872 avoid pools. Sparse AOE impact 1306876; other damage variants remain unclassified."),
      entry(3421, 1_290_516, "Ravenous Feast", :soak, :cast,
        "TwinFangs.lua explicitly renames this to soak."),
      entry(3421, 1_290_662, "Ravenous Feast", :soak, :damage_taken,
        "Observed shared AOE soak damage, not avoidable damage."),
      entry(3421, 1_310_371, "Stone Breaker", :tank_mechanic, :damage_taken,
        "BigWigs 1288538 TANK/slams annotation; observed impact primarily hits two tanks."),
      entry(3421, 1_294_976, "Toxic Fumes", :unknown, :damage_taken,
        "All 23 players in all eight pulls; raid-wide AOE pressure, not avoidable by volume alone."),
      entry(3421, 1_290_480, "Eternal Venom", :unknown, :damage_taken,
        "All 23 players in all eight pulls; ST suffix on periodic damage does not establish avoidability."),
      entry(3421, 1_290_878, "Coiling Ichor", :unknown, :damage_taken,
        "All 23 players in all eight pulls. BigWigs toxin label supplies no safe individual blame rule."),
      entry(3421, 1_292_806, "Stir the Depths", :unknown, :damage_taken,
        "Raid-wide AOE component; must not inherit the wave-hit criterion on 1292807."),
      entry(3421, 1_288_237, "Caustic Deluge", :unknown, :damage_taken,
        "ST damage on two players per pull. Do not confuse assigned targets with avoidable globules."),
      entry(3421, 1_288_201, "Caustic Globule", :unknown, :damage_taken,
        "Hits nearly everyone per pull; BigWigs orbs annotation is insufficient to classify this variant."),
      entry(3421, 1_308_122, "Venomous Emergence", :unknown, :damage_taken,
        "BigWigs adds annotation; AOE reaches the raid. No individual failure semantics.")
    ]
  end

  defp unverified_mechanics do
    # UNVERIFIED: no September 6 pulls for these bosses. No damage rule seeds.
    [
      entry(3429, 1_299_680, "Sever", :tank_mechanic, :cast, "CoiledAltar.lua: tank_frontal."),
      entry(3429, 1_286_573, "Soul Sever", :tank_mechanic, :cast, "CoiledAltar.lua: tank_frontal."),
      entry(3429, 1_307_279, "Blighted Sever", :tank_mechanic, :cast, "CoiledAltar.lua: tank_frontal."),
      entry(3497, 1_295_858, "Shredding Shards", :tank_mechanic, :debuff_application,
        "Explorers.lua: tank_debuff."),
      entry(3497, 1_291_929, "Steady Strikes", :tank_mechanic, :debuff_application,
        "Explorers.lua: tank_debuff."),
      entry(3497, 1_286_921, "Icebound Flames", :interrupt, :interrupt_opportunity,
        "Explorers.lua: cast option 1286921, failure-to-interrupt debuff 1286922."),
      entry(3470, 1_284_109, "Hollowing Strikes", :tank_mechanic, :debuff_application,
        "Nekzali.lua: tank_debuff / tank stacks."),
      entry(3470, 1_305_421, "Hungering Pyre", :soak, :cast, "Nekzali.lua: soak."),
      entry(3470, 1_285_681, "Soulcoil Ignition", :avoidable, :cast,
        "Nekzali.lua: dodge. Cast-only observation until damage ID is verified."),
      entry(3445, 1_284_491, "Bloodvenom Injection", :tank_mechanic, :debuff_application,
        "Sentinels.lua: tank_debuff, drops pool when it expires."),
      entry(3445, 1_288_232, "Unstable Miasma", :soak, :cast, "Sentinels.lua: soak."),
      entry(3455, 1_280_935, "Dripping Fangs", :tank_mechanic, :cast,
        "Vashnik.lua: TANK / tank_hit."),
      entry(3455, 1_295_173, "Exploding Infection", :healer_mechanic, :debuff_application,
        "Vashnik.lua: magic dispel."),
      entry(3492, 1_298_367, "Mother's Wrath", :tank_mechanic, :cast,
        "Ulatek.lua: TANK / tank_knockback."),
      entry(3492, 1_300_530, "Spectral Coils", :soak, :cast, "Ulatek.lua: soaks, left/right."),
      entry(3492, 1_295_905, "Serpent's Bite", :soak, :cast, "Ulatek.lua: soaks.")
    ]
  end

  defp entry(encounter_id, spell_id, name, type, family, notes) do
    verified = encounter_id in [3420, 3421]
    boss = Enum.find(bosses(), &(&1.encounter_id == encounter_id))

    CatalogHelpers.mechanic(
      info().name,
      info().slug,
      %{
        boss_name: boss.name,
        boss_encounter_id: encounter_id,
        spell_id: spell_id,
        name: name,
        mechanic_type: type,
        evidence_family: family,
        source_annotations:
          if(verified and family == :damage_taken, do: [:bigwigs, :combat_log], else: [:bigwigs])
      },
      notes: if(verified, do: notes, else: "UNVERIFIED against real logs. " <> notes)
    )
  end
end
