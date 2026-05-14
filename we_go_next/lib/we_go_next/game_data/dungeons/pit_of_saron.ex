defmodule WeGoNext.GameData.Dungeons.PitOfSaron do
  @moduledoc "Static data for Pit of Saron (MDT index 150)."

  def info do
    %{
      name: "Pit of Saron",
      slug: "pit_of_saron",
      mdt_index: 150,
      map_id: 556,
      total_count: 643,
      floors: 1,
    }
  end

  def enemies do
    [
      %{
        name: "Deathwhisper Necrolyte",
        id: 252551,
        count: 15,
        health: 1366961,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258448, name: "Necromantic Infusion", dispellable: true}
        ],
        positions: [
          %{x: 416.28, y: -243.60, sublevel: 1, group: 47},
          %{x: 485.33, y: -325.16, sublevel: 1, group: 44},
          %{x: 336.27, y: -372.89, sublevel: 1, group: 52},
          %{x: 280.34, y: -427.44, sublevel: 1, group: 28},
          %{x: 299.88, y: -459.59, sublevel: 1, group: 4},
          %{x: 264.08, y: -406.06, sublevel: 1},
          %{x: 295.74, y: -380.02, sublevel: 1, group: 27}
        ],
      },
      %{
        name: "Risen Soldier",
        id: 252602,
        count: 0,
        health: 334146,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258450, name: "Charging Slash"},
          %{id: 1258451, name: "Charging Slash"}
        ],
        positions: [
          %{x: 420.11, y: -237.23, sublevel: 1, group: 47},
          %{x: 415.69, y: -236.41, sublevel: 1, group: 47},
          %{x: 481.86, y: -319.75, sublevel: 1, group: 44},
          %{x: 486.21, y: -319.11, sublevel: 1, group: 44},
          %{x: 490.21, y: -321.60, sublevel: 1, group: 44},
          %{x: 342.18, y: -370.90, sublevel: 1, group: 52},
          %{x: 339.03, y: -367.52, sublevel: 1, group: 52},
          %{x: 334.42, y: -367.19, sublevel: 1, group: 52},
          %{x: 278.95, y: -421.95, sublevel: 1, group: 28},
          %{x: 283.35, y: -422.17, sublevel: 1, group: 28},
          %{x: 286.28, y: -425.99, sublevel: 1, group: 28},
          %{x: 302.68, y: -464.06, sublevel: 1, group: 4},
          %{x: 304.29, y: -461.51, sublevel: 1, group: 4},
          %{x: 304.43, y: -456.94, sublevel: 1, group: 4},
          %{x: 259.58, y: -402.99, sublevel: 1},
          %{x: 268.15, y: -403.49, sublevel: 1},
          %{x: 293.06, y: -374.88, sublevel: 1, group: 27},
          %{x: 298.52, y: -374.99, sublevel: 1, group: 27},
          %{x: 301.21, y: -378.91, sublevel: 1, group: 27}
        ],
      },
      %{
        name: "Arcanist Cadaver",
        id: 252603,
        count: 0,
        health: 1366961,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258448, name: "Necromantic Infusion", dispellable: true},
          %{id: 1271479, name: "Netherburst", interruptible: true}
        ],
        positions: [
          %{x: 411.72, y: -238.37, sublevel: 1, group: 47},
          %{x: 490.73, y: -326.16, sublevel: 1, group: 44},
          %{x: 330.75, y: -370.58, sublevel: 1, group: 52},
          %{x: 275.16, y: -424.66, sublevel: 1, group: 28},
          %{x: 298.75, y: -464.17, sublevel: 1, group: 4},
          %{x: 264.16, y: -401.11, sublevel: 1},
          %{x: 290.24, y: -378.60, sublevel: 1, group: 27}
        ],
      },
      %{
        name: "Gloombound Shadebringer",
        id: 252567,
        count: 7,
        health: 1366961,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258431, name: "Shadow Bolt", interruptible: true}
        ],
        positions: [
          %{x: 464.24, y: -357.96, sublevel: 1, group: 77},
          %{x: 384.72, y: -396.31, sublevel: 1, group: 39},
          %{x: 330.28, y: -389.45, sublevel: 1, group: 32},
          %{x: 239.56, y: -458.52, sublevel: 1, group: 21},
          %{x: 222.60, y: -476.66, sublevel: 1, group: 19},
          %{x: 230.26, y: -486.79, sublevel: 1, group: 20},
          %{x: 228.86, y: -499.14, sublevel: 1, group: 18},
          %{x: 220.00, y: -541.68, sublevel: 1, group: 15},
          %{x: 319.85, y: -538.40, sublevel: 1, group: 14},
          %{x: 310.70, y: -504.62, sublevel: 1, group: 12},
          %{x: 284.78, y: -486.97, sublevel: 1, group: 5},
          %{x: 188.19, y: -428.62, sublevel: 1, group: 23},
          %{x: 246.98, y: -415.79, sublevel: 1, group: 29},
          %{x: 391.21, y: -181.06, sublevel: 1, group: 71},
          %{x: 263.35, y: -466.93, sublevel: 1, group: 81}
        ],
      },
      %{
        name: "Quarry Tormentor",
        id: 252561,
        count: 5,
        health: 1670730,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258433, name: "Tormenting Blade"},
          %{id: 1258434, name: "Curse of Torment"}
        ],
        positions: [
          %{x: 422.09, y: -251.14, sublevel: 1, group: 47},
          %{x: 490.83, y: -344.50, sublevel: 1, group: 43},
          %{x: 424.85, y: -422.35, sublevel: 1, group: 38},
          %{x: 388.13, y: -434.08, sublevel: 1, group: 67},
          %{x: 363.16, y: -450.13, sublevel: 1, group: 35},
          %{x: 326.55, y: -396.20, sublevel: 1, group: 32},
          %{x: 314.66, y: -412.91, sublevel: 1, group: 31},
          %{x: 329.34, y: -453.87, sublevel: 1, group: 6},
          %{x: 324.96, y: -471.01, sublevel: 1, group: 8},
          %{x: 275.47, y: -451.22, sublevel: 1, group: 2},
          %{x: 239.46, y: -451.44, sublevel: 1, group: 21},
          %{x: 214.07, y: -478.26, sublevel: 1, group: 19},
          %{x: 220.55, y: -500.04, sublevel: 1, group: 18},
          %{x: 212.99, y: -539.84, sublevel: 1, group: 15},
          %{x: 313.06, y: -538.52, sublevel: 1, group: 14},
          %{x: 304.54, y: -505.02, sublevel: 1, group: 12},
          %{x: 293.07, y: -485.98, sublevel: 1, group: 5},
          %{x: 195.74, y: -433.84, sublevel: 1, group: 23},
          %{x: 253.75, y: -416.01, sublevel: 1, group: 29},
          %{x: 236.79, y: -384.00, sublevel: 1, group: 25},
          %{x: 269.61, y: -345.45, sublevel: 1, group: 26},
          %{x: 326.54, y: -336.93, sublevel: 1, group: 51},
          %{x: 254.08, y: -467.64, sublevel: 1, group: 81},
          %{x: 385.21, y: -402.60, sublevel: 1, group: 39},
          %{x: 451.40, y: -309.88, sublevel: 1, group: 85},
          %{x: 358.79, y: -203.02, sublevel: 1, group: 70}
        ],
      },
      %{
        name: "Dreadpulse Lich",
        id: 252563,
        count: 15,
        health: 2278268,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258798, name: "Dread Pulse"},
          %{id: 1258802, name: "Dread Pulse"},
          %{id: 1258820, name: "Torrent of Misery"},
          %{id: 1258826, name: "Torrent of Misery"},
          %{id: 1271074, name: "Icy Blast", interruptible: true}
        ],
        positions: [
          %{x: 363.63, y: -439.19, sublevel: 1, group: 35},
          %{x: 290.21, y: -449.04, sublevel: 1, group: 3},
          %{x: 254.38, y: -453.82, sublevel: 1, group: 54},
          %{x: 205.67, y: -456.38, sublevel: 1, group: 55},
          %{x: 286.17, y: -397.65, sublevel: 1, group: 68},
          %{x: 262.06, y: -363.59, sublevel: 1, group: 69},
          %{x: 438.38, y: -182.38, sublevel: 1, group: 72},
          %{x: 444.85, y: -316.49, sublevel: 1, group: 85},
          %{x: 418.24, y: -416.45, sublevel: 1, group: 38}
        ],
      },
      %{
        name: "Rotting Ghoul",
        id: 252558,
        count: 5,
        health: 1518845,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258459, name: "Rotting Strikes"}
        ],
        positions: [
          %{x: 359.46, y: -284.46, sublevel: 1, group: 49},
          %{x: 356.09, y: -279.11, sublevel: 1, group: 49},
          %{x: 352.82, y: -273.30, sublevel: 1, group: 49},
          %{x: 434.58, y: -293.76, sublevel: 1, group: 45},
          %{x: 432.13, y: -379.50, sublevel: 1, group: 41},
          %{x: 434.54, y: -386.75, sublevel: 1, group: 41},
          %{x: 395.40, y: -414.58, sublevel: 1, group: 37},
          %{x: 346.66, y: -437.76, sublevel: 1, group: 34},
          %{x: 343.71, y: -444.50, sublevel: 1, group: 34},
          %{x: 307.88, y: -413.03, sublevel: 1, group: 31},
          %{x: 300.83, y: -412.23, sublevel: 1, group: 31},
          %{x: 311.31, y: -427.17, sublevel: 1, group: 30},
          %{x: 232.15, y: -451.29, sublevel: 1, group: 21},
          %{x: 232.47, y: -458.93, sublevel: 1, group: 21},
          %{x: 225.53, y: -515.96, sublevel: 1, group: 17},
          %{x: 217.02, y: -524.13, sublevel: 1, group: 16},
          %{x: 306.00, y: -516.48, sublevel: 1, group: 13},
          %{x: 312.27, y: -519.47, sublevel: 1, group: 13},
          %{x: 312.96, y: -485.98, sublevel: 1, group: 10},
          %{x: 202.76, y: -437.77, sublevel: 1, group: 23},
          %{x: 193.15, y: -405.65, sublevel: 1, group: 24},
          %{x: 200.77, y: -410.17, sublevel: 1, group: 24},
          %{x: 242.81, y: -370.60, sublevel: 1, group: 25},
          %{x: 317.90, y: -336.90, sublevel: 1, group: 51},
          %{x: 401.13, y: -189.12, sublevel: 1, group: 71},
          %{x: 401.77, y: -181.83, sublevel: 1, group: 71},
          %{x: 402.38, y: -174.31, sublevel: 1, group: 71},
          %{x: 268.76, y: -473.36, sublevel: 1, group: 81},
          %{x: 249.51, y: -475.69, sublevel: 1, group: 81},
          %{x: 490.73, y: -382.70, sublevel: 1, group: 42}
        ],
      },
      %{
        name: "Ymirjar Graveblade",
        id: 252610,
        count: 11,
        health: 2733921,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1258439, name: "Frostbane Slash"},
          %{id: 1258445, name: "Frostbane Slash"},
          %{id: 1278950, name: "Melee"},
          %{id: 1278963, name: "Dark Rupture"},
          %{id: 1278967, name: "Dark Rupture"}
        ],
        positions: [
          %{x: 425.89, y: -270.81, sublevel: 1, group: 46},
          %{x: 500.12, y: -342.11, sublevel: 1, group: 43},
          %{x: 355.65, y: -386.47, sublevel: 1, group: 40},
          %{x: 241.31, y: -506.57, sublevel: 1, group: 65},
          %{x: 296.98, y: -522.75, sublevel: 1, group: 64},
          %{x: 316.98, y: -498.22, sublevel: 1, group: 66},
          %{x: 221.21, y: -427.74, sublevel: 1, group: 56},
          %{x: 311.81, y: -359.38, sublevel: 1, group: 63},
          %{x: 368.17, y: -193.81, sublevel: 1, group: 70},
          %{x: 259.53, y: -476.68, sublevel: 1, group: 81},
          %{x: 315.59, y: -458.51, sublevel: 1, group: 87},
          %{x: 357.83, y: -194.03, sublevel: 1, group: 70},
          %{x: 438.86, y: -194.36, sublevel: 1, group: 72}
        ],
      },
      %{
        name: "Leaping Geist",
        id: 252559,
        count: 2,
        health: 759423,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258464, name: "Leaping Maul"}
        ],
        positions: [
          %{x: 396.48, y: -256.55, sublevel: 1, group: 48},
          %{x: 397.47, y: -263.93, sublevel: 1, group: 48},
          %{x: 359.56, y: -272.67, sublevel: 1, group: 49},
          %{x: 363.19, y: -278.26, sublevel: 1, group: 49},
          %{x: 434.67, y: -286.18, sublevel: 1, group: 45},
          %{x: 456.67, y: -356.44, sublevel: 1, group: 77},
          %{x: 461.44, y: -351.85, sublevel: 1, group: 77},
          %{x: 440.40, y: -384.55, sublevel: 1, group: 41},
          %{x: 436.15, y: -374.06, sublevel: 1, group: 41},
          %{x: 442.92, y: -390.76, sublevel: 1, group: 41},
          %{x: 437.80, y: -378.65, sublevel: 1, group: 41},
          %{x: 402.15, y: -416.09, sublevel: 1, group: 37},
          %{x: 340.59, y: -435.54, sublevel: 1, group: 34},
          %{x: 336.49, y: -441.32, sublevel: 1, group: 34},
          %{x: 305.39, y: -406.99, sublevel: 1, group: 31},
          %{x: 311.19, y: -407.18, sublevel: 1, group: 31},
          %{x: 310.02, y: -433.01, sublevel: 1, group: 30},
          %{x: 326.50, y: -490.95, sublevel: 1, group: 11},
          %{x: 327.30, y: -495.71, sublevel: 1, group: 11},
          %{x: 317.12, y: -479.00, sublevel: 1, group: 9},
          %{x: 194.97, y: -425.69, sublevel: 1, group: 23},
          %{x: 236.96, y: -375.65, sublevel: 1, group: 25},
          %{x: 286.50, y: -310.91, sublevel: 1, group: 80},
          %{x: 396.24, y: -185.78, sublevel: 1, group: 71},
          %{x: 397.02, y: -181.32, sublevel: 1, group: 71},
          %{x: 397.12, y: -176.73, sublevel: 1, group: 71},
          %{x: 470.23, y: -169.10, sublevel: 1, group: 73},
          %{x: 472.22, y: -164.50, sublevel: 1, group: 73},
          %{x: 479.55, y: -165.12, sublevel: 1, group: 73},
          %{x: 481.42, y: -169.47, sublevel: 1, group: 73},
          %{x: 479.80, y: -174.57, sublevel: 1, group: 73},
          %{x: 475.57, y: -176.44, sublevel: 1, group: 73},
          %{x: 471.35, y: -174.07, sublevel: 1, group: 73},
          %{x: 266.41, y: -444.78, sublevel: 1, group: 2},
          %{x: 268.44, y: -452.40, sublevel: 1, group: 2},
          %{x: 335.33, y: -413.37, sublevel: 1, group: 33},
          %{x: 342.40, y: -412.71, sublevel: 1, group: 33},
          %{x: 328.17, y: -413.16, sublevel: 1, group: 33},
          %{x: 401.35, y: -410.22, sublevel: 1, group: 37},
          %{x: 398.73, y: -421.48, sublevel: 1, group: 37},
          %{x: 445.10, y: -187.62, sublevel: 1, group: 72},
          %{x: 445.85, y: -182.14, sublevel: 1, group: 72},
          %{x: 445.35, y: -175.90, sublevel: 1, group: 72},
          %{x: 446.10, y: -192.86, sublevel: 1, group: 72},
          %{x: 446.60, y: -198.35, sublevel: 1, group: 72}
        ],
      },
      %{
        name: "Plungetalon Gargoyle",
        id: 252606,
        count: 6,
        health: 1215076,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258997, name: "Plungegrip", interruptible: true},
          %{id: 1271543, name: "Stoneskin"}
        ],
        positions: [
          %{x: 376.57, y: -267.88, sublevel: 1},
          %{x: 477.75, y: -369.04, sublevel: 1, group: 78},
          %{x: 390.57, y: -400.22, sublevel: 1, group: 39},
          %{x: 372.80, y: -446.02, sublevel: 1, group: 35},
          %{x: 303.90, y: -426.91, sublevel: 1, group: 30},
          %{x: 202.73, y: -428.47, sublevel: 1, group: 23},
          %{x: 271.15, y: -409.49, sublevel: 1},
          %{x: 326.95, y: -345.88, sublevel: 1, group: 51}
        ],
      },
      %{
        name: "Lumbering Plaguehorror",
        id: 252555,
        count: 6,
        health: 1822614,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1259116, name: "Blight Splatter"},
          %{id: 1259132, name: "Plague Frenzy"}
        ],
        positions: [
          %{x: 204.29, y: -390.32, sublevel: 1, group: 58},
          %{x: 218.58, y: -399.65, sublevel: 1, group: 57},
          %{x: 272.40, y: -377.75, sublevel: 1, group: 59},
          %{x: 290.00, y: -355.55, sublevel: 1, group: 60},
          %{x: 330.51, y: -315.12, sublevel: 1, group: 62},
          %{x: 294.53, y: -312.06, sublevel: 1, group: 80}
        ],
      },
      %{
        name: "Iceborn Proto-Drake",
        id: 257190,
        count: 9,
        health: 1822614,
        creature_type: "Dragonkin",
        is_boss: false,
        spells: [
          %{id: 1271009, name: "Icy Strikes"},
          %{id: 1278986, name: "Frost Breath"}
        ],
        positions: [
          %{x: 417.15, y: -276.72, sublevel: 1, group: 46},
          %{x: 499.85, y: -354.03, sublevel: 1, group: 43},
          %{x: 352.93, y: -397.10, sublevel: 1, group: 40}
        ],
      },
      %{
        name: "Wrathbone Enforcer",
        id: 252565,
        count: 5,
        health: 1670730,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258435, name: "Sunderstrike"}
        ],
        positions: [
          %{x: 440.10, y: -289.20, sublevel: 1, group: 45},
          %{x: 366.80, y: -415.98, sublevel: 1, group: 53},
          %{x: 331.73, y: -420.51, sublevel: 1, group: 33},
          %{x: 339.70, y: -420.00, sublevel: 1, group: 33},
          %{x: 334.10, y: -396.01, sublevel: 1, group: 32},
          %{x: 304.23, y: -434.45, sublevel: 1, group: 30},
          %{x: 324.43, y: -449.99, sublevel: 1, group: 6},
          %{x: 318.27, y: -469.51, sublevel: 1, group: 8},
          %{x: 273.84, y: -442.92, sublevel: 1, group: 2},
          %{x: 248.68, y: -436.50, sublevel: 1, group: 22},
          %{x: 242.51, y: -436.30, sublevel: 1, group: 22},
          %{x: 245.33, y: -388.08, sublevel: 1, group: 25},
          %{x: 244.29, y: -379.60, sublevel: 1, group: 25},
          %{x: 262.73, y: -344.99, sublevel: 1, group: 26},
          %{x: 315.50, y: -317.04, sublevel: 1, group: 50},
          %{x: 318.21, y: -346.29, sublevel: 1, group: 51},
          %{x: 289.04, y: -470.06, sublevel: 1, group: 82},
          %{x: 282.85, y: -471.13, sublevel: 1, group: 82},
          %{x: 417.14, y: -426.47, sublevel: 1, group: 38},
          %{x: 492.83, y: -376.42, sublevel: 1, group: 42},
          %{x: 374.70, y: -413.19, sublevel: 1, group: 53}
        ],
      },
      %{
        name: "Rimebone Coldwraith",
        id: 252566,
        count: 7,
        health: 1366961,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258436, name: "Ice Bolt", interruptible: true},
          %{id: 1258437, name: "Permeating Cold", dispellable: true}
        ],
        positions: [
          %{x: 390.66, y: -261.47, sublevel: 1, group: 48},
          %{x: 413.21, y: -252.04, sublevel: 1, group: 47},
          %{x: 309.59, y: -309.63, sublevel: 1, group: 50},
          %{x: 299.02, y: -332.02, sublevel: 1, group: 61},
          %{x: 475.60, y: -169.87, sublevel: 1, group: 73},
          %{x: 367.47, y: -202.63, sublevel: 1, group: 70},
          %{x: 454.01, y: -317.27, sublevel: 1, group: 85},
          %{x: 490.47, y: -351.81, sublevel: 1, group: 43}
        ],
      },
      %{
        name: "Glacieth",
        id: 252564,
        count: 20,
        health: 5467842,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 1259188, name: "Cryoburst"},
          %{id: 1259202, name: "Cryoburst"},
          %{id: 1259205, name: "Cryopatch"},
          %{id: 1259226, name: "Focused Guard"},
          %{id: 1278754, name: "Focused Guard"}
        ],
        positions: [
          %{x: 500.76, y: -145.96, sublevel: 1, group: 76}
        ],
      },
      %{
        name: "Krick",
        id: 252621,
        count: 0,
        health: 13922745,
        creature_type: "Undead",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1264027, name: "Shade Shift"},
          %{id: 1264246, name: "Shade Shift"},
          %{id: 1264363, name: "Get 'Em, Ick!"},
          %{id: 1278893, name: "Death Bolt", interruptible: true},
          %{id: 1279667, name: "Shadow Lance"},
          %{id: 1279668, name: "Shadow Lancer"}
        ],
        positions: [
          %{x: 325.37, y: -250.25, sublevel: 1, group: 75}
        ],
      },
      %{
        name: "Ick",
        id: 252625,
        count: 0,
        health: 13922745,
        creature_type: "Undead",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1264287, name: "Blight Smash"},
          %{id: 1264299, name: "Blight"},
          %{id: 1264336, name: "Plague Expulsion"},
          %{id: 1264349, name: "Plague Globs"},
          %{id: 1264453, name: "Lumbering Fixation"},
          %{id: 1264461, name: "Plague Globs"}
        ],
        positions: [
          %{x: 349.85, y: -240.30, sublevel: 1, group: 75}
        ],
      },
      %{
        name: "Forgemaster Garfrost",
        id: 252635,
        count: 0,
        health: 11865977,
        creature_type: "Undead",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1261299, name: "Throw Saronite"},
          %{id: 1261315, name: "Melee"},
          %{id: 1261546, name: "Orebreaker"},
          %{id: 1261799, name: "Saronite Sludge"},
          %{id: 1261806, name: "Siphoning Chill"},
          %{id: 1261808, name: "Siphoning Chill"},
          %{id: 1261847, name: "Cryostomp"},
          %{id: 1261921, name: "Cryoshards", dispellable: true},
          %{id: 1262029, name: "Glacial Overload"},
          %{id: 1272433, name: "Ore Chunks"}
        ],
        positions: [
          %{x: 546.46, y: -348.26, sublevel: 1, group: 79}
        ],
      },
      %{
        name: "Scourgelord Tyrannus",
        id: 252648,
        count: 0,
        health: 11707763,
        creature_type: "Humanoid",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1262582, name: "Scourgelord's Brand"},
          %{id: 1262596, name: "Scourgelord's Brand"},
          %{id: 1263406, name: "Army of the Dead"},
          %{id: 1263671, name: "Scourgelord's Reckoning"},
          %{id: 1263756, name: "Death's Grasp"},
          %{id: 1263766, name: "Death's Grasp"},
          %{id: 1276648, name: "Bone Infusion"}
        ],
        positions: [
          %{x: 300.80, y: -154.79, sublevel: 1, group: 74}
        ],
      },
      %{
        name: "Rimefang",
        id: 252653,
        count: 0,
        health: 12657041,
        creature_type: "Undead",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1262739, name: "Frost Spit"},
          %{id: 1262745, name: "Rime Blast"},
          %{id: 1262750, name: "Rime Blast"},
          %{id: 1263716, name: "Frostbite"},
          %{id: 1276948, name: "Ice Barrage"},
          %{id: 1276973, name: "Ice Barrage"}
        ],
        positions: [
          %{x: 329.56, y: -143.28, sublevel: 1, group: 74}
        ],
      },
      %{
        name: "Rotling",
        id: 254684,
        count: 0,
        health: 316426,
        creature_type: "Undead",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 290.55, y: -135.64, sublevel: 1, group: 74},
          %{x: 311.15, y: -174.82, sublevel: 1, group: 74}
        ],
      },
      %{
        name: "Scourge Plaguespreader",
        id: 254691,
        count: 0,
        health: 949278,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1262941, name: "Plague Bolt", interruptible: true},
          %{id: 1263000, name: "Festering Pulse"}
        ],
        positions: [
          %{x: 281.57, y: -164.43, sublevel: 1, group: 74},
          %{x: 294.73, y: -174.32, sublevel: 1, group: 74},
          %{x: 277.82, y: -148.95, sublevel: 1, group: 74}
        ],
      },
      %{
        name: "Shade of Krick",
        id: 255037,
        count: 0,
        health: 367054,
        creature_type: "Undead",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1264186, name: "Shadowbind", interruptible: true},
          %{id: 1271678, name: "Shade Bomb"}
        ],
        positions: [
          %{x: 327.56, y: -219.90, sublevel: 1, group: 75}
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
