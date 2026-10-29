defmodule WeGoNext.GameData.Dungeons.AlgetharAcademy do
  @moduledoc "Static data for Algethar Academy (MDT index 45)."

  def info do
    %{
      name: "Algethar Academy",
      slug: "algethar_academy",
      mdt_index: 45,
      map_id: 402,
      total_count: 460,
      floors: 1,
    }
  end

  def enemies do
    [
      %{
        name: "Corrupted Manafiend",
        id: 196_045,
        count: 5,
        health: 1_518_845,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 387_523, name: "Return to Book"},
          %{id: 388_862, name: "Surge", interruptible: true},
          %{id: 388_863, name: "Mana Void"},
          %{id: 388_866, name: "Mana Void"}
        ],
        positions: [
          %{x: 382.96, y: -407.14, sublevel: 1, group: 1},
          %{x: 364.82, y: -362.00, sublevel: 1, group: 2},
          %{x: 352.20, y: -368.76, sublevel: 1, group: 2},
          %{x: 319.68, y: -235.12, sublevel: 1, group: 10},
          %{x: 338.46, y: -235.40, sublevel: 1, group: 10},
          %{x: 356.54, y: -110.53, sublevel: 1, group: 14},
          %{x: 375.62, y: -110.10, sublevel: 1, group: 14},
          %{x: 248.40, y: -323.30, sublevel: 1, group: 7},
          %{x: 248.42, y: -306.18, sublevel: 1, group: 7},
          %{x: 285.92, y: -271.10, sublevel: 1, group: 8},
          %{x: 300.03, y: -268.42, sublevel: 1, group: 8}
        ],
      },
      %{
        name: "Spellbound Battleaxe",
        id: 196_577,
        count: 5,
        health: 1_670_730,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 387_523, name: "Return to Book"},
          %{id: 388_841, name: "Spellbound Weapon"},
          %{id: 1_270_098, name: "Spellbound Weapon"}
        ],
        positions: [
          %{x: 382.25, y: -392.01, sublevel: 1, group: 1},
          %{x: 360.73, y: -380.17, sublevel: 1, group: 2},
          %{x: 338.68, y: -219.43, sublevel: 1, group: 10},
          %{x: 317.91, y: -140.70, sublevel: 1, group: 11},
          %{x: 296.05, y: -255.89, sublevel: 1, group: 8},
          %{x: 230.53, y: -322.72, sublevel: 1, group: 7},
          %{x: 369.85, y: -399.19, sublevel: 1, group: 1},
          %{x: 240.50, y: -267.36, sublevel: 1, group: 9},
          %{x: 229.06, y: -274.32, sublevel: 1, group: 9},
          %{x: 251.95, y: -257.41, sublevel: 1, group: 9},
          %{x: 320.60, y: -219.60, sublevel: 1, group: 10},
          %{x: 340.50, y: -148.45, sublevel: 1, group: 11}
        ],
      },
      %{
        name: "Arcane Ravager",
        id: 196_671,
        count: 15,
        health: 3_645_228,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 388_940, name: "Vicious Ambush"},
          %{id: 388_942, name: "Vicious Ambush"},
          %{id: 388_957, name: "Riftbreath"},
          %{id: 388_958, name: "Riftbreath"},
          %{id: 388_976, name: "Riftbreath"},
          %{id: 388_982, name: "Vicious Ambush"},
          %{id: 388_984, name: "Vicious Ambush"}
        ],
        positions: [
          %{x: 324.20, y: -300.24, sublevel: 1, group: 3},
          %{x: 327.87, y: -154.75, sublevel: 1, group: 11},
          %{x: 366.87, y: -123.08, sublevel: 1, group: 14}
        ],
      },
      %{
        name: "Arcane Forager",
        id: 196_694,
        count: 4,
        health: 1_215_076,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 389_054, name: "Vicious Lunge"},
          %{id: 389_055, name: "Vicious Lunge"}
        ],
        positions: [
          %{x: 314.39, y: -312.03, sublevel: 1, group: 3},
          %{x: 309.39, y: -296.31, sublevel: 1, group: 3},
          %{x: 295.28, y: -333.74, sublevel: 1, group: 4},
          %{x: 306.14, y: -341.11, sublevel: 1, group: 4},
          %{x: 355.02, y: -285.82, sublevel: 1, group: 5},
          %{x: 356.75, y: -299.06, sublevel: 1, group: 5},
          %{x: 337.95, y: -264.12, sublevel: 1, group: 6},
          %{x: 329.46, y: -272.77, sublevel: 1, group: 6},
          %{x: 279.05, y: -131.17, sublevel: 1, group: 12},
          %{x: 277.82, y: -146.33, sublevel: 1, group: 12},
          %{x: 262.87, y: -142.28, sublevel: 1, group: 12},
          %{x: 265.24, y: -128.23, sublevel: 1, group: 12},
          %{x: 362.01, y: -168.79, sublevel: 1, group: 13},
          %{x: 367.24, y: -156.87, sublevel: 1, group: 13},
          %{x: 330.33, y: -86.41, sublevel: 1, group: 15},
          %{x: 313.90, y: -86.18, sublevel: 1, group: 15}
        ],
      },
      %{
        name: "Unruly Textbook",
        id: 196_044,
        count: 4,
        health: 1_215_076,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 387_523, name: "Return to Book"},
          %{id: 388_392, name: "Monotonous Lecture", interruptible: true, dispellable: true}
        ],
        positions: [
          %{x: 231.44, y: -305.45, sublevel: 1, group: 7},
          %{x: 282.73, y: -257.48, sublevel: 1, group: 8},
          %{x: 224.38, y: -261.47, sublevel: 1, group: 9},
          %{x: 236.63, y: -249.50, sublevel: 1, group: 9}
        ],
      },
      %{
        name: "Vexamus",
        id: 194_181,
        count: 0,
        health: 11_074_911,
        creature_type: "Elemental",
        is_boss: true,
        encounter_id: 2509,
        spells: [
          %{id: 385_958, name: "Arcane Expulsion"},
          %{id: 386_173, name: "Mana Bombs"},
          %{id: 386_181, name: "Mana Bomb"},
          %{id: 386_201, name: "Corrupted Mana"},
          %{id: 386_202, name: "Mana Bomb"},
          %{id: 387_691, name: "Arcane Orbs"},
          %{id: 388_537, name: "Arcane Fissure"},
          %{id: 388_546, name: "Arcane Fissure"},
          %{id: 388_651, name: "Arcane Fissure"}
        ],
        positions: [
          %{x: 182.84, y: -297.13, sublevel: 1}
        ],
      },
      %{
        name: "Guardian Sentry",
        id: 192_680,
        count: 18,
        health: 4_556_535,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 377_912, name: "Expel Intruders"},
          %{id: 377_991, name: "Storm Slash"},
          %{id: 378_003, name: "Deadly Winds"},
          %{id: 378_011, name: "Deadly Winds"}
        ],
        positions: [
          %{x: 542.24, y: -166.14, sublevel: 1}
        ],
      },
      %{
        name: "Territorial Eagle",
        id: 192_329,
        count: 2,
        health: 759_423,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 377_344, name: "Peck"},
          %{id: 377_389, name: "Raging Screech"}
        ],
        positions: [
          %{x: 511.60, y: -102.18, sublevel: 1, group: 16},
          %{x: 515.96, y: -124.68, sublevel: 1, group: 16},
          %{x: 492.13, y: -115.20, sublevel: 1, group: 16},
          %{x: 499.92, y: -125.31, sublevel: 1, group: 16},
          %{x: 522.79, y: -109.69, sublevel: 1, group: 16},
          %{x: 507.96, y: -114.46, sublevel: 1, group: 16},
          %{x: 475.34, y: -81.10, sublevel: 1, group: 17},
          %{x: 462.72, y: -70.09, sublevel: 1, group: 17},
          %{x: 452.21, y: -79.07, sublevel: 1, group: 17},
          %{x: 568.29, y: -70.85, sublevel: 1, group: 18},
          %{x: 555.40, y: -63.80, sublevel: 1, group: 18},
          %{x: 542.77, y: -68.36, sublevel: 1, group: 18},
          %{x: 497.08, y: -103.78, sublevel: 1, group: 16},
          %{x: 449.57, y: -65.83, sublevel: 1, group: 17},
          %{x: 477.94, y: -67.31, sublevel: 1, group: 17},
          %{x: 554.93, y: -77.32, sublevel: 1, group: 18}
        ],
      },
      %{
        name: "Alpha Eagle",
        id: 192_333,
        count: 15,
        health: 2_278_268,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 377_383, name: "Gust"},
          %{id: 377_389, name: "Raging Screech"},
          %{id: 1_276_632, name: "Raging Screech"}
        ],
        positions: [
          %{x: 462.07, y: -91.46, sublevel: 1, group: 17},
          %{x: 563.04, y: -90.07, sublevel: 1, group: 18},
          %{x: 539.96, y: -84.88, sublevel: 1, group: 18}
        ],
      },
      %{
        name: "Crawth",
        id: 191_736,
        count: 0,
        health: 15_821_301,
        creature_type: "Beast",
        is_boss: true,
        encounter_id: 2495,
        spells: [
          %{id: 181_089, name: "Encounter Event"},
          %{id: 376_997, name: "Savage Peck"},
          %{id: 377_004, name: "Deafening Screech"},
          %{id: 377_009, name: "Deafening Screech"},
          %{id: 377_034, name: "Overpowering Gust"},
          %{id: 1_276_752, name: "Ruinous Winds"},
          %{id: 1_285_508, name: "Blistering Fire"},
          %{id: 1_285_509, name: "Blistering Fire"}
        ],
        positions: [
          %{x: 512.69, y: -38.92, sublevel: 1}
        ],
      },
      %{
        name: "Aggravated Skitterfly",
        id: 197_406,
        count: 4,
        health: 1_215_076,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 390_938, name: "Agitation"},
          %{id: 390_942, name: "Darting Sting"},
          %{id: 390_944, name: "Darting Sting"}
        ],
        positions: [
          %{x: 502.03, y: -315.75, sublevel: 1, group: 19},
          %{x: 515.31, y: -321.73, sublevel: 1, group: 19},
          %{x: 513.53, y: -306.82, sublevel: 1, group: 19},
          %{x: 479.87, y: -383.14, sublevel: 1, group: 22},
          %{x: 482.23, y: -362.88, sublevel: 1, group: 22},
          %{x: 492.68, y: -375.48, sublevel: 1, group: 22}
        ],
      },
      %{
        name: "Vile Lasher",
        id: 197_219,
        count: 9,
        health: 2_733_921,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 390_912, name: "Detonation Seeds"},
          %{id: 390_915, name: "Detonation Seeds"},
          %{id: 390_918, name: "Seed Detonation"},
          %{id: 1_282_244, name: "Vile Bite"}
        ],
        positions: [
          %{x: 538.37, y: -301.75, sublevel: 1, group: 20},
          %{x: 544.29, y: -353.26, sublevel: 1, group: 21},
          %{x: 464.76, y: -317.20, sublevel: 1, group: 23}
        ],
      },
      %{
        name: "Hungry Lasher",
        id: 197_398,
        count: 2,
        health: 759_423,
        creature_type: "Elemental",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 591.08, y: -315.70, sublevel: 1, group: 20},
          %{x: 486.73, y: -282.98, sublevel: 1, group: 20},
          %{x: 580.15, y: -298.26, sublevel: 1, group: 20},
          %{x: 574.25, y: -312.20, sublevel: 1, group: 20},
          %{x: 496.06, y: -290.54, sublevel: 1, group: 20},
          %{x: 509.12, y: -287.91, sublevel: 1, group: 20},
          %{x: 499.69, y: -274.68, sublevel: 1, group: 20},
          %{x: 516.60, y: -273.95, sublevel: 1, group: 20},
          %{x: 551.71, y: -372.68, sublevel: 1, group: 21},
          %{x: 559.15, y: -345.17, sublevel: 1, group: 21},
          %{x: 529.21, y: -341.44, sublevel: 1, group: 21},
          %{x: 556.80, y: -331.15, sublevel: 1, group: 21},
          %{x: 541.64, y: -331.72, sublevel: 1, group: 21},
          %{x: 535.82, y: -366.95, sublevel: 1, group: 21},
          %{x: 560.71, y: -361.88, sublevel: 1, group: 21},
          %{x: 526.31, y: -357.48, sublevel: 1, group: 21},
          %{x: 480.68, y: -325.89, sublevel: 1, group: 23},
          %{x: 479.45, y: -306.15, sublevel: 1, group: 23},
          %{x: 470.92, y: -336.15, sublevel: 1, group: 23},
          %{x: 454.81, y: -338.21, sublevel: 1, group: 23},
          %{x: 449.85, y: -315.88, sublevel: 1, group: 23},
          %{x: 451.99, y: -301.74, sublevel: 1, group: 23},
          %{x: 466.31, y: -297.41, sublevel: 1, group: 23},
          %{x: 451.13, y: -327.51, sublevel: 1, group: 23}
        ],
      },
      %{
        name: "Overgrown Ancient",
        id: 196_482,
        count: 0,
        health: 9_492_781,
        creature_type: "Elemental",
        is_boss: true,
        encounter_id: 2512,
        spells: [
          %{id: 388_544, name: "Barkbreaker"},
          %{id: 388_623, name: "Branch Out"},
          %{id: 388_796, name: "Germinate"},
          %{id: 388_799, name: "Germinate"},
          %{id: 388_923, name: "Burst Forth"},
          %{id: 390_297, name: "Dormant"},
          %{id: 396_716, name: "Splinterbark"}
        ],
        positions: [
          %{x: 629.41, y: -362.80, sublevel: 1}
        ],
      },
      %{
        name: "Algeth'ar Echoknight",
        id: 196_200,
        count: 15,
        health: 2_733_921,
        creature_type: "Dragonkin",
        is_boss: false,
        spells: [
          %{id: 1_270_349, name: "Astral Whirlwind"},
          %{id: 1_270_356, name: "Arcane Smash"}
        ],
        positions: [
          %{x: 539.54, y: -477.87, sublevel: 1, group: 29},
          %{x: 521.51, y: -506.69, sublevel: 1, group: 34},
          %{x: 514.50, y: -521.32, sublevel: 1, group: 34},
          %{x: 509.81, y: -452.50, sublevel: 1, group: 28},
          %{x: 482.75, y: -532.74, sublevel: 1, group: 33},
          %{x: 559.59, y: -411.12, sublevel: 1, group: 38},
          %{x: 576.34, y: -425.28, sublevel: 1, group: 38}
        ],
      },
      %{
        name: "Spectral Invoker",
        id: 196_202,
        count: 5,
        health: 1_670_730,
        creature_type: "Dragonkin",
        is_boss: false,
        spells: [
          %{id: 1_279_627, name: "Arcane Bolt", interruptible: true}
        ],
        positions: [
          %{x: 507.57, y: -422.59, sublevel: 1, group: 27},
          %{x: 474.38, y: -445.73, sublevel: 1, group: 31},
          %{x: 522.66, y: -475.49, sublevel: 1, group: 29},
          %{x: 481.60, y: -483.46, sublevel: 1, group: 30},
          %{x: 466.31, y: -488.73, sublevel: 1, group: 30},
          %{x: 459.69, y: -459.50, sublevel: 1, group: 31},
          %{x: 443.82, y: -526.96, sublevel: 1, group: 32},
          %{x: 450.92, y: -512.95, sublevel: 1, group: 32},
          %{x: 477.04, y: -547.40, sublevel: 1, group: 33},
          %{x: 494.11, y: -544.87, sublevel: 1, group: 33},
          %{x: 525.33, y: -427.22, sublevel: 1, group: 27},
          %{x: 435.04, y: -514.75, sublevel: 1, group: 32}
        ],
      },
      %{
        name: "Echo of Doragosa",
        id: 190_609,
        count: 0,
        health: 14_239_171,
        creature_type: "Dragonkin",
        is_boss: true,
        encounter_id: 2514,
        spells: [
          %{id: 373_326, name: "Arcane Missiles"},
          %{id: 374_343, name: "Energy Bomb"},
          %{id: 374_350, name: "Energy Bomb", dispellable: true},
          %{id: 374_352, name: "Energy Bomb"},
          %{id: 388_822, name: "Power Vacuum"},
          %{id: 439_488, name: "Unleash Energy"},
          %{id: 1_279_418, name: "Arcane Rift"},
          %{id: 1_282_251, name: "Astral Blast"},
          %{id: 1_282_252, name: "Astral Blast"}
        ],
        positions: [
          %{x: 560.17, y: -534.71, sublevel: 1}
        ],
      },
    ]
  end

  def interruptible_spells do
    enemies()
    |> Enum.flat_map(fn enemy ->
      enemy.spells
      |> Enum.filter(& &1[:interruptible])
      |> Enum.map(&Map.put(&1, :mob_name, enemy.name))
    end)
  end

  def bosses do
    Enum.filter(enemies(), & &1.is_boss)
  end

  def trash do
    Enum.reject(enemies(), & &1.is_boss)
  end
end
