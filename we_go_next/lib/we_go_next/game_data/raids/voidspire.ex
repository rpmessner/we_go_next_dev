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
      mechanic("Vorasius", 3177, 1_243_853, "Void Breath", :avoidable, :damage_taken, [:dbm]),
      mechanic("Vorasius", 3177, 1_254_199, "Parasite Expulsion", :avoidable, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Vorasius", 3177, 1_256_855, "Void Breath", :avoidable, :damage_taken, [
        :wowanalyzer
      ]),
      mechanic("Vorasius", 3177, 1_241_836, "Shadowclaw Slam", :unknown, :cast, [:dbm]),
      mechanic("Vorasius", 3177, 1_254_113, "Fixate", :unknown, :debuff_application, [
        :wowanalyzer
      ]),
      mechanic("Vorasius", 3177, 1_260_046, "Primordial Roar", :unknown, :cast, [:dbm]),
      mechanic("Vorasius", 3177, 1_260_052, "Primordial Roar", :unknown, :cast, [:wowanalyzer]),
      mechanic("Vaelgor & Ezzorak", 3178, 1_244_221, "Dread Breath", :avoidable, :damage_taken, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic(
        "Vaelgor & Ezzorak",
        3178,
        1_255_612,
        "Dread Breath",
        :avoidable,
        :debuff_application,
        [:wowanalyzer]
      ),
      mechanic(
        "Vaelgor & Ezzorak",
        3178,
        1_255_979,
        "Dread Breath",
        :avoidable,
        :debuff_application,
        [:wowanalyzer]
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
