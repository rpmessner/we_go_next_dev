defmodule WeGoNext.GameData.Dungeons.WindrunnerSpire do
  @moduledoc "Static data for Windrunner Spire (MDT index 152)."

  def info do
    %{
      name: "Windrunner Spire",
      slug: "windrunner_spire",
      mdt_index: 152,
      map_id: 557,
      total_count: 591,
      floors: 1,
    }
  end

  def enemies do
    [
      %{
        name: "Restless Steward",
        id: 232_070,
        count: 7,
        health: 1_366_961,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1_216_135, name: "Spirit Bolt", interruptible: true},
          %{id: 1_216_298, name: "Soul Torment", dispellable: true},
          %{id: 1_253_700, name: "Soul Torment"}
        ],
        positions: [
          %{x: 86.93, y: -154.12, sublevel: 1, group: 2},
          %{x: 90.70, y: -177.88, sublevel: 1, group: 1},
          %{x: 110.16, y: -73.72, sublevel: 1, group: 7},
          %{x: 271.29, y: -104.11, sublevel: 1, group: 8},
          %{x: 499.82, y: -202.54, sublevel: 1, group: 16},
          %{x: 110.13, y: -262.28, sublevel: 1, group: 30}
        ],
      },
      %{
        name: "Dutiful Groundskeeper",
        id: 232_071,
        count: 4,
        health: 1_670_730,
        creature_type: "Undead",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 81.59, y: -146.57, sublevel: 1, group: 2},
          %{x: 85.70, y: -185.63, sublevel: 1, group: 1},
          %{x: 56.43, y: -189.75, sublevel: 1, group: 5},
          %{x: 49.46, y: -183.28, sublevel: 1, group: 5},
          %{x: 48.47, y: -152.93, sublevel: 1, group: 6},
          %{x: 55.43, y: -145.47, sublevel: 1, group: 6},
          %{x: 119.61, y: -64.87, sublevel: 1, group: 7},
          %{x: 101.70, y: -64.37, sublevel: 1, group: 7},
          %{x: 101.70, y: -83.78, sublevel: 1, group: 7},
          %{x: 119.11, y: -83.78, sublevel: 1, group: 7},
          %{x: 271.60, y: -114.37, sublevel: 1, group: 8},
          %{x: 349.02, y: -104.42, sublevel: 1, group: 10},
          %{x: 349.17, y: -114.45, sublevel: 1, group: 10},
          %{x: 304.56, y: -79.24, sublevel: 1, group: 9},
          %{x: 493.16, y: -197.50, sublevel: 1, group: 16},
          %{x: 478.77, y: -126.43, sublevel: 1},
          %{x: 492.04, y: -126.63, sublevel: 1},
          %{x: 463.15, y: -103.73, sublevel: 1, group: 23},
          %{x: 451.21, y: -89.40, sublevel: 1, group: 22},
          %{x: 470.39, y: -62.63, sublevel: 1, group: 24},
          %{x: 500.43, y: -62.43, sublevel: 1, group: 25},
          %{x: 100.70, y: -249.94, sublevel: 1, group: 30},
          %{x: 122.59, y: -249.94, sublevel: 1, group: 30},
          %{x: 122.10, y: -274.82, sublevel: 1, group: 30},
          %{x: 100.70, y: -275.81, sublevel: 1, group: 30}
        ],
      },
      %{
        name: "Spellguard Magus",
        id: 232_113,
        count: 15,
        health: 2_126_383,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1_216_250, name: "Arcane Salvo"},
          %{id: 1_216_253, name: "Arcane Salvo"},
          %{id: 1_253_683, name: "Spellguard's Protection"},
          %{id: 1_253_686, name: "Spellguard's Protection"}
        ],
        positions: [
          %{x: 70.24, y: -181.39, sublevel: 1, group: 4},
          %{x: 69.86, y: -155.92, sublevel: 1, group: 3}
        ],
      },
      %{
        name: "Windrunner Soldier",
        id: 232_116,
        count: 5,
        health: 1_670_730,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1_216_462, name: "Precise Cut"}
        ],
        positions: [
          %{x: 114.76, y: -471.87, sublevel: 1, group: 31},
          %{x: 161.90, y: -453.42, sublevel: 1, group: 34},
          %{x: 161.40, y: -479.79, sublevel: 1, group: 33},
          %{x: 122.70, y: -495.76, sublevel: 1, group: 32},
          %{x: 590.25, y: -501.68, sublevel: 1, group: 43},
          %{x: 538.33, y: -478.75, sublevel: 1, group: 45},
          %{x: 536.16, y: -488.79, sublevel: 1, group: 45},
          %{x: 495.36, y: -488.93, sublevel: 1, group: 46},
          %{x: 498.84, y: -498.65, sublevel: 1, group: 46},
          %{x: 573.35, y: -392.03, sublevel: 1, group: 53},
          %{x: 527.80, y: -403.61, sublevel: 1, group: 51},
          %{x: 530.07, y: -414.02, sublevel: 1, group: 51},
          %{x: 491.40, y: -387.10, sublevel: 1, group: 50},
          %{x: 487.32, y: -397.28, sublevel: 1, group: 50}
        ],
      },
      %{
        name: "Fervent Apothecary",
        id: 232_173,
        count: 5,
        health: 1_366_961,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 473_644, name: "Phial Toss"},
          %{id: 473_647, name: "Phial Toss"},
          %{id: 473_649, name: "Shattered Phial"}
        ],
        positions: [
          %{x: 109.68, y: -463.74, sublevel: 1, group: 31},
          %{x: 133.12, y: -346.77, sublevel: 1, group: 36},
          %{x: 317.33, y: -360.76, sublevel: 1, group: 37},
          %{x: 308.48, y: -397.49, sublevel: 1, group: 38},
          %{x: 336.44, y: -427.76, sublevel: 1, group: 40},
          %{x: 308.08, y: -454.72, sublevel: 1, group: 41}
        ],
      },
      %{
        name: "Ardent Cutthroat",
        id: 232_171,
        count: 6,
        health: 1_518_845,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 473_794, name: "Poison Blades", interruptible: true},
          %{id: 473_795, name: "Poison Blades"},
          %{id: 473_864, name: "Shadowrive"},
          %{id: 473_868, name: "Shadowrive"}
        ],
        positions: [
          %{x: 119.96, y: -462.93, sublevel: 1, group: 31},
          %{x: 156.92, y: -488.25, sublevel: 1, group: 33},
          %{x: 128.07, y: -385.27, sublevel: 1, group: 36},
          %{x: 121.89, y: -347.11, sublevel: 1, group: 36},
          %{x: 286.77, y: -348.95, sublevel: 1, group: 37},
          %{x: 316.12, y: -371.34, sublevel: 1, group: 37},
          %{x: 297.32, y: -398.62, sublevel: 1, group: 38},
          %{x: 327.07, y: -421.64, sublevel: 1, group: 40},
          %{x: 326.52, y: -432.79, sublevel: 1, group: 40},
          %{x: 297.51, y: -454.24, sublevel: 1, group: 41}
        ],
      },
      %{
        name: "Zealous Reaver",
        id: 232_232,
        count: 4,
        health: 1_670_730,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 473_640, name: "Fierce Slash"}
        ],
        positions: [
          %{x: 127.03, y: -337.25, sublevel: 1, group: 36},
          %{x: 117.12, y: -426.56, sublevel: 1, group: 35},
          %{x: 155.93, y: -444.47, sublevel: 1, group: 34},
          %{x: 133.54, y: -495.29, sublevel: 1, group: 32},
          %{x: 272.34, y: -418.10, sublevel: 1, group: 39},
          %{x: 272.34, y: -435.02, sublevel: 1, group: 39}
        ],
      },
      %{
        name: "Devoted Woebringer",
        id: 232_175,
        count: 15,
        health: 2_126_383,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 473_657, name: "Shadow Bolt", interruptible: true},
          %{id: 473_663, name: "Pulsing Shriek", interruptible: true},
          %{id: 473_668, name: "Pulsing Shriek"},
          %{id: 473_672, name: "Pulsing Shriek"}
        ],
        positions: [
          %{x: 136.40, y: -430.14, sublevel: 1, group: 35},
          %{x: 303.97, y: -407.84, sublevel: 1, group: 38}
        ],
      },
      %{
        name: "Flesh Behemoth",
        id: 232_176,
        count: 20,
        health: 3_948_997,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 473_776, name: "Fetid Spew"},
          %{id: 473_786, name: "Fetid Spew"},
          %{id: 473_789, name: "Fetid Bile"},
          %{id: 1_277_799, name: "Brutal Chop"}
        ],
        positions: [
          %{x: 286.30, y: -369.95, sublevel: 1, group: 37}
        ],
      },
      %{
        name: "Territorial Dragonhawk",
        id: 232_056,
        count: 7,
        health: 1_366_961,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1_216_848, name: "Fire Spit"},
          %{id: 1_216_860, name: "Bolstering Flames", dispellable: true},
          %{id: 1_266_745, name: "Fire Spit"}
        ],
        positions: [
          %{x: 279.99, y: -109.02, sublevel: 1, group: 8},
          %{x: 313.26, y: -75.19, sublevel: 1, group: 9},
          %{x: 358.25, y: -108.73, sublevel: 1, group: 10},
          %{x: 536.62, y: -140.51, sublevel: 1, group: 28},
          %{x: 545.45, y: -137.05, sublevel: 1, group: 28}
        ],
      },
      %{
        name: "Spindleweb Hatchling",
        id: 234_673,
        count: 1,
        health: 303_769,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1_216_834, name: "Acidic Demise"}
        ],
        positions: [
          %{x: 324.20, y: -151.43, sublevel: 1, group: 11},
          %{x: 316.37, y: -151.38, sublevel: 1, group: 11},
          %{x: 320.41, y: -144.85, sublevel: 1, group: 11},
          %{x: 313.39, y: -182.56, sublevel: 1, group: 12},
          %{x: 325.72, y: -181.54, sublevel: 1, group: 12},
          %{x: 328.17, y: -188.60, sublevel: 1, group: 12},
          %{x: 311.96, y: -189.82, sublevel: 1, group: 12},
          %{x: 319.59, y: -178.98, sublevel: 1, group: 12},
          %{x: 316.81, y: -229.93, sublevel: 1, group: 13},
          %{x: 316.26, y: -236.96, sublevel: 1, group: 13},
          %{x: 323.32, y: -236.94, sublevel: 1, group: 13},
          %{x: 323.98, y: -230.10, sublevel: 1, group: 13},
          %{x: 304.57, y: -214.50, sublevel: 1},
          %{x: 329.57, y: -220.33, sublevel: 1},
          %{x: 334.99, y: -211.54, sublevel: 1},
          %{x: 480.34, y: -248.25, sublevel: 1, group: 14},
          %{x: 487.53, y: -249.02, sublevel: 1, group: 14},
          %{x: 481.29, y: -239.15, sublevel: 1, group: 14},
          %{x: 489.29, y: -240.52, sublevel: 1, group: 14},
          %{x: 490.40, y: -271.45, sublevel: 1},
          %{x: 493.89, y: -267.12, sublevel: 1},
          %{x: 469.47, y: -271.52, sublevel: 1},
          %{x: 462.35, y: -259.43, sublevel: 1},
          %{x: 463.00, y: -253.11, sublevel: 1},
          %{x: 484.05, y: -207.72, sublevel: 1, group: 15},
          %{x: 482.94, y: -214.73, sublevel: 1, group: 15},
          %{x: 471.00, y: -209.86, sublevel: 1, group: 15},
          %{x: 476.01, y: -214.46, sublevel: 1, group: 15},
          %{x: 502.65, y: -231.26, sublevel: 1},
          %{x: 464.84, y: -235.09, sublevel: 1},
          %{x: 461.28, y: -228.39, sublevel: 1},
          %{x: 461.43, y: -198.08, sublevel: 1},
          %{x: 467.25, y: -191.96, sublevel: 1},
          %{x: 505.40, y: -192.80, sublevel: 1},
          %{x: 501.73, y: -188.63, sublevel: 1},
          %{x: 512.60, y: -157.58, sublevel: 1},
          %{x: 507.59, y: -162.21, sublevel: 1},
          %{x: 505.67, y: -133.39, sublevel: 1},
          %{x: 466.41, y: -130.06, sublevel: 1},
          %{x: 465.91, y: -167.91, sublevel: 1},
          %{x: 460.90, y: -158.81, sublevel: 1}
        ],
      },
      %{
        name: "Creeping Spindleweb",
        id: 232_067,
        count: 7,
        health: 1_518_845,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1_216_822, name: "Poison Spray"},
          %{id: 1_216_825, name: "Poison Spray"},
          %{id: 1_216_834, name: "Acidic Demise"}
        ],
        positions: [
          %{x: 319.61, y: -187.63, sublevel: 1, group: 12},
          %{x: 485.05, y: -244.01, sublevel: 1, group: 14},
          %{x: 477.95, y: -208.11, sublevel: 1, group: 15}
        ],
      },
      %{
        name: "Apex Lynx",
        id: 232_063,
        count: 15,
        health: 2_582_037,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1_216_985, name: "Puncturing Bite"},
          %{id: 1_217_010, name: "Ferocious Pounce"},
          %{id: 1_217_021, name: "Ferocious Pounce"}
        ],
        positions: [
          %{x: 484.75, y: -159.82, sublevel: 1, group: 17}
        ],
      },
      %{
        name: "Pesty Lashling",
        id: 238_099,
        count: 1,
        health: 303_769,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 1_277_761, name: "Sporecharged"}
        ],
        positions: [
          %{x: 425.12, y: -145.73, sublevel: 1, group: 19},
          %{x: 420.59, y: -141.24, sublevel: 1, group: 19},
          %{x: 419.59, y: -148.01, sublevel: 1, group: 19},
          %{x: 428.95, y: -156.96, sublevel: 1, group: 18},
          %{x: 425.76, y: -160.74, sublevel: 1, group: 18},
          %{x: 424.37, y: -165.72, sublevel: 1, group: 18},
          %{x: 442.28, y: -133.48, sublevel: 1, group: 21},
          %{x: 442.28, y: -128.11, sublevel: 1, group: 21},
          %{x: 423.57, y: -118.55, sublevel: 1, group: 20},
          %{x: 425.76, y: -124.13, sublevel: 1, group: 20},
          %{x: 429.34, y: -119.55, sublevel: 1, group: 20},
          %{x: 445.24, y: -94.18, sublevel: 1, group: 22},
          %{x: 455.98, y: -83.63, sublevel: 1, group: 22},
          %{x: 457.58, y: -114.87, sublevel: 1, group: 23},
          %{x: 461.83, y: -110.43, sublevel: 1, group: 23},
          %{x: 469.91, y: -102.34, sublevel: 1, group: 23},
          %{x: 476.48, y: -100.34, sublevel: 1, group: 23},
          %{x: 468.32, y: -109.30, sublevel: 1, group: 23},
          %{x: 466.80, y: -68.60, sublevel: 1, group: 24},
          %{x: 470.58, y: -55.07, sublevel: 1, group: 24},
          %{x: 494.86, y: -54.08, sublevel: 1, group: 25},
          %{x: 493.27, y: -60.05, sublevel: 1, group: 25},
          %{x: 508.40, y: -65.62, sublevel: 1, group: 25},
          %{x: 504.41, y: -70.39, sublevel: 1, group: 25},
          %{x: 475.56, y: -58.45, sublevel: 1, group: 24},
          %{x: 502.91, y: -106.38, sublevel: 1, group: 26},
          %{x: 508.56, y: -109.50, sublevel: 1, group: 26},
          %{x: 514.59, y: -112.89, sublevel: 1, group: 26},
          %{x: 503.48, y: -111.91, sublevel: 1, group: 26},
          %{x: 508.82, y: -115.71, sublevel: 1, group: 26},
          %{x: 526.45, y: -91.23, sublevel: 1, group: 27},
          %{x: 532.96, y: -93.91, sublevel: 1, group: 27},
          %{x: 540.61, y: -98.12, sublevel: 1, group: 27},
          %{x: 529.13, y: -97.74, sublevel: 1, group: 27},
          %{x: 534.47, y: -100.13, sublevel: 1, group: 27},
          %{x: 540.99, y: -127.21, sublevel: 1, group: 28},
          %{x: 534.49, y: -129.50, sublevel: 1, group: 28},
          %{x: 527.60, y: -134.09, sublevel: 1, group: 28},
          %{x: 529.13, y: -139.84, sublevel: 1, group: 28},
          %{x: 530.66, y: -147.11, sublevel: 1, group: 28}
        ],
      },
      %{
        name: "Bloated Lasher",
        id: 236_894,
        count: 17,
        health: 3_341_459,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 1_216_819, name: "Fungal Bolt", interruptible: true},
          %{id: 1_216_963, name: "Spore Dispersal"}
        ],
        positions: [
          %{x: 504.82, y: -92.00, sublevel: 1}
        ],
      },
      %{
        name: "Scouting Trapper",
        id: 238_049,
        count: 5,
        health: 1_380_770,
        creature_type: "Undead",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 489.18, y: -167.60, sublevel: 1, group: 17},
          %{x: 481.29, y: -167.93, sublevel: 1, group: 17},
          %{x: 507.82, y: -147.97, sublevel: 1}
        ],
      },
      %{
        name: "Swiftshot Archer",
        id: 232_119,
        count: 7,
        health: 1_366_961,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1_216_419, name: "Shoot"},
          %{id: 1_216_449, name: "Arrow Rain"},
          %{id: 1_216_454, name: "Arrow Rain"}
        ],
        positions: [
          %{x: 582.17, y: -506.92, sublevel: 1, group: 43},
          %{x: 503.14, y: -507.38, sublevel: 1, group: 46},
          %{x: 508.93, y: -502.45, sublevel: 1, group: 46},
          %{x: 501.35, y: -386.65, sublevel: 1, group: 50},
          %{x: 492.98, y: -406.55, sublevel: 1, group: 50},
          %{x: 574.61, y: -401.35, sublevel: 1, group: 53}
        ],
      },
      %{
        name: "Phalanx Breaker",
        id: 232_122,
        count: 15,
        health: 2_430_152,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 471_643, name: "Interrupting Screech"},
          %{id: 471_648, name: "Break Ranks"},
          %{id: 471_650, name: "Break Ranks"}
        ],
        positions: [
          %{x: 566.50, y: -486.00, sublevel: 1, group: 44},
          %{x: 507.45, y: -490.52, sublevel: 1, group: 46},
          %{x: 497.73, y: -396.60, sublevel: 1, group: 50},
          %{x: 552.68, y: -404.97, sublevel: 1, group: 52}
        ],
      },
      %{
        name: "Loyal Worg",
        id: 232_283,
        count: 5,
        health: 1_518_845,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1_253_739, name: "Shred Flesh"}
        ],
        positions: [
          %{x: 470.65, y: -425.98, sublevel: 1, group: 54},
          %{x: 502.64, y: -462.75, sublevel: 1, group: 57},
          %{x: 476.70, y: -443.81, sublevel: 1, group: 55},
          %{x: 522.16, y: -445.55, sublevel: 1, group: 59},
          %{x: 559.87, y: -450.48, sublevel: 1, group: 60}
        ],
      },
      %{
        name: "Lingering Marauder",
        id: 232_147,
        count: 6,
        health: 1_670_730,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1_216_637, name: "Gore Whirl"},
          %{id: 1_216_643, name: "Gore Whirl"}
        ],
        positions: [
          %{x: 486.90, y: -468.92, sublevel: 1, group: 56},
          %{x: 478.51, y: -424.53, sublevel: 1, group: 54},
          %{x: 559.62, y: -440.09, sublevel: 1, group: 60},
          %{x: 446.93, y: -453.77, sublevel: 1, group: 49}
        ],
      },
      %{
        name: "Spectral Axethrower",
        id: 232_148,
        count: 7,
        health: 1_366_961,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 468_659, name: "Throw Axe"}
        ],
        positions: [
          %{x: 408.98, y: -446.85, sublevel: 1, group: 47},
          %{x: 529.10, y: -440.67, sublevel: 1, group: 59},
          %{x: 529.50, y: -450.37, sublevel: 1, group: 59},
          %{x: 569.79, y: -450.17, sublevel: 1, group: 60},
          %{x: 569.08, y: -438.71, sublevel: 1, group: 60}
        ],
      },
      %{
        name: "Phantasmal Mystic",
        id: 232_146,
        count: 15,
        health: 2_430_152,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1_216_459, name: "Ephemeral Bloodlust"},
          %{id: 1_216_592, name: "Chain Lightning", interruptible: true},
          %{id: 1_270_618, name: "Flame Nova"}
        ],
        positions: [
          %{x: 503.84, y: -442.56, sublevel: 1, group: 58},
          %{x: 578.81, y: -444.60, sublevel: 1, group: 60}
        ],
      },
      %{
        name: "Emberdawn",
        id: 231_606,
        count: 0,
        health: 11_650_806,
        creature_type: "Beast",
        is_boss: true,
        encounter_id: 2656,
        spells: [
          %{id: 465_904, name: "Burning Gale"},
          %{id: 466_064, name: "Searing Beak"},
          %{id: 466_091, name: "Searing Beak"},
          %{id: 466_556, name: "Flaming Updraft"},
          %{id: 466_559, name: "Flaming Updraft"},
          %{id: 467_040, name: "Burning Gale"},
          %{id: 1_217_763, name: "Fire Breath"},
          %{id: 1_217_795, name: "Burning Gale"},
          %{id: 1_252_548, name: "Fiery Landing"}
        ],
        positions: [
          %{x: 651.17, y: -146.65, sublevel: 1, group: 29}
        ],
      },
      %{
        name: "Kalis",
        id: 231_626,
        count: 0,
        health: 7_910_651,
        creature_type: "Undead",
        is_boss: true,
        encounter_id: 2656,
        spells: [
          %{id: 472_724, name: "Shadow Bolt", interruptible: true},
          %{id: 472_736, name: "Debilitating Shriek"},
          %{id: 474_105, name: "Curse of Darkness"},
          %{id: 1_219_491, name: "Debilitating Shriek"},
          %{id: 1_219_551, name: "Broken Bond"}
        ],
        positions: [
          %{x: 285.66, y: -507.04, sublevel: 1, group: 42}
        ],
      },
      %{
        name: "Latch",
        id: 231_629,
        count: 0,
        health: 9_176_355,
        creature_type: "Undead",
        is_boss: true,
        encounter_id: 2656,
        spells: [
          %{id: 472_745, name: "Splattering Spew"},
          %{id: 472_758, name: "Splattering Spew"},
          %{id: 472_777, name: "Gunk Splatter"},
          %{id: 472_795, name: "Heaving Yank"},
          %{id: 472_888, name: "Bone Hack"},
          %{id: 474_065, name: "Bone Hack"},
          %{id: 474_075, name: "Heaving Chop"},
          %{id: 1_219_551, name: "Broken Bond"},
          %{id: 1_282_272, name: "Splattered"}
        ],
        positions: [
          %{x: 321.04, y: -506.54, sublevel: 1, group: 42}
        ],
      },
      %{
        name: "Commander Kroluk",
        id: 231_631,
        count: 0,
        health: 9_492_781,
        creature_type: "Undead",
        is_boss: true,
        encounter_id: 2656,
        spells: [
          %{id: 467_620, name: "Rampage"},
          %{id: 467_621, name: "Rampage"},
          %{id: 468_221, name: "Rallying Bellow"},
          %{id: 468_924, name: "Bladestorm"},
          %{id: 470_963, name: "Bladestorm"},
          %{id: 471_038, name: "Bladestorm"},
          %{id: 472_043, name: "Rallying Bellow"},
          %{id: 472_053, name: "Reckless Leap"},
          %{id: 472_054, name: "Reckless Leap"},
          %{id: 472_081, name: "Reckless Leap"},
          %{id: 1_214_874, name: "Violent Manifestation"},
          %{id: 1_250_851, name: "Shield Wall"},
          %{id: 1_253_026, name: "Intimidating Shout"},
          %{id: 1_253_270, name: "Reckless Leap"},
          %{id: 1_253_272, name: "Intimidating Shout"},
          %{id: 1_271_676, name: "Bladestorm"},
          %{id: 1_283_335, name: "Rampage"},
          %{id: 1_283_357, name: "Falling Rubble"}
        ],
        positions: [
          %{x: 624.42, y: -448.38, sublevel: 1}
        ],
      },
      %{
        name: "Restless Heart",
        id: 231_636,
        count: 0,
        health: 12_657_041,
        creature_type: "Aberration",
        is_boss: true,
        encounter_id: 2656,
        spells: [
          %{id: 468_429, name: "Bullseye Windblast"},
          %{id: 468_442, name: "Billowing Wind"},
          %{id: 472_556, name: "Arrow Rain"},
          %{id: 472_662, name: "Tempest Slash"},
          %{id: 472_672, name: "Bolt Gale"},
          %{id: 474_528, name: "Bolt Gale"},
          %{id: 1_216_042, name: "Squall Leap"},
          %{id: 1_253_977, name: "Turbulent Arrows"},
          %{id: 1_253_978, name: "Gust Shot"},
          %{id: 1_253_986, name: "Gust Shot"},
          %{id: 1_283_371, name: "Squall Leap"}
        ],
        positions: [
          %{x: 680.89, y: -304.66, sublevel: 1}
        ],
      },
      %{
        name: "Flaming Updraft",
        id: 232_118,
        count: 0,
        health: 253_141,
        creature_type: "Not specified",
        is_boss: false,
        spells: [
          %{id: 465_957, name: "Ignited Embers"},
          %{id: 467_120, name: "Ignited Embers"},
          %{id: 470_212, name: "Flaming Twisters"},
          %{id: 472_118, name: "Ignited Embers"}
        ],
        positions: [
          %{x: 665.86, y: -160.99, sublevel: 1, group: 29},
          %{x: 672.22, y: -149.91, sublevel: 1, group: 29},
          %{x: 670.69, y: -137.66, sublevel: 1, group: 29}
        ],
      },
      %{
        name: "Phalanx Breaker",
        id: 232_121,
        count: 0,
        health: 157_503,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1_282_478, name: "Melee"}
        ],
        positions: [
          %{x: 562.67, y: -497.86, sublevel: 1, group: 44},
          %{x: 518.57, y: -496.65, sublevel: 1, group: 46},
          %{x: 504.08, y: -407.73, sublevel: 1, group: 50},
          %{x: 549.04, y: -394.96, sublevel: 1, group: 52}
        ],
      },
      %{
        name: "Haunting Grunt",
        id: 258_868,
        count: 4,
        health: 131_251,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 467_815, name: "Intercepting Charge"}
        ],
        positions: [
          %{x: 446.25, y: -441.06, sublevel: 1, group: 49},
          %{x: 416.47, y: -457.11, sublevel: 1, group: 47},
          %{x: 415.57, y: -437.20, sublevel: 1, group: 47},
          %{x: 509.26, y: -459.92, sublevel: 1, group: 57},
          %{x: 484.63, y: -441.36, sublevel: 1, group: 55},
          %{x: 478.91, y: -470.53, sublevel: 1, group: 56}
        ],
      },
      %{
        name: "Scouting Trapper",
        id: 250_883,
        count: 2,
        health: 1_518_845,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1_219_224, name: "Freezing Trap"},
          %{id: 1_219_266, name: "Freezing Trap"}
        ],
        positions: [

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
