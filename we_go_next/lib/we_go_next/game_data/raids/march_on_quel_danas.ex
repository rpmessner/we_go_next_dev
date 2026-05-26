defmodule WeGoNext.GameData.Raids.MarchOnQuelDanas do
  @moduledoc """
  Curated mechanic catalog for March on Quel'Danas.
  """

  import WeGoNext.GameData.Raids.CatalogHelpers, only: [boss: 5, rule_criteria: 1]
  alias WeGoNext.GameData.Raids.CatalogHelpers

  @raid_name "March on Quel'Danas"
  @raid_slug "march_on_quel_danas"

  def info do
    %{
      name: @raid_name,
      slug: @raid_slug,
      product: "wow",
      channel: "retail",
      zone_ids: [2913],
      dbm_module_map_ids: [1308],
      tier: "Midnight Season 1"
    }
  end

  def bosses do
    [
      boss("Belo'ren, Child of Al'ar", 3182, 2739, 1308, 2913),
      boss("Midnight Falls", 3183, 2740, 1308, 2913)
    ]
  end

  def mechanics do
    [
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_241_291, "Dives", :avoidable, :damage_taken, [
        :wowanalyzer
      ]),
      mechanic(
        "Belo'ren, Child of Al'ar",
        3182,
        1_241_292,
        "Light Diver",
        :avoidable,
        :damage_taken,
        [:dbm, :wowanalyzer]
      ),
      mechanic(
        "Belo'ren, Child of Al'ar",
        3182,
        1_241_339,
        "Void Diver",
        :avoidable,
        :damage_taken,
        [:dbm, :wowanalyzer]
      ),
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_241_340, "Dives", :avoidable, :damage_taken, [
        :wowanalyzer
      ]),
      mechanic(
        "Belo'ren, Child of Al'ar",
        3182,
        1_242_792,
        "Incubation of Flames",
        :avoidable,
        :damage_taken,
        [:dbm]
      ),
      mechanic(
        "Belo'ren, Child of Al'ar",
        3182,
        1_246_709,
        "Death Drop",
        :avoidable,
        :damage_taken,
        [:dbm]
      ),
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_241_678, "Tank Cones", :tank_mechanic, :cast, [
        :wowanalyzer
      ]),
      mechanic(
        "Belo'ren, Child of Al'ar",
        3182,
        1_260_763,
        "Guardian's Edict",
        :tank_mechanic,
        :cast,
        [:dbm]
      ),
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_261_217, "Tank Cones", :tank_mechanic, :cast, [
        :wowanalyzer
      ]),
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_261_218, "Tank Cones", :tank_mechanic, :cast, [
        :wowanalyzer
      ]),
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_241_162, "Light Feather", :unknown, :cast, [
        :dbm
      ]),
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_241_163, "Void Feather", :unknown, :cast, [
        :dbm
      ]),
      mechanic(
        "Belo'ren, Child of Al'ar",
        3182,
        1_241_282,
        "Embers of Belo'ren",
        :unknown,
        :cast,
        [:dbm]
      ),
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_241_313, "Rebirth", :unknown, :cast, [:dbm]),
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_241_992, "Quills", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_242_091, "Quills", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic(
        "Belo'ren, Child of Al'ar",
        3182,
        1_242_515,
        "Voidlight Convergence",
        :unknown,
        :cast,
        [:dbm, :wowanalyzer]
      ),
      mechanic("Belo'ren, Child of Al'ar", 3182, 1_242_981, "Radiant Echoes", :unknown, :cast, [
        :dbm
      ]),
      mechanic("Midnight Falls", 3183, 1_251_331, "Dark Archangel", :avoidable, :damage_taken, [
        :wowanalyzer
      ]),
      mechanic("Midnight Falls", 3183, 1_253_915, "Heaven's Glaives", :avoidable, :damage_taken, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic(
        "Midnight Falls",
        3183,
        1_266_388,
        "Dark Constellation",
        :avoidable,
        :damage_taken,
        [:dbm]
      ),
      mechanic("Midnight Falls", 3183, 1_276_525, "Heaven & Hell", :avoidable, :damage_taken, [
        :wowanalyzer
      ]),
      mechanic("Midnight Falls", 3183, 1_279_420, "Dark Quasar", :avoidable, :damage_taken, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_284_528, "Galvanize", :avoidable, :damage_taken, [
        :wowanalyzer
      ]),
      mechanic(
        "Midnight Falls",
        3183,
        1_251_386,
        "Safeguard Prism",
        :interrupt,
        :interrupt_opportunity,
        [:dbm, :wowanalyzer]
      ),
      mechanic(
        "Midnight Falls",
        3183,
        1_284_931,
        "Termination Prism",
        :interrupt,
        :interrupt_opportunity,
        [:dbm, :wowanalyzer]
      ),
      mechanic("Midnight Falls", 3183, 1_281_184, "Criticality", :spread, :debuff_application, [
        :wowanalyzer
      ]),
      mechanic("Midnight Falls", 3183, 1_249_609, "Dark Rune", :unknown, :cast, [:wowanalyzer]),
      mechanic("Midnight Falls", 3183, 1_249_620, "Death's Dirge", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic("Midnight Falls", 3183, 1_249_796, "Shattered Sky", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_250_898, "Dark Archangel", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_253_031, "Glimmering", :unknown, :cast, [:wowanalyzer]),
      mechanic("Midnight Falls", 3183, 1_266_897, "Light Siphon", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_267_049, "Heaven's Lance", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_273_158, "Death's Requiem", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_275_539, "Severance", :unknown, :cast, [:wowanalyzer]),
      mechanic("Midnight Falls", 3183, 1_276_202, "Severance", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_279_512, "Starsplinters", :unknown, :cast, [:wowanalyzer]),
      mechanic("Midnight Falls", 3183, 1_281_123, "Dark Meltdown", :unknown, :cast, [:wowanalyzer]),
      mechanic("Midnight Falls", 3183, 1_281_194, "Dark Meltdown", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_282_043, "Into the Darkwell", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic("Midnight Falls", 3183, 1_282_047, "Into Darkwell", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_282_249, "Cosmic Fission", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_282_412, "Core Harvest", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_284_527, "Galvanize", :unknown, :cast, [:wowanalyzer]),
      mechanic("Midnight Falls", 3183, 1_284_980, "Grim Symphony", :unknown, :cast, [:dbm]),
      mechanic("Midnight Falls", 3183, 1_285_510, "Starsplinters", :unknown, :cast, [:wowanalyzer]),
      mechanic("Midnight Falls", 3183, 1_285_708, "Memory Game", :unknown, :cast, [:wowanalyzer])
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
