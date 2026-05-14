defmodule WeGoNext.GameData.Dungeons.MaisaraCaverns do
  @moduledoc "Static data for Maisara Caverns (MDT index 154)."

  def info do
    %{
      name: "Maisara Caverns",
      slug: "maisara_caverns",
      mdt_index: 154,
      map_id: 560,
      total_count: 607,
      floors: 1,
    }
  end

  def enemies do
    [
      %{
        name: "Frenzied Berserker",
        id: 248684,
        count: 5,
        health: 1746672,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1255765, name: "Blood Frenzy"},
          %{id: 1255966, name: "Regeneratin'"}
        ],
        positions: [
          %{x: 246.90, y: -165.14, sublevel: 1, group: 1},
          %{x: 255.12, y: -160.58, sublevel: 1, group: 1},
          %{x: 262.24, y: -157.23, sublevel: 1, group: 1},
          %{x: 269.13, y: -153.88, sublevel: 1, group: 1},
          %{x: 334.33, y: -247.32, sublevel: 1, group: 21},
          %{x: 342.90, y: -270.10, sublevel: 1, group: 23},
          %{x: 321.78, y: -320.50, sublevel: 1, group: 26},
          %{x: 261.50, y: -188.22, sublevel: 1, group: 4},
          %{x: 288.82, y: -188.08, sublevel: 1, group: 6},
          %{x: 356.66, y: -217.88, sublevel: 1, group: 10},
          %{x: 351.19, y: -215.89, sublevel: 1, group: 10},
          %{x: 389.34, y: -219.86, sublevel: 1, group: 13},
          %{x: 419.24, y: -184.58, sublevel: 1, group: 15},
          %{x: 424.57, y: -183.51, sublevel: 1, group: 15},
          %{x: 328.33, y: -330.72, sublevel: 1, group: 26},
          %{x: 358.13, y: -320.96, sublevel: 1, group: 25},
          %{x: 347.14, y: -330.12, sublevel: 1, group: 25},
          %{x: 302.78, y: -358.49, sublevel: 1, group: 29},
          %{x: 258.75, y: -352.96, sublevel: 1},
          %{x: 257.97, y: -377.69, sublevel: 1},
          %{x: 202.56, y: -330.84, sublevel: 1, group: 39},
          %{x: 192.54, y: -304.33, sublevel: 1, group: 40},
          %{x: 187.39, y: -278.60, sublevel: 1, group: 43},
          %{x: 251.03, y: -306.36, sublevel: 1, group: 44},
          %{x: 249.58, y: -314.60, sublevel: 1, group: 44},
          %{x: 231.60, y: -257.54, sublevel: 1, group: 46},
          %{x: 230.69, y: -262.52, sublevel: 1, group: 46},
          %{x: 277.43, y: -253.31, sublevel: 1},
          %{x: 281.73, y: -287.68, sublevel: 1},
          %{x: 301.09, y: -266.98, sublevel: 1, group: 52}
        ],
      },
      %{
        name: "Keen Headhunter",
        id: 242964,
        count: 7,
        health: 1518845,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1255964, name: "Throw Spear"},
          %{id: 1255966, name: "Regeneratin'"},
          %{id: 1266381, name: "Hooked Snare", interruptible: true}
        ],
        positions: [
          %{x: 257.47, y: -193.19, sublevel: 1, group: 4},
          %{x: 292.30, y: -195.54, sublevel: 1, group: 6},
          %{x: 383.78, y: -215.74, sublevel: 1, group: 13},
          %{x: 437.87, y: -192.62, sublevel: 1},
          %{x: 353.21, y: -249.32, sublevel: 1, group: 20},
          %{x: 348.86, y: -265.31, sublevel: 1, group: 23},
          %{x: 370.50, y: -302.84, sublevel: 1, group: 24},
          %{x: 325.45, y: -325.74, sublevel: 1, group: 26},
          %{x: 287.20, y: -392.67, sublevel: 1, group: 32},
          %{x: 282.22, y: -395.03, sublevel: 1, group: 32},
          %{x: 198.35, y: -340.36, sublevel: 1, group: 39},
          %{x: 188.96, y: -285.93, sublevel: 1, group: 43},
          %{x: 254.78, y: -312.15, sublevel: 1, group: 44},
          %{x: 285.63, y: -314.99, sublevel: 1},
          %{x: 263.57, y: -231.46, sublevel: 1, group: 57},
          %{x: 268.77, y: -228.07, sublevel: 1, group: 57},
          %{x: 302.67, y: -283.27, sublevel: 1, group: 55},
          %{x: 310.81, y: -271.96, sublevel: 1, group: 54},
          %{x: 266.23, y: -366.33, sublevel: 1}
        ],
      },
      %{
        name: "Dread Souleater",
        id: 248686,
        count: 15,
        health: 2278268,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1257088, name: "Necrotic Wave"},
          %{id: 1257155, name: "Rain of Toads"},
          %{id: 1257160, name: "Rain of Toads"}
        ],
        positions: [
          %{x: 280.86, y: -201.47, sublevel: 1, group: 5},
          %{x: 419.95, y: -176.58, sublevel: 1, group: 15},
          %{x: 311.05, y: -244.74, sublevel: 1},
          %{x: 352.37, y: -325.67, sublevel: 1, group: 25},
          %{x: 301.61, y: -316.67, sublevel: 1, group: 27},
          %{x: 218.25, y: -366.68, sublevel: 1, group: 37},
          %{x: 279.86, y: -323.90, sublevel: 1}
        ],
      },
      %{
        name: "Ritual Hexxer",
        id: 248685,
        count: 7,
        health: 1366961,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1256008, name: "Hex", interruptible: true, dispellable: true},
          %{id: 1256015, name: "Shadow Bolt", interruptible: true}
        ],
        positions: [
          %{x: 333.34, y: -186.93, sublevel: 1, group: 7},
          %{x: 359.87, y: -180.30, sublevel: 1, group: 8},
          %{x: 395.93, y: -201.66, sublevel: 1, group: 12},
          %{x: 394.48, y: -209.58, sublevel: 1, group: 12},
          %{x: 336.61, y: -253.39, sublevel: 1, group: 21},
          %{x: 367.02, y: -262.14, sublevel: 1, group: 18},
          %{x: 371.21, y: -266.59, sublevel: 1, group: 18},
          %{x: 360.49, y: -328.81, sublevel: 1, group: 25},
          %{x: 296.76, y: -359.80, sublevel: 1, group: 29},
          %{x: 245.54, y: -364.43, sublevel: 1, group: 38},
          %{x: 205.70, y: -338.69, sublevel: 1, group: 39},
          %{x: 248.75, y: -289.87, sublevel: 1, group: 45},
          %{x: 254.77, y: -294.58, sublevel: 1, group: 45},
          %{x: 244.26, y: -231.99, sublevel: 1, group: 49},
          %{x: 261.71, y: -266.82, sublevel: 1, group: 51},
          %{x: 297.92, y: -282.81, sublevel: 1, group: 55},
          %{x: 610.58, y: -443.40, sublevel: 1, group: 77},
          %{x: 748.01, y: -302.92, sublevel: 1, group: 87},
          %{x: 226.92, y: -366.00, sublevel: 1, group: 37}
        ],
      },
      %{
        name: "Hexbound Eagle",
        id: 249020,
        count: 3,
        health: 1442903,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1256586, name: "Diseased Claws"},
          %{id: 1257780, name: "Shredding Talons"},
          %{id: 1257781, name: "Shredding Talons"},
          %{id: 1257782, name: "Shredding Talons"}
        ],
        positions: [
          %{x: 328.89, y: -180.75, sublevel: 1, group: 7},
          %{x: 326.40, y: -187.22, sublevel: 1, group: 7},
          %{x: 347.30, y: -247.52, sublevel: 1, group: 20},
          %{x: 367.25, y: -296.49, sublevel: 1, group: 24},
          %{x: 363.32, y: -303.03, sublevel: 1, group: 24},
          %{x: 302.65, y: -324.79, sublevel: 1, group: 27},
          %{x: 308.94, y: -319.29, sublevel: 1, group: 27},
          %{x: 235.38, y: -350.74, sublevel: 1},
          %{x: 209.76, y: -356.38, sublevel: 1},
          %{x: 263.79, y: -224.45, sublevel: 1, group: 57}
        ],
      },
      %{
        name: "Hex Guardian",
        id: 253302,
        count: 15,
        health: 2430152,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1258475, name: "Magma Surge"},
          %{id: 1258482, name: "Searing Presence"},
          %{id: 1258806, name: "Ritual Firebrand", dispellable: true}
        ],
        positions: [
          %{x: 325.41, y: -211.28, sublevel: 1, group: 9},
          %{x: 412.13, y: -264.55, sublevel: 1, group: 17},
          %{x: 339.70, y: -382.53, sublevel: 1, group: 30},
          %{x: 273.00, y: -344.91, sublevel: 1, group: 28},
          %{x: 258.49, y: -251.39, sublevel: 1, group: 47}
        ],
      },
      %{
        name: "Warding Mask",
        id: 249002,
        count: 2,
        health: 455654,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1257328, name: "Sear"}
        ],
        positions: [
          %{x: 327.89, y: -217.25, sublevel: 1, group: 9},
          %{x: 319.93, y: -215.26, sublevel: 1, group: 9},
          %{x: 405.06, y: -260.10, sublevel: 1, group: 17},
          %{x: 415.80, y: -257.74, sublevel: 1, group: 17},
          %{x: 420.77, y: -263.24, sublevel: 1, group: 17},
          %{x: 404.54, y: -267.17, sublevel: 1, group: 17},
          %{x: 409.51, y: -271.62, sublevel: 1, group: 17},
          %{x: 418.68, y: -269.79, sublevel: 1, group: 17},
          %{x: 341.90, y: -288.37, sublevel: 1, group: 22},
          %{x: 348.42, y: -288.25, sublevel: 1, group: 22},
          %{x: 340.59, y: -292.03, sublevel: 1, group: 22},
          %{x: 346.92, y: -293.95, sublevel: 1, group: 22},
          %{x: 334.98, y: -377.56, sublevel: 1, group: 30},
          %{x: 333.15, y: -387.24, sublevel: 1, group: 30},
          %{x: 345.72, y: -377.03, sublevel: 1, group: 30},
          %{x: 344.41, y: -388.55, sublevel: 1, group: 30},
          %{x: 306.74, y: -389.93, sublevel: 1, group: 33},
          %{x: 301.50, y: -390.20, sublevel: 1, group: 33},
          %{x: 247.11, y: -371.24, sublevel: 1, group: 38},
          %{x: 240.30, y: -369.15, sublevel: 1, group: 38},
          %{x: 249.20, y: -359.98, sublevel: 1, group: 38},
          %{x: 243.70, y: -357.89, sublevel: 1, group: 38},
          %{x: 257.55, y: -245.39, sublevel: 1, group: 47},
          %{x: 253.18, y: -249.08, sublevel: 1, group: 47},
          %{x: 262.13, y: -247.04, sublevel: 1, group: 47},
          %{x: 240.19, y: -226.11, sublevel: 1, group: 49},
          %{x: 239.51, y: -231.99, sublevel: 1, group: 49},
          %{x: 237.48, y: -235.38, sublevel: 1, group: 49},
          %{x: 271.43, y: -267.78, sublevel: 1, group: 50},
          %{x: 275.05, y: -266.17, sublevel: 1, group: 50},
          %{x: 280.21, y: -265.87, sublevel: 1, group: 50},
          %{x: 284.52, y: -267.05, sublevel: 1, group: 50},
          %{x: 272.28, y: -273.14, sublevel: 1, group: 50},
          %{x: 276.03, y: -276.72, sublevel: 1, group: 50},
          %{x: 280.45, y: -275.47, sublevel: 1, group: 50},
          %{x: 284.32, y: -272.57, sublevel: 1, group: 50},
          %{x: 346.36, y: -284.22, sublevel: 1, group: 22}
        ],
      },
      %{
        name: "Bramblemaw Bear",
        id: 249022,
        count: 5,
        health: 1594787,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1256561, name: "Crunch Armor"}
        ],
        positions: [
          %{x: 295.22, y: -165.89, sublevel: 1, group: 2},
          %{x: 302.37, y: -165.08, sublevel: 1, group: 2},
          %{x: 300.30, y: -171.39, sublevel: 1, group: 2},
          %{x: 357.17, y: -187.71, sublevel: 1, group: 8},
          %{x: 364.35, y: -187.27, sublevel: 1, group: 8},
          %{x: 315.75, y: -257.23, sublevel: 1},
          %{x: 300.74, y: -246.26, sublevel: 1},
          %{x: 318.24, y: -236.45, sublevel: 1},
          %{x: 198.60, y: -242.55, sublevel: 1},
          %{x: 189.71, y: -255.45, sublevel: 1},
          %{x: 330.45, y: -277.43, sublevel: 1},
          %{x: 324.67, y: -291.30, sublevel: 1},
          %{x: 196.60, y: -363.58, sublevel: 1, group: 36},
          %{x: 200.01, y: -369.34, sublevel: 1, group: 36},
          %{x: 202.36, y: -363.32, sublevel: 1, group: 36},
          %{x: 282.77, y: -303.56, sublevel: 1, group: 56},
          %{x: 276.21, y: -301.52, sublevel: 1, group: 56},
          %{x: 225.72, y: -258.90, sublevel: 1, group: 46},
          %{x: 306.04, y: -225.11, sublevel: 1, group: 104},
          %{x: 287.86, y: -231.94, sublevel: 1, group: 104}
        ],
      },
      %{
        name: "Mire Laborer",
        id: 248693,
        count: 1,
        health: 987249,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 299.99, y: -182.34, sublevel: 1, group: 3},
          %{x: 294.02, y: -180.84, sublevel: 1, group: 3},
          %{x: 336.58, y: -232.18, sublevel: 1, group: 11},
          %{x: 343.54, y: -232.67, sublevel: 1, group: 11},
          %{x: 339.56, y: -226.70, sublevel: 1, group: 11},
          %{x: 404.23, y: -232.57, sublevel: 1},
          %{x: 403.97, y: -200.70, sublevel: 1, group: 12},
          %{x: 402.97, y: -206.17, sublevel: 1, group: 12},
          %{x: 401.37, y: -212.64, sublevel: 1, group: 12},
          %{x: 424.41, y: -211.10, sublevel: 1, group: 16},
          %{x: 430.88, y: -212.59, sublevel: 1, group: 16},
          %{x: 368.27, y: -236.80, sublevel: 1, group: 19},
          %{x: 363.04, y: -237.32, sublevel: 1, group: 19},
          %{x: 416.58, y: -284.45, sublevel: 1, group: 17},
          %{x: 319.29, y: -389.71, sublevel: 1, group: 34},
          %{x: 315.62, y: -389.71, sublevel: 1, group: 34},
          %{x: 314.37, y: -398.15, sublevel: 1, group: 35},
          %{x: 311.75, y: -403.10, sublevel: 1, group: 35},
          %{x: 310.18, y: -398.38, sublevel: 1, group: 35},
          %{x: 217.04, y: -311.35, sublevel: 1},
          %{x: 204.62, y: -300.86, sublevel: 1},
          %{x: 174.78, y: -300.62, sublevel: 1, group: 41},
          %{x: 174.26, y: -304.28, sublevel: 1, group: 41},
          %{x: 174.82, y: -316.28, sublevel: 1, group: 42},
          %{x: 176.65, y: -320.73, sublevel: 1, group: 42},
          %{x: 182.67, y: -281.48, sublevel: 1, group: 43},
          %{x: 183.20, y: -285.14, sublevel: 1, group: 43},
          %{x: 249.49, y: -262.02, sublevel: 1, group: 48},
          %{x: 248.36, y: -265.18, sublevel: 1, group: 48},
          %{x: 252.43, y: -264.96, sublevel: 1, group: 48},
          %{x: 294.30, y: -255.68, sublevel: 1, group: 53},
          %{x: 298.83, y: -254.09, sublevel: 1, group: 53},
          %{x: 297.24, y: -264.04, sublevel: 1, group: 52},
          %{x: 301.77, y: -262.69, sublevel: 1, group: 52}
        ],
      },
      %{
        name: "Hulking Juggernaut",
        id: 248678,
        count: 15,
        health: 2733921,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1256047, name: "Deafening Roar"},
          %{id: 1256059, name: "Rending Gore"}
        ],
        positions: [
          %{x: 365.92, y: -242.56, sublevel: 1, group: 19},
          %{x: 297.80, y: -352.73, sublevel: 1, group: 29},
          %{x: 228.86, y: -294.80, sublevel: 1},
          %{x: 254.83, y: -214.85, sublevel: 1}
        ],
      },
      %{
        name: "Umbral Shadowbinder",
        id: 254740,
        count: 5,
        health: 1366961,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1263292, name: "Shrink", interruptible: true},
          %{id: 1263336, name: "Shadow Burst"},
          %{id: 1265832, name: "Shadow Burst"}
        ],
        positions: [
          %{x: 381.73, y: -228.79, sublevel: 1, group: 14},
          %{x: 389.09, y: -231.99, sublevel: 1, group: 14},
          %{x: 429.38, y: -233.52, sublevel: 1},
          %{x: 416.06, y: -276.60, sublevel: 1, group: 17},
          %{x: 354.73, y: -334.05, sublevel: 1, group: 25},
          %{x: 328.06, y: -348.06, sublevel: 1, group: 31},
          %{x: 322.82, y: -351.98, sublevel: 1, group: 31},
          %{x: 329.89, y: -355.91, sublevel: 1, group: 31},
          %{x: 196.54, y: -333.72, sublevel: 1, group: 39},
          %{x: 193.59, y: -311.66, sublevel: 1, group: 40},
          %{x: 265.24, y: -328.03, sublevel: 1},
          %{x: 260.27, y: -273.51, sublevel: 1, group: 51},
          %{x: 521.53, y: -537.28, sublevel: 1, group: 67},
          %{x: 647.20, y: -544.02, sublevel: 1, group: 73},
          %{x: 707.49, y: -482.77, sublevel: 1},
          %{x: 603.50, y: -306.05, sublevel: 1, group: 82}
        ],
      },
      %{
        name: "Restless Gnarldin",
        id: 249030,
        count: 15,
        health: 2733921,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1257895, name: "Ancestral Crush"},
          %{id: 1257898, name: "Ancestral Crush"},
          %{id: 1259274, name: "Spectral Strikes"},
          %{id: 1259631, name: "Staggering Blow"}
        ],
        positions: [
          %{x: 517.16, y: -388.18, sublevel: 1, group: 60},
          %{x: 552.84, y: -425.02, sublevel: 1},
          %{x: 697.04, y: -489.24, sublevel: 1},
          %{x: 747.27, y: -356.19, sublevel: 1, group: 90},
          %{x: 606.26, y: -276.38, sublevel: 1},
          %{x: 617.28, y: -367.06, sublevel: 1, group: 105}
        ],
      },
      %{
        name: "Reanimated Warrior",
        id: 248692,
        count: 2,
        health: 1594787,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1257716, name: "Reanimation", interruptible: true},
          %{id: 1257914, name: "Undying Resolve"},
          %{id: 1257920, name: "Dread Slash"}
        ],
        positions: [
          %{x: 499.22, y: -370.58, sublevel: 1, group: 59},
          %{x: 519.12, y: -370.08, sublevel: 1, group: 59},
          %{x: 498.76, y: -397.56, sublevel: 1, group: 61},
          %{x: 536.57, y: -397.06, sublevel: 1, group: 61},
          %{x: 487.93, y: -430.97, sublevel: 1, group: 65},
          %{x: 495.39, y: -431.46, sublevel: 1, group: 65},
          %{x: 524.47, y: -476.70, sublevel: 1, group: 66},
          %{x: 507.06, y: -478.19, sublevel: 1, group: 66},
          %{x: 547.05, y: -449.03, sublevel: 1, group: 63},
          %{x: 573.99, y: -549.99, sublevel: 1, group: 69},
          %{x: 582.45, y: -550.48, sublevel: 1, group: 69},
          %{x: 586.59, y: -504.21, sublevel: 1, group: 71},
          %{x: 606.37, y: -519.48, sublevel: 1, group: 72},
          %{x: 611.35, y: -518.99, sublevel: 1, group: 72},
          %{x: 639.74, y: -543.02, sublevel: 1, group: 73},
          %{x: 649.62, y: -505.63, sublevel: 1, group: 76},
          %{x: 656.58, y: -503.14, sublevel: 1, group: 76},
          %{x: 709.48, y: -489.73, sublevel: 1},
          %{x: 662.47, y: -453.93, sublevel: 1, group: 78},
          %{x: 672.42, y: -453.93, sublevel: 1, group: 78},
          %{x: 683.87, y: -453.43, sublevel: 1, group: 78},
          %{x: 691.94, y: -351.06, sublevel: 1, group: 85},
          %{x: 699.90, y: -357.03, sublevel: 1, group: 85},
          %{x: 746.82, y: -330.59, sublevel: 1, group: 89},
          %{x: 755.78, y: -335.06, sublevel: 1, group: 89},
          %{x: 743.03, y: -298.44, sublevel: 1, group: 87},
          %{x: 743.53, y: -309.38, sublevel: 1, group: 87},
          %{x: 753.48, y: -308.89, sublevel: 1, group: 87},
          %{x: 752.98, y: -298.44, sublevel: 1, group: 87},
          %{x: 734.42, y: -270.85, sublevel: 1, group: 88},
          %{x: 744.37, y: -271.34, sublevel: 1, group: 88},
          %{x: 601.51, y: -297.10, sublevel: 1, group: 82},
          %{x: 617.93, y: -297.10, sublevel: 1, group: 82},
          %{x: 602.01, y: -316.50, sublevel: 1, group: 82},
          %{x: 618.92, y: -316.00, sublevel: 1, group: 82},
          %{x: 611.46, y: -342.30, sublevel: 1, group: 93},
          %{x: 603.50, y: -345.78, sublevel: 1, group: 93},
          %{x: 612.04, y: -337.38, sublevel: 1}
        ],
      },
      %{
        name: "Grim Skirmisher",
        id: 248690,
        count: 2,
        health: 911307,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1270079, name: "Grim Ward", dispellable: true},
          %{id: 1270085, name: "Grim Ward"}
        ],
        positions: [
          %{x: 509.17, y: -369.58, sublevel: 1, group: 59},
          %{x: 531.55, y: -369.58, sublevel: 1, group: 59},
          %{x: 539.59, y: -454.50, sublevel: 1, group: 63},
          %{x: 543.57, y: -458.98, sublevel: 1, group: 63},
          %{x: 550.04, y: -457.49, sublevel: 1, group: 63},
          %{x: 553.52, y: -451.52, sublevel: 1, group: 63},
          %{x: 513.07, y: -535.29, sublevel: 1, group: 67},
          %{x: 517.55, y: -530.81, sublevel: 1, group: 67},
          %{x: 523.02, y: -530.31, sublevel: 1, group: 67},
          %{x: 528.49, y: -536.78, sublevel: 1, group: 67},
          %{x: 525.51, y: -542.75, sublevel: 1, group: 67},
          %{x: 517.55, y: -544.24, sublevel: 1, group: 67},
          %{x: 579.12, y: -508.69, sublevel: 1, group: 71},
          %{x: 584.60, y: -512.17, sublevel: 1, group: 71},
          %{x: 614.22, y: -489.29, sublevel: 1, group: 74},
          %{x: 618.69, y: -483.82, sublevel: 1, group: 74},
          %{x: 620.68, y: -494.26, sublevel: 1, group: 74},
          %{x: 625.16, y: -487.80, sublevel: 1, group: 74},
          %{x: 604.11, y: -453.35, sublevel: 1, group: 77},
          %{x: 621.53, y: -448.38, sublevel: 1, group: 77},
          %{x: 670.78, y: -383.47, sublevel: 1, group: 81},
          %{x: 687.20, y: -383.97, sublevel: 1, group: 81},
          %{x: 708.36, y: -305.79, sublevel: 1, group: 86},
          %{x: 709.35, y: -313.75, sublevel: 1, group: 86},
          %{x: 714.33, y: -303.30, sublevel: 1, group: 86},
          %{x: 715.82, y: -312.75, sublevel: 1, group: 86},
          %{x: 650.56, y: -184.54, sublevel: 1, group: 98},
          %{x: 651.06, y: -194.99, sublevel: 1, group: 98},
          %{x: 650.56, y: -203.94, sublevel: 1, group: 98},
          %{x: 655.04, y: -189.52, sublevel: 1, group: 98},
          %{x: 656.53, y: -198.47, sublevel: 1, group: 98},
          %{x: 683.61, y: -178.10, sublevel: 1, group: 99},
          %{x: 689.58, y: -177.60, sublevel: 1, group: 99},
          %{x: 696.04, y: -178.10, sublevel: 1, group: 99},
          %{x: 688.49, y: -190.60, sublevel: 1, group: 99},
          %{x: 693.06, y: -183.08, sublevel: 1, group: 99},
          %{x: 690.52, y: -133.06, sublevel: 1, group: 100},
          %{x: 697.05, y: -138.71, sublevel: 1, group: 100},
          %{x: 695.21, y: -146.81, sublevel: 1, group: 100},
          %{x: 683.06, y: -132.07, sublevel: 1, group: 100},
          %{x: 640.80, y: -131.41, sublevel: 1, group: 101},
          %{x: 639.80, y: -138.88, sublevel: 1, group: 101},
          %{x: 640.80, y: -148.33, sublevel: 1, group: 101},
          %{x: 646.27, y: -148.83, sublevel: 1, group: 101}
        ],
      },
      %{
        name: "Tormented Shade",
        id: 249036,
        count: 7,
        health: 1366961,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1259255, name: "Spirit Rend", interruptible: true, dispellable: true}
        ],
        positions: [
          %{x: 511.19, y: -405.52, sublevel: 1, group: 61},
          %{x: 522.64, y: -404.02, sublevel: 1, group: 61},
          %{x: 493.28, y: -411.49, sublevel: 1, group: 61},
          %{x: 536.07, y: -411.49, sublevel: 1, group: 61},
          %{x: 489.15, y: -452.32, sublevel: 1, group: 64},
          %{x: 496.12, y: -455.80, sublevel: 1, group: 64},
          %{x: 608.86, y: -513.02, sublevel: 1, group: 72},
          %{x: 641.23, y: -548.00, sublevel: 1, group: 73},
          %{x: 715.29, y: -380.03, sublevel: 1, group: 91},
          %{x: 722.75, y: -385.50, sublevel: 1, group: 91},
          %{x: 737.14, y: -360.17, sublevel: 1, group: 90},
          %{x: 743.78, y: -367.13, sublevel: 1, group: 90},
          %{x: 613.95, y: -306.55, sublevel: 1, group: 82},
          %{x: 640.81, y: -389.75, sublevel: 1, group: 92},
          %{x: 629.87, y: -394.73, sublevel: 1, group: 92},
          %{x: 628.22, y: -377.01, sublevel: 1, group: 105},
          %{x: 615.29, y: -378.50, sublevel: 1, group: 105},
          %{x: 659.02, y: -206.93, sublevel: 1, group: 98},
          %{x: 657.03, y: -183.05, sublevel: 1, group: 98},
          %{x: 680.37, y: -187.54, sublevel: 1, group: 99},
          %{x: 700.52, y: -186.06, sublevel: 1, group: 99},
          %{x: 645.77, y: -140.37, sublevel: 1, group: 101},
          %{x: 648.76, y: -131.41, sublevel: 1, group: 101},
          %{x: 681.56, y: -139.03, sublevel: 1, group: 100},
          %{x: 688.72, y: -145.09, sublevel: 1, group: 100}
        ],
      },
      %{
        name: "Rokh'zal",
        id: 253683,
        count: 10,
        health: 3797113,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1259786, name: "Ritual Sacrifice"},
          %{id: 1262241, name: "Invoke Shadow"}
        ],
        positions: [
          %{x: 521.78, y: -423.90, sublevel: 1, group: 62}
        ],
      },
      %{
        name: "Bound Defender",
        id: 249025,
        count: 15,
        health: 2582037,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1257546, name: "Vigilant Defense"},
          %{id: 1259274, name: "Spectral Strikes"},
          %{id: 1259651, name: "Soulstorms"},
          %{id: 1259664, name: "Soulstorms"}
        ],
        positions: [
          %{x: 515.52, y: -472.72, sublevel: 1, group: 66},
          %{x: 599.83, y: -535.17, sublevel: 1, group: 70},
          %{x: 657.50, y: -475.97, sublevel: 1, group: 75},
          %{x: 663.81, y: -377.01, sublevel: 1, group: 81},
          %{x: 657.68, y: -99.87, sublevel: 1},
          %{x: 684.81, y: -100.40, sublevel: 1}
        ],
      },
      %{
        name: "Hollow Soulrender",
        id: 249024,
        count: 15,
        health: 2278268,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1259677, name: "Rend Souls"},
          %{id: 1264327, name: "Shadowfrost Blast", interruptible: true},
          %{id: 1271623, name: "Frost Nova", dispellable: true}
        ],
        positions: [
          %{x: 559.00, y: -499.34, sublevel: 1, group: 68},
          %{x: 616.05, y: -456.34, sublevel: 1, group: 77},
          %{x: 678.24, y: -377.50, sublevel: 1, group: 81}
        ],
      },
      %{
        name: "Muro'jin",
        id: 247570,
        count: 0,
        health: 8543503,
        creature_type: "Humanoid",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1243752, name: "Icy Slick"},
          %{id: 1249789, name: "Revive Pet"},
          %{id: 1249989, name: "Coordinated Assault"},
          %{id: 1260648, name: "Barrage"},
          %{id: 1260709, name: "Vilebranch Sting", dispellable: true},
          %{id: 1260731, name: "Freezing Trap"},
          %{id: 1266480, name: "Flanking Spear"},
          %{id: 1266485, name: "Flanking Spear"},
          %{id: 1266488, name: "Open Wound"}
        ],
        positions: [
          %{x: 392.20, y: -371.15, sublevel: 1, group: 58}
        ],
      },
      %{
        name: "Nekraxx",
        id: 247572,
        count: 0,
        health: 8543503,
        creature_type: "Beast",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1243900, name: "Fetid Quillstorm"},
          %{id: 1246666, name: "Infected Pinions"},
          %{id: 1249478, name: "Carrion Swoop"},
          %{id: 1249479, name: "Carrion Swoop"},
          %{id: 1249638, name: "Carrion Swoop"},
          %{id: 1249947, name: "Bestial Wrath"},
          %{id: 1249948, name: "Bestial Wrath"},
          %{id: 1256247, name: "Fetid Quillstorm"},
          %{id: 1256387, name: "Carrion Swoop"}
        ],
        positions: [
          %{x: 410.21, y: -358.21, sublevel: 1, group: 58}
        ],
      },
      %{
        name: "Vordaza",
        id: 248595,
        count: 0,
        health: 9113070,
        creature_type: "Humanoid",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1250708, name: "Necrotic Convergence", interruptible: true},
          %{id: 1251204, name: "Wrest Phantoms"},
          %{id: 1251554, name: "Drain Soul"},
          %{id: 1251567, name: "Drain Soul"},
          %{id: 1251598, name: "Deathshroud"},
          %{id: 1251811, name: "Final Pursuit"},
          %{id: 1251813, name: "Lingering Dread"},
          %{id: 1251833, name: "Soulrot"},
          %{id: 1252054, name: "Unmake"},
          %{id: 1252130, name: "Unmake"},
          %{id: 1252611, name: "Coalesced Death"},
          %{id: 1263735, name: "Necrotic Convergence"},
          %{id: 1264987, name: "Withering Miasma"},
          %{id: 1264989, name: "Withering Miasma"},
          %{id: 1266706, name: "Haunting Remains"},
          %{id: 1277556, name: "Necrotic Convergence"}
        ],
        positions: [
          %{x: 675.16, y: -308.15, sublevel: 1, group: 84}
        ],
      },
      %{
        name: "Rak'tul",
        id: 248605,
        count: 0,
        health: 13448107,
        creature_type: "Undead",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1248879, name: "Deathgorged Vessel"},
          %{id: 1248980, name: "Volatile Essence"},
          %{id: 1251023, name: "Spiritbreaker"},
          %{id: 1251024, name: "Spiritbreaker"},
          %{id: 1252675, name: "Crush Souls"},
          %{id: 1252676, name: "Crush Souls"},
          %{id: 1252704, name: "Crush Souls"},
          %{id: 1253765, name: "Spiritbreaker"},
          %{id: 1253779, name: "Spectral Decay"},
          %{id: 1253788, name: "Soulrending Roar"},
          %{id: 1253844, name: "Withering Soul"},
          %{id: 1253909, name: "Soul Expulsion"},
          %{id: 1259810, name: "Shattered Totem"},
          %{id: 1266188, name: "Shadow Realm"},
          %{id: 1279517, name: "Soul Expulsion"}
        ],
        positions: [
          %{x: 676.57, y: -7.81, sublevel: 1, group: 102}
        ],
      },
      %{
        name: "Unstable Phantom",
        id: 250443,
        count: 0,
        health: 1265704,
        creature_type: "Undead",
        is_boss: false,
        spells: [
          %{id: 1251775, name: "Final Pursuit"}
        ],
        positions: [
          %{x: 685.31, y: -295.21, sublevel: 1, group: 84}
        ],
      },
      %{
        name: "Soulbind Totem",
        id: 251047,
        count: 0,
        health: 253141,
        creature_type: "Not specified",
        is_boss: false,
        spells: [
          %{id: 1252777, name: "Soulbind"},
          %{id: 1252816, name: "Chill of Death"}
        ],
        positions: [
          %{x: 689.21, y: -14.27, sublevel: 1, group: 102}
        ],
      },
      %{
        name: "Zil'jan",
        id: 253458,
        count: 7,
        health: 607538,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1259882, name: "Ritual Drums"},
          %{id: 1259887, name: "Ritual Drums"},
          %{id: 1262900, name: "Ritual Drums"}
        ],
        positions: [
          %{x: 671.93, y: -34.87, sublevel: 1, group: 103}
        ],
      },
      %{
        name: "Gloomwing Bat",
        id: 253473,
        count: 5,
        health: 1366961,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1259182, name: "Piercing Screech", interruptible: true},
          %{id: 1259183, name: "Piercing Screech"}
        ],
        positions: [
          %{x: 716.59, y: -437.47, sublevel: 1, group: 79},
          %{x: 721.07, y: -443.94, sublevel: 1, group: 79},
          %{x: 712.61, y: -444.93, sublevel: 1, group: 79},
          %{x: 674.72, y: -514.62, sublevel: 1, group: 80},
          %{x: 672.23, y: -523.58, sublevel: 1, group: 80},
          %{x: 681.69, y: -521.59, sublevel: 1, group: 80},
          %{x: 622.83, y: -196.77, sublevel: 1, group: 96},
          %{x: 621.84, y: -182.84, sublevel: 1, group: 96},
          %{x: 627.05, y: -109.86, sublevel: 1, group: 95},
          %{x: 627.05, y: -96.43, sublevel: 1, group: 95},
          %{x: 717.07, y: -95.17, sublevel: 1, group: 94},
          %{x: 719.06, y: -108.11, sublevel: 1, group: 94},
          %{x: 729.69, y: -177.50, sublevel: 1, group: 97},
          %{x: 731.68, y: -189.94, sublevel: 1, group: 97},
          %{x: 774.26, y: -267.10, sublevel: 1, group: 106},
          %{x: 780.73, y: -284.01, sublevel: 1, group: 106},
          %{x: 581.69, y: -234.26, sublevel: 1, group: 83},
          %{x: 582.68, y: -247.20, sublevel: 1, group: 83}
        ],
      },
      %{
        name: "Death's Grasp",
        id: 253701,
        count: 0,
        health: 227827,
        creature_type: "Not specified",
        is_boss: false,
        spells: [
          %{id: 1259794, name: "Ritual Sacrifice"}
        ],
        positions: [
          %{x: 516.44, y: -433.43, sublevel: 1, group: 62}
        ],
      },
      %{
        name: "Rokh'zal",
        id: 254233,
        count: 0,
        health: 3948997,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1259772, name: "Umbral Vortex"},
          %{id: 1259777, name: "Umbral Vortex"}
        ],
        positions: [
          %{x: 524.00, y: -435.42, sublevel: 1, group: 62}
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
