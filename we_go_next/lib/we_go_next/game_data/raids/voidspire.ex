defmodule WeGoNext.GameData.Raids.Voidspire do
  @moduledoc """
  Curated mechanic catalog for The Voidspire.

  DBM, WowAnalyzer, journal data, and local log observations are scaffolding
  inputs, but this file is the curated source used to seed editable rules.
  """

  import WeGoNext.GameData.Raids.CatalogHelpers, only: [boss: 5, rule_criteria: 1]
  alias WeGoNext.GameData.Raids.CatalogHelpers

  @raid_name "The Voidspire"
  @raid_slug "the_voidspire"

  def info do
    %{
      name: @raid_name,
      slug: @raid_slug,
      product: "wow",
      channel: "retail",
      zone_ids: [2912],
      dbm_module_map_ids: [1307],
      tier: "Midnight Season 1"
    }
  end

  def bosses do
    [
      boss("Imperator Averzian", 3176, 2733, 1307, 2912),
      boss("Vorasius", 3177, 2734, 1307, 2912),
      boss("Vaelgor & Ezzorak", 3178, 2735, 1307, 2912),
      boss("Fallen King Salhadaar", 3179, 2736, 1307, 2912),
      boss("Lightblinded Vanguard", 3180, 2737, 1307, 2912),
      boss("Crown of the Cosmos", 3181, 2738, 1307, 2912)
    ]
  end

  def mechanics do
    [
      mechanic(
        "Imperator Averzian",
        3176,
        1_260_712,
        "Oblivion Wrath",
        :avoidable,
        :damage_taken,
        [:dbm]
      ),
      mechanic(
        "Imperator Averzian",
        3176,
        1_260_718,
        "Oblivion's Wrath",
        :avoidable,
        :damage_taken,
        [:dbm, :local_logs],
        notes: "Direct damage spell observed in imported logs for DBM dodge/orb warning 1260712."
      ),
      mechanic(
        "Imperator Averzian",
        3176,
        1_255_702,
        "Pitch Bulwark",
        :interrupt,
        :interrupt_opportunity,
        [:dbm]
      ),
      mechanic("Imperator Averzian", 3176, 1_249_265, "Umbral Collapse", :soak, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Imperator Averzian", 3176, 1_249_266, "Umbral Collapse", :soak, :cast, [
        :wowanalyzer
      ]),
      mechanic(
        "Imperator Averzian",
        3176,
        1_249_262,
        "Umbral Collapse",
        :soak,
        :damage_taken,
        [:local_logs],
        notes:
          "Observed damage outcome for Umbral Collapse; soak fact semantics are not implemented yet."
      ),
      mechanic(
        "Imperator Averzian",
        3176,
        1_260_203,
        "March of the Endless",
        :soak,
        :debuff_application,
        [:dbm, :wowanalyzer]
      ),
      mechanic("Imperator Averzian", 3176, 1_260_206, "Umbral Collapse", :soak, :cast, [
        :wowanalyzer
      ]),
      mechanic(
        "Imperator Averzian",
        3176,
        1_280_013,
        "Void Marked",
        :healer_mechanic,
        :debuff_application,
        [:wowanalyzer]
      ),
      mechanic("Imperator Averzian", 3176, 1_249_251, "Dark Upheaval", :unknown, :cast, [:dbm]),
      mechanic(
        "Imperator Averzian",
        3176,
        1_259_903,
        "Dark Upheaval",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes:
          "High-volume observed damage for DBM AOEDAMAGE cast 1249251; do not treat as generic avoidable damage."
      ),
      mechanic("Imperator Averzian", 3176, 1_251_361, "Shadow's Advance", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic("Imperator Averzian", 3176, 1_251_583, "March of the Endless", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic("Imperator Averzian", 3176, 1_258_880, "Void Fall", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Imperator Averzian", 3176, 1_262_776, "Shadow's Advance", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Imperator Averzian", 3176, 1_266_786, "Void Fall", :unknown, :cast, [:wowanalyzer]),
      mechanic(
        "Imperator Averzian",
        3176,
        1_280_075,
        "Lingering Darkness",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes:
          "Observed current-tier damage/debuff spell; attribution semantics need manual review."
      ),
      mechanic("Vorasius", 3177, 1_243_853, "Void Breath", :avoidable, :damage_taken, [:dbm]),
      mechanic("Vorasius", 3177, 1_254_199, "Parasite Expulsion", :avoidable, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic(
        "Vorasius",
        3177,
        1_275_558,
        "Parasite Expulsion",
        :avoidable,
        :damage_taken,
        [:dbm, :wowanalyzer, :local_logs],
        notes:
          "Direct damage spell observed for DBM movement/add warning 1254199; player hits are failure-eligible."
      ),
      mechanic("Vorasius", 3177, 1_256_855, "Void Breath", :avoidable, :damage_taken, [
        :wowanalyzer
      ]),
      mechanic("Vorasius", 3177, 1_241_836, "Shadowclaw Slam", :unknown, :cast, [:dbm]),
      mechanic(
        "Vorasius",
        3177,
        1_241_808,
        "Shadowclaw Slam",
        :tank_mechanic,
        :damage_taken,
        [:local_logs],
        notes:
          "Observed damage outcome for Shadowclaw Slam; tank fact semantics are not implemented yet."
      ),
      mechanic(
        "Vorasius",
        3177,
        1_272_328,
        "Shadowclaw Slam",
        :tank_mechanic,
        :damage_taken,
        [:local_logs],
        notes:
          "Observed Shadowclaw Slam variant damage; tank fact semantics are not implemented yet."
      ),
      mechanic(
        "Vorasius",
        3177,
        1_281_954,
        "Shadowclaw Slam",
        :tank_mechanic,
        :damage_taken,
        [:local_logs],
        notes: "High-damage Shadowclaw Slam variant observed on player targets."
      ),
      mechanic("Vorasius", 3177, 1_254_113, "Fixate", :unknown, :debuff_application, [
        :wowanalyzer
      ]),
      mechanic("Vorasius", 3177, 1_260_046, "Primordial Roar", :unknown, :cast, [:dbm]),
      mechanic("Vorasius", 3177, 1_260_052, "Primordial Roar", :unknown, :cast, [:wowanalyzer]),
      mechanic(
        "Vorasius",
        3177,
        1_272_950,
        "Primordial Power",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes:
          "High-volume observed damage; likely encounter pressure, not generic avoidable damage."
      ),
      mechanic(
        "Vorasius",
        3177,
        1_280_101,
        "Dark Energy",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes: "High-volume observed damage; attribution semantics need manual review."
      ),
      mechanic(
        "Vorasius",
        3177,
        1_259_186,
        "Blisterburst",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes:
          "Observed raid damage without source warning evidence; keep out of avoidable facts."
      ),
      mechanic(
        "Vaelgor & Ezzorak",
        3178,
        1_244_221,
        "Dread Breath",
        :targeted_cone,
        :cast,
        [
          :dbm,
          :wowanalyzer
        ],
        notes:
          "Targeted cone cast; assignment target is exposed by spell 1255612 and cast success.",
        rule: %{
          target_marker_spell_id: 1_255_612,
          impact_spell_ids: [1_244_225],
          hit_debuff_spell_ids: [1_255_979],
          max_safe_hit_count: 2,
          target_role_policy: :any,
          allowed_collateral_roles: [:tank],
          position_evidence: :optional
        }
      ),
      mechanic(
        "Vaelgor & Ezzorak",
        3178,
        1_244_225,
        "Dread Breath",
        :targeted_cone,
        :damage_taken,
        [
          :combat_log,
          :wowanalyzer
        ],
        notes: "Direct cone impact spell observed in imported logs."
      ),
      mechanic(
        "Vaelgor & Ezzorak",
        3178,
        1_255_612,
        "Dread Breath",
        :targeted_cone,
        :debuff_application,
        [:wowanalyzer],
        notes: "Pre-target marker debuff applied before Dread Breath impact."
      ),
      mechanic(
        "Vaelgor & Ezzorak",
        3178,
        1_255_979,
        "Dread Breath",
        :targeted_cone,
        :debuff_application,
        [:wowanalyzer],
        notes: "Post-hit debuff and periodic damage on players clipped by Dread Breath."
      ),
      mechanic("Vaelgor & Ezzorak", 3178, 1_262_623, "Null Beam", :avoidable, :damage_taken, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_245_645, "Rakfang", :tank_mechanic, :cast, [:dbm]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_265_131, "Vaelwing", :tank_mechanic, :cast, [:dbm]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_244_672, "Nullzone", :unknown, :debuff_application, [
        :wowanalyzer
      ]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_244_917, "Void Howl", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_245_391, "Gloom", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_248_847, "Radiant Barrier", :unknown, :cast, [:dbm]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_249_748, "Midnight Flames", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic(
        "Vaelgor & Ezzorak",
        3178,
        1_259_275,
        "Midnight Manifestation",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes: "Observed damage source in imported Vaelgor & Ezzorak pulls; semantics unknown."
      ),
      mechanic(
        "Vaelgor & Ezzorak",
        3178,
        1_270_497,
        "Shadowmark",
        :unknown,
        :debuff_application,
        [:wowanalyzer]
      ),
      mechanic("Vaelgor & Ezzorak", 3178, 1_277_470, "Cosmosis Gloom", :unknown, :cast, [:dbm]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_277_471, "Cosmosis Null Beam", :unknown, :cast, [:dbm]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_277_472, "Cosmosis Dread Breath", :unknown, :cast, [
        :dbm
      ]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_277_473, "Cosmosis Void Howl", :unknown, :cast, [:dbm]),
      mechanic(
        "Fallen King Salhadaar",
        3179,
        1_246_175,
        "Entropic Unraveling",
        :avoidable,
        :damage_taken,
        [:dbm, :wowanalyzer]
      ),
      mechanic(
        "Fallen King Salhadaar",
        3179,
        1_248_697,
        "Twilight Obscurity",
        :avoidable,
        :debuff_application,
        [:wowanalyzer]
      ),
      mechanic(
        "Fallen King Salhadaar",
        3179,
        1_253_024,
        "Shattering Twilight",
        :avoidable,
        :damage_taken,
        [:dbm]
      ),
      mechanic(
        "Fallen King Salhadaar",
        3179,
        1_254_081,
        "Fractured Projection",
        :interrupt,
        :interrupt_opportunity,
        [:dbm, :wowanalyzer]
      ),
      mechanic("Fallen King Salhadaar", 3179, 1_253_032, "Tank Spikes", :tank_mechanic, :cast, [
        :wowanalyzer
      ]),
      mechanic("Fallen King Salhadaar", 3179, 1_243_453, "Void Convergence", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Fallen King Salhadaar", 3179, 1_250_686, "Twilight Obscurity", :unknown, :cast, [
        :dbm
      ]),
      mechanic(
        "Fallen King Salhadaar",
        3179,
        1_285_504,
        "Dark Radiation",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes:
          "Observed raid damage in imported heroic pulls; no individual failure semantics yet."
      ),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_246_765,
        "Divine Storm",
        :avoidable,
        :damage_taken,
        [:dbm, :local_logs],
        track: true,
        rule: %{max_hits: 0},
        notes:
          "DBM marks this as a melee movement warning; observed as player damage in current logs."
      ),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_248_451,
        "Aura of Peace",
        :avoidable,
        :damage_taken,
        [:dbm, :wowanalyzer]
      ),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_248_652,
        "Divine Toll",
        :avoidable,
        :damage_taken,
        [:dbm, :local_logs],
        track: true,
        rule: %{max_hits: 0},
        notes: "DBM DodgeCount warning with DODGES label and observed damage in current logs."
      ),
      mechanic("Lightblinded Vanguard", 3180, 1_276_368, "Execution Sentence", :soak, :cast, [
        :dbm
      ]),
      mechanic("Lightblinded Vanguard", 3180, 1_246_162, "Aura of Devotion", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_246_736,
        "Final Judgement",
        :unknown,
        :debuff_application,
        [:dbm, :wowanalyzer]
      ),
      mechanic("Lightblinded Vanguard", 3180, 1_246_749, "Sacred Toll", :unknown, :cast, [:dbm]),
      mechanic("Lightblinded Vanguard", 3180, 1_248_449, "Aura of Wrath", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Lightblinded Vanguard", 3180, 1_248_674, "Sacred Shield", :unknown, :cast, [:dbm]),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_248_994,
        "Execution Sentence",
        :unknown,
        :debuff_application,
        [:wowanalyzer]
      ),
      mechanic("Lightblinded Vanguard", 3180, 1_249_130, "Elephant", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_251_857,
        "Judgement Shield",
        :unknown,
        :debuff_application,
        [:dbm, :wowanalyzer]
      ),
      mechanic("Lightblinded Vanguard", 3180, 1_255_738, "Searing Radiance", :unknown, :cast, [
        :dbm
      ]),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_255_739,
        "Searing Radiance",
        :unknown,
        :damage_taken,
        [:dbm, :local_logs],
        notes:
          "Observed damage/debuff outcome for Searing Radiance; not generic avoidable damage."
      ),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_272_310,
        "Empowered Divine Storm",
        :unknown,
        :cast,
        [:dbm]
      ),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_276_639,
        "Empowered Searing Radiance",
        :unknown,
        :cast,
        [:dbm]
      ),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_248_502,
        "Avenger's Shield",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes: "Observed player damage without supported failure semantics."
      ),
      mechanic(
        "Lightblinded Vanguard",
        3180,
        1_258_661,
        "Light Infusion",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes:
          "High-volume observed damage; likely encounter pressure rather than avoidable failure."
      ),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_233_819,
        "Void Expulsion",
        :avoidable,
        :damage_taken,
        [:wowanalyzer]
      ),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_233_826,
        "Void Expulsion",
        :avoidable,
        :damage_taken,
        [:wowanalyzer, :local_logs],
        notes: "Direct observed damage for WowAnalyzer Void Expulsion area-denial spell 1233819."
      ),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_243_753,
        "Ravenous Abyss",
        :avoidable,
        :damage_taken,
        [:dbm, :wowanalyzer, :local_logs],
        track: true,
        rule: %{max_hits: 0},
        notes: "DBM DodgeCount warning; WowAnalyzer identifies the cast as Ravenous Abyss."
      ),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_243_743,
        "Interrupting Tremor",
        :interrupt,
        :interrupt_opportunity,
        [:dbm, :wowanalyzer]
      ),
      mechanic("Crown of the Cosmos", 3181, 1_233_787, "Dark Hand", :tank_mechanic, :cast, [:dbm]),
      mechanic("Crown of the Cosmos", 3181, 1_246_461, "Rift Slash", :tank_mechanic, :cast, [:dbm]),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_233_602,
        "Silverstrike Arrow",
        :unknown,
        :debuff_application,
        [:wowanalyzer]
      ),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_233_649,
        "Silverstrike Arrow",
        :unknown,
        :damage_taken,
        [:wowanalyzer, :local_logs],
        notes: "Observed damage outcome for Silverstrike Arrow debuff; not failure-eligible yet."
      ),
      mechanic("Crown of the Cosmos", 3181, 1_237_837, "Call of the Void", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Crown of the Cosmos", 3181, 1_238_843, "Devouring Cosmos", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Crown of the Cosmos", 3181, 1_239_080, "Aspect of the End", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_239_111,
        "Aspect of the End",
        :unknown,
        :debuff_application,
        [:wowanalyzer]
      ),
      mechanic("Crown of the Cosmos", 3181, 1_246_918, "Cosmic Barrier", :unknown, :cast, [:dbm]),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_246_925,
        "Cosmic Barrier",
        :unknown,
        :damage_taken,
        [:dbm, :local_logs],
        notes: "Observed damage around the shield phase; attribution needs manual review."
      ),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_259_861,
        "Ranger-Captain's Mark",
        :unknown,
        :debuff_application,
        [:wowanalyzer]
      ),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_260_027,
        "Grasp of Emptiness",
        :unknown,
        :debuff_application,
        [:wowanalyzer]
      ),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_243_981,
        "Silverstrike Barrage",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes: "Observed player damage without supported failure semantics."
      ),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_260_000,
        "Void Barrage",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes: "Observed player damage without supported failure semantics."
      ),
      mechanic(
        "Crown of the Cosmos",
        3181,
        1_242_553,
        "Void Remnants",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes:
          "Observed damage/debuff spell; likely environmental residue, not generic avoidable damage."
      ),
      mechanic("Crown of the Cosmos", 3181, 1_261_339, "Cosmic Portal", :unknown, :cast, [:dbm]),
      mechanic("Crown of the Cosmos", 3181, 1_283_236, "Void Expulsion", :unknown, :cast, [:dbm])
    ]
  end

  def rule_criteria, do: rule_criteria(mechanics())

  defp mechanic(boss_name, encounter_id, spell_id, name, type, event, sources, opts \\ []) do
    CatalogHelpers.mechanic(
      @raid_name,
      @raid_slug,
      boss_name,
      encounter_id,
      spell_id,
      name,
      type,
      event,
      sources,
      opts
    )
  end
end
