defmodule WeGoNext.GameData.SurvivalActions do
  @moduledoc """
  Retail defensive and consumable metadata used to gate survival projections.

  Cast and aura IDs are separate because the retail combat log frequently uses
  different IDs for the button press and the resulting buff.

  `base_cooldown_ms` and `charges` deliberately exclude talent modifiers.
  Talent-gated rows carry the ability's `talent_spell_id`; resolving that spell
  to the selected trait-node/entry tuples in `COMBATANT_INFO` belongs to the
  talent-loadout projection. An empty `spec_ids` list means the action is a
  universal consumable rather than a class ability.
  """

  @death_knight_specs [250, 251, 252]
  @druid_specs [102, 103, 104, 105]
  @evoker_specs [1467, 1468, 1473]
  @hunter_specs [253, 254, 255]
  @mage_specs [62, 63, 64]
  @monk_specs [268, 269, 270]
  @paladin_specs [65, 66, 70]
  @priest_specs [256, 257, 258]
  @rogue_specs [259, 260, 261]
  @shaman_specs [262, 263, 264]
  @warlock_specs [265, 266, 267]
  @warrior_specs [71, 72, 73]

  @defaults %{
    kind: :defensive,
    charges: 1,
    verified_retail: %{project_id: 1, build_major: 12},
    availability: :baseline,
    talent_spell_id: nil,
    shared_cooldown_group: nil,
    max_uses_per_combat: nil
  }

  # IDs were observed in local retail combat logs whose COMBAT_LOG_VERSION
  # headers report PROJECT_ID 1 and BUILD_VERSION 12.x. Cooldowns are the
  # unmodified retail tooltip values; talent reductions are intentionally not
  # folded into these base values.
  @actions Enum.map(
             [
               # Death Knight
               %{
                 key: :anti_magic_shell,
                 name: "Anti-Magic Shell",
                 cast_spell_ids: [48_707, 410_358, 444_740],
                 aura_spell_ids: [48_707, 410_358, 444_741],
                 base_cooldown_ms: 60_000,
                 category: :personal,
                 class_id: 6,
                 spec_ids: @death_knight_specs
               },
               %{
                 key: :icebound_fortitude,
                 name: "Icebound Fortitude",
                 cast_spell_ids: [48_792],
                 aura_spell_ids: [48_792],
                 base_cooldown_ms: 120_000,
                 category: :personal,
                 class_id: 6,
                 spec_ids: @death_knight_specs,
                 availability: :talent,
                 talent_spell_id: 48_792
               },
               %{
                 key: :death_pact,
                 name: "Death Pact",
                 cast_spell_ids: [48_743],
                 aura_spell_ids: [48_743],
                 base_cooldown_ms: 120_000,
                 category: :personal,
                 class_id: 6,
                 spec_ids: @death_knight_specs,
                 availability: :talent,
                 talent_spell_id: 48_743
               },
               %{
                 key: :lichborne,
                 name: "Lichborne",
                 cast_spell_ids: [49_039],
                 aura_spell_ids: [49_039],
                 base_cooldown_ms: 120_000,
                 category: :personal,
                 class_id: 6,
                 spec_ids: @death_knight_specs
               },
               %{
                 key: :vampiric_blood,
                 name: "Vampiric Blood",
                 cast_spell_ids: [55_233],
                 aura_spell_ids: [55_233],
                 base_cooldown_ms: 90_000,
                 category: :personal,
                 class_id: 6,
                 spec_ids: [250],
                 availability: :talent,
                 talent_spell_id: 55_233
               },
               %{
                 key: :dancing_rune_weapon,
                 name: "Dancing Rune Weapon",
                 cast_spell_ids: [49_028],
                 aura_spell_ids: [81_256],
                 base_cooldown_ms: 120_000,
                 category: :personal,
                 class_id: 6,
                 spec_ids: [250],
                 availability: :talent,
                 talent_spell_id: 49_028
               },
               %{
                 key: :anti_magic_zone,
                 name: "Anti-Magic Zone",
                 cast_spell_ids: [51_052],
                 aura_spell_ids: [145_629],
                 base_cooldown_ms: 240_000,
                 category: :external,
                 class_id: 6,
                 spec_ids: @death_knight_specs,
                 availability: :talent,
                 talent_spell_id: 51_052
               },

               # Demon Hunter
               %{
                 key: :blur,
                 name: "Blur",
                 cast_spell_ids: [198_589],
                 aura_spell_ids: [212_800],
                 base_cooldown_ms: 60_000,
                 category: :personal,
                 class_id: 12,
                 spec_ids: [577]
               },
               %{
                 key: :demon_spikes,
                 name: "Demon Spikes",
                 cast_spell_ids: [203_720],
                 aura_spell_ids: [203_819],
                 base_cooldown_ms: 20_000,
                 category: :personal,
                 class_id: 12,
                 spec_ids: [581]
               },
               %{
                 key: :darkness,
                 name: "Darkness",
                 cast_spell_ids: [196_718],
                 aura_spell_ids: [],
                 base_cooldown_ms: 300_000,
                 category: :external,
                 class_id: 12,
                 spec_ids: [577],
                 availability: :talent,
                 talent_spell_id: 196_718
               },

               # Druid
               %{
                 key: :barkskin,
                 name: "Barkskin",
                 cast_spell_ids: [22_812],
                 aura_spell_ids: [22_812],
                 base_cooldown_ms: 60_000,
                 category: :personal,
                 class_id: 11,
                 spec_ids: @druid_specs
               },
               %{
                 key: :survival_instincts,
                 name: "Survival Instincts",
                 cast_spell_ids: [61_336],
                 aura_spell_ids: [61_336],
                 base_cooldown_ms: 180_000,
                 category: :personal,
                 class_id: 11,
                 spec_ids: [104],
                 availability: :talent,
                 talent_spell_id: 61_336
               },
               %{
                 key: :frenzied_regeneration,
                 name: "Frenzied Regeneration",
                 cast_spell_ids: [22_842],
                 aura_spell_ids: [22_842],
                 base_cooldown_ms: 36_000,
                 category: :personal,
                 class_id: 11,
                 spec_ids: [104],
                 availability: :talent,
                 talent_spell_id: 22_842
               },
               %{
                 key: :ironbark,
                 name: "Ironbark",
                 cast_spell_ids: [102_342],
                 aura_spell_ids: [102_342],
                 base_cooldown_ms: 90_000,
                 category: :external,
                 class_id: 11,
                 spec_ids: [105],
                 availability: :talent,
                 talent_spell_id: 102_342
               },

               # Evoker
               %{
                 key: :obsidian_scales,
                 name: "Obsidian Scales",
                 cast_spell_ids: [363_916],
                 aura_spell_ids: [363_916],
                 base_cooldown_ms: 90_000,
                 category: :personal,
                 class_id: 13,
                 spec_ids: @evoker_specs,
                 availability: :talent,
                 talent_spell_id: 363_916
               },
               %{
                 key: :zephyr,
                 name: "Zephyr",
                 cast_spell_ids: [374_227],
                 aura_spell_ids: [374_227],
                 base_cooldown_ms: 120_000,
                 category: :external,
                 class_id: 13,
                 spec_ids: @evoker_specs,
                 availability: :talent,
                 talent_spell_id: 374_227
               },
               %{
                 key: :time_dilation,
                 name: "Time Dilation",
                 cast_spell_ids: [357_170],
                 aura_spell_ids: [357_170],
                 base_cooldown_ms: 60_000,
                 category: :external,
                 class_id: 13,
                 spec_ids: [1468],
                 availability: :talent,
                 talent_spell_id: 357_170
               },

               # Hunter
               %{
                 key: :aspect_of_the_turtle,
                 name: "Aspect of the Turtle",
                 cast_spell_ids: [186_265],
                 aura_spell_ids: [186_265],
                 base_cooldown_ms: 180_000,
                 category: :immunity,
                 class_id: 3,
                 spec_ids: @hunter_specs
               },
               %{
                 key: :survival_of_the_fittest,
                 name: "Survival of the Fittest",
                 cast_spell_ids: [264_735],
                 aura_spell_ids: [264_735],
                 base_cooldown_ms: 90_000,
                 category: :personal,
                 class_id: 3,
                 spec_ids: @hunter_specs,
                 availability: :talent,
                 talent_spell_id: 264_735
               },
               %{
                 key: :exhilaration,
                 name: "Exhilaration",
                 cast_spell_ids: [109_304],
                 aura_spell_ids: [],
                 base_cooldown_ms: 120_000,
                 category: :personal,
                 class_id: 3,
                 spec_ids: @hunter_specs
               },

               # Mage
               %{
                 key: :ice_block,
                 name: "Ice Block",
                 cast_spell_ids: [45_438],
                 aura_spell_ids: [45_438],
                 base_cooldown_ms: 240_000,
                 category: :immunity,
                 class_id: 8,
                 spec_ids: @mage_specs,
                 availability: :talent,
                 talent_spell_id: 45_438
               },
               %{
                 key: :greater_invisibility,
                 name: "Greater Invisibility",
                 cast_spell_ids: [110_959],
                 aura_spell_ids: [110_960],
                 base_cooldown_ms: 120_000,
                 category: :personal,
                 class_id: 8,
                 spec_ids: [62],
                 availability: :talent,
                 talent_spell_id: 110_959
               },
               %{
                 key: :prismatic_barrier,
                 name: "Prismatic Barrier",
                 cast_spell_ids: [235_450],
                 aura_spell_ids: [235_450],
                 base_cooldown_ms: 30_000,
                 category: :personal,
                 class_id: 8,
                 spec_ids: [62],
                 availability: :talent,
                 talent_spell_id: 235_450
               },
               %{
                 key: :ice_barrier,
                 name: "Ice Barrier",
                 cast_spell_ids: [11_426],
                 aura_spell_ids: [11_426],
                 base_cooldown_ms: 30_000,
                 category: :personal,
                 class_id: 8,
                 spec_ids: [64],
                 availability: :talent,
                 talent_spell_id: 11_426
               },
               %{
                 key: :alter_time,
                 name: "Alter Time",
                 cast_spell_ids: [342_245],
                 aura_spell_ids: [342_246],
                 base_cooldown_ms: 60_000,
                 category: :personal,
                 class_id: 8,
                 spec_ids: @mage_specs,
                 availability: :talent,
                 talent_spell_id: 342_245
               },

               # Monk
               %{
                 key: :fortifying_brew,
                 name: "Fortifying Brew",
                 cast_spell_ids: [115_203],
                 aura_spell_ids: [120_954],
                 base_cooldown_ms: 360_000,
                 category: :personal,
                 class_id: 10,
                 spec_ids: @monk_specs,
                 availability: :talent,
                 talent_spell_id: 115_203
               },
               %{
                 key: :touch_of_karma,
                 name: "Touch of Karma",
                 cast_spell_ids: [122_470],
                 aura_spell_ids: [122_470, 124_280, 125_174],
                 base_cooldown_ms: 90_000,
                 category: :personal,
                 class_id: 10,
                 spec_ids: [269]
               },

               # Paladin
               %{
                 key: :divine_shield,
                 name: "Divine Shield",
                 cast_spell_ids: [642],
                 aura_spell_ids: [642, 1_246_384],
                 base_cooldown_ms: 300_000,
                 category: :immunity,
                 class_id: 2,
                 spec_ids: @paladin_specs
               },
               %{
                 key: :divine_protection,
                 name: "Divine Protection",
                 cast_spell_ids: [498, 403_876],
                 aura_spell_ids: [498, 403_876],
                 base_cooldown_ms: 60_000,
                 category: :personal,
                 class_id: 2,
                 spec_ids: @paladin_specs
               },
               %{
                 key: :ardent_defender,
                 name: "Ardent Defender",
                 cast_spell_ids: [31_850],
                 aura_spell_ids: [31_850],
                 base_cooldown_ms: 90_000,
                 category: :personal,
                 class_id: 2,
                 spec_ids: [66],
                 availability: :talent,
                 talent_spell_id: 31_850
               },
               %{
                 key: :guardian_of_ancient_kings,
                 name: "Guardian of Ancient Kings",
                 cast_spell_ids: [86_659],
                 aura_spell_ids: [86_659, 393_108],
                 base_cooldown_ms: 180_000,
                 category: :personal,
                 class_id: 2,
                 spec_ids: [66],
                 availability: :talent,
                 talent_spell_id: 86_659
               },
               %{
                 key: :blessing_of_protection,
                 name: "Blessing of Protection",
                 cast_spell_ids: [1022],
                 aura_spell_ids: [1022],
                 base_cooldown_ms: 300_000,
                 category: :external,
                 class_id: 2,
                 spec_ids: @paladin_specs,
                 availability: :talent,
                 talent_spell_id: 1022
               },
               %{
                 key: :blessing_of_spellwarding,
                 name: "Blessing of Spellwarding",
                 cast_spell_ids: [204_018],
                 aura_spell_ids: [204_018],
                 base_cooldown_ms: 300_000,
                 category: :external,
                 class_id: 2,
                 spec_ids: [66],
                 availability: :talent,
                 talent_spell_id: 204_018
               },
               %{
                 key: :blessing_of_sacrifice,
                 name: "Blessing of Sacrifice",
                 cast_spell_ids: [6940],
                 aura_spell_ids: [6940],
                 base_cooldown_ms: 120_000,
                 category: :external,
                 class_id: 2,
                 spec_ids: @paladin_specs,
                 availability: :talent,
                 talent_spell_id: 6940
               },

               # Priest
               %{
                 key: :desperate_prayer,
                 name: "Desperate Prayer",
                 cast_spell_ids: [19_236],
                 aura_spell_ids: [19_236],
                 base_cooldown_ms: 90_000,
                 category: :personal,
                 class_id: 5,
                 spec_ids: @priest_specs,
                 availability: :talent,
                 talent_spell_id: 19_236
               },
               %{
                 key: :dispersion,
                 name: "Dispersion",
                 cast_spell_ids: [47_585],
                 aura_spell_ids: [47_585],
                 base_cooldown_ms: 120_000,
                 category: :immunity,
                 class_id: 5,
                 spec_ids: [258]
               },
               %{
                 key: :pain_suppression,
                 name: "Pain Suppression",
                 cast_spell_ids: [33_206],
                 aura_spell_ids: [33_206],
                 base_cooldown_ms: 180_000,
                 category: :external,
                 class_id: 5,
                 spec_ids: [256],
                 availability: :talent,
                 talent_spell_id: 33_206
               },
               %{
                 key: :guardian_spirit,
                 name: "Guardian Spirit",
                 cast_spell_ids: [47_788],
                 aura_spell_ids: [47_788],
                 base_cooldown_ms: 180_000,
                 category: :external,
                 class_id: 5,
                 spec_ids: [257],
                 availability: :talent,
                 talent_spell_id: 47_788
               },

               # Rogue
               %{
                 key: :feint,
                 name: "Feint",
                 cast_spell_ids: [1966],
                 aura_spell_ids: [1966],
                 base_cooldown_ms: 15_000,
                 category: :personal,
                 class_id: 4,
                 spec_ids: @rogue_specs
               },
               %{
                 key: :cloak_of_shadows,
                 name: "Cloak of Shadows",
                 cast_spell_ids: [31_224],
                 aura_spell_ids: [31_224],
                 base_cooldown_ms: 120_000,
                 category: :immunity,
                 class_id: 4,
                 spec_ids: @rogue_specs,
                 availability: :talent,
                 talent_spell_id: 31_224
               },
               %{
                 key: :evasion,
                 name: "Evasion",
                 cast_spell_ids: [5277],
                 aura_spell_ids: [5277],
                 base_cooldown_ms: 120_000,
                 category: :personal,
                 class_id: 4,
                 spec_ids: @rogue_specs,
                 availability: :talent,
                 talent_spell_id: 5277
               },
               %{
                 key: :crimson_vial,
                 name: "Crimson Vial",
                 cast_spell_ids: [185_311],
                 aura_spell_ids: [185_311],
                 base_cooldown_ms: 30_000,
                 category: :personal,
                 class_id: 4,
                 spec_ids: @rogue_specs
               },

               # Shaman
               %{
                 key: :astral_shift,
                 name: "Astral Shift",
                 cast_spell_ids: [108_271],
                 aura_spell_ids: [108_271],
                 base_cooldown_ms: 120_000,
                 category: :personal,
                 class_id: 7,
                 spec_ids: @shaman_specs,
                 availability: :talent,
                 talent_spell_id: 108_271
               },
               %{
                 key: :earth_elemental,
                 name: "Earth Elemental",
                 cast_spell_ids: [198_103],
                 aura_spell_ids: [198_103],
                 base_cooldown_ms: 180_000,
                 category: :personal,
                 class_id: 7,
                 spec_ids: @shaman_specs,
                 availability: :talent,
                 talent_spell_id: 198_103
               },

               # Warlock
               %{
                 key: :unending_resolve,
                 name: "Unending Resolve",
                 cast_spell_ids: [104_773],
                 aura_spell_ids: [104_773],
                 base_cooldown_ms: 180_000,
                 category: :personal,
                 class_id: 9,
                 spec_ids: @warlock_specs
               },
               %{
                 key: :dark_pact,
                 name: "Dark Pact",
                 cast_spell_ids: [108_416],
                 aura_spell_ids: [108_416],
                 base_cooldown_ms: 60_000,
                 category: :personal,
                 class_id: 9,
                 spec_ids: @warlock_specs,
                 availability: :talent,
                 talent_spell_id: 108_416
               },

               # Warrior
               %{
                 key: :spell_reflection,
                 name: "Spell Reflection",
                 cast_spell_ids: [23_920],
                 aura_spell_ids: [23_920, 385_391],
                 base_cooldown_ms: 25_000,
                 category: :personal,
                 class_id: 1,
                 spec_ids: @warrior_specs,
                 availability: :talent,
                 talent_spell_id: 23_920
               },
               %{
                 key: :die_by_the_sword,
                 name: "Die by the Sword",
                 cast_spell_ids: [118_038],
                 aura_spell_ids: [118_038],
                 base_cooldown_ms: 120_000,
                 category: :personal,
                 class_id: 1,
                 spec_ids: [71],
                 availability: :talent,
                 talent_spell_id: 118_038
               },
               %{
                 key: :enraged_regeneration,
                 name: "Enraged Regeneration",
                 cast_spell_ids: [184_364],
                 aura_spell_ids: [184_364],
                 base_cooldown_ms: 120_000,
                 category: :personal,
                 class_id: 1,
                 spec_ids: [72],
                 availability: :talent,
                 talent_spell_id: 184_364
               },
               %{
                 key: :shield_wall,
                 name: "Shield Wall",
                 cast_spell_ids: [871],
                 aura_spell_ids: [871],
                 base_cooldown_ms: 180_000,
                 category: :personal,
                 class_id: 1,
                 spec_ids: [73],
                 availability: :talent,
                 talent_spell_id: 871
               },
               %{
                 key: :ignore_pain,
                 name: "Ignore Pain",
                 cast_spell_ids: [190_456],
                 aura_spell_ids: [190_456],
                 base_cooldown_ms: 1000,
                 category: :personal,
                 class_id: 1,
                 spec_ids: [73],
                 availability: :talent,
                 talent_spell_id: 190_456
               },
               %{
                 key: :impending_victory,
                 name: "Impending Victory",
                 cast_spell_ids: [202_168],
                 aura_spell_ids: [],
                 base_cooldown_ms: 25_000,
                 category: :personal,
                 class_id: 1,
                 spec_ids: @warrior_specs,
                 availability: :talent,
                 talent_spell_id: 202_168
               },
               %{
                 key: :rallying_cry,
                 name: "Rallying Cry",
                 cast_spell_ids: [97_462],
                 aura_spell_ids: [97_463],
                 base_cooldown_ms: 180_000,
                 category: :external,
                 class_id: 1,
                 spec_ids: @warrior_specs,
                 availability: :talent,
                 talent_spell_id: 97_462
               },

               # Consumables are universal; an empty spec list means every spec.
               %{
                 key: :healthstone,
                 name: "Healthstone",
                 kind: :healthstone,
                 cast_spell_ids: [6262, 452_930],
                 aura_spell_ids: [],
                 base_cooldown_ms: 60_000,
                 category: :consumable,
                 class_id: nil,
                 spec_ids: [],
                 shared_cooldown_group: :healthstone,
                 max_uses_per_combat: 1
               },
               %{
                 key: :potent_healing_potion,
                 name: "Potent Healing Potion",
                 kind: :health_potion,
                 cast_spell_ids: [1_262_857],
                 aura_spell_ids: [],
                 base_cooldown_ms: 300_000,
                 category: :consumable,
                 class_id: nil,
                 spec_ids: [],
                 shared_cooldown_group: :combat_potion,
                 max_uses_per_combat: 1
               }
             ],
             &Map.merge(@defaults, &1)
           )

  @by_cast_id for action <- @actions,
                  spell_id <- action.cast_spell_ids,
                  into: %{},
                  do: {spell_id, action}

  @by_aura_id for action <- @actions,
                  spell_id <- action.aura_spell_ids,
                  into: %{},
                  do: {spell_id, action}

  @cast_ids MapSet.new(Map.keys(@by_cast_id))
  @aura_ids MapSet.new(Map.keys(@by_aura_id))

  def all, do: @actions
  def cast_ids, do: @cast_ids
  def aura_ids, do: @aura_ids

  def for_spec(spec_id) when is_integer(spec_id) do
    Enum.filter(@actions, &(&1.spec_ids == [] or spec_id in &1.spec_ids))
  end

  def for_spec(_spec_id), do: []

  def get_by_cast_id(spell_id) when is_integer(spell_id), do: Map.get(@by_cast_id, spell_id)
  def get_by_cast_id(_spell_id), do: nil

  def get_by_aura_id(spell_id) when is_integer(spell_id), do: Map.get(@by_aura_id, spell_id)
  def get_by_aura_id(_spell_id), do: nil
end
