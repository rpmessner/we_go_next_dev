defmodule WeGoNext.GameData.Dungeons.MagistersTerrace do
  @moduledoc "Static data for Magisters Terrace (MDT index 153)."

  def info do
    %{
      name: "Magisters Terrace",
      slug: "magisters_terrace",
      mdt_index: 153,
      map_id: 558,
      total_count: 585,
      floors: 1,
    }
  end

  def enemies do
    [
      %{
        name: "Arcane Magister",
        id: 232369,
        count: 7,
        health: 1366961,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 468962, name: "Arcane Bolt", interruptible: true},
          %{id: 468966, name: "Polymorph", interruptible: true, dispellable: true},
          %{id: 1245046, name: "Blink"}
        ],
        positions: [
          %{x: 392.26, y: -171.12, sublevel: 1, group: 11},
          %{x: 55.09, y: -143.66, sublevel: 1, group: 1},
          %{x: 81.47, y: -144.13, sublevel: 1, group: 1},
          %{x: 112.26, y: -166.08, sublevel: 1, group: 3},
          %{x: 139.38, y: -211.78, sublevel: 1, group: 4},
          %{x: 368.49, y: -184.26, sublevel: 1, group: 10},
          %{x: 433.21, y: -146.25, sublevel: 1, group: 17},
          %{x: 515.89, y: -204.21, sublevel: 1, group: 23},
          %{x: 511.76, y: -145.78, sublevel: 1, group: 25},
          %{x: 599.44, y: -109.99, sublevel: 1, group: 26},
          %{x: 633.08, y: -128.93, sublevel: 1, group: 27}
        ],
      },
      %{
        name: "Animated Codex",
        id: 234089,
        count: 2,
        health: 10000,
        creature_type: "Elemental",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 116.38, y: -171.82, sublevel: 1, group: 3},
          %{x: 108.14, y: -171.84, sublevel: 1, group: 3},
          %{x: 154.83, y: -134.79, sublevel: 1, group: 5},
          %{x: 149.34, y: -137.71, sublevel: 1, group: 5},
          %{x: 154.91, y: -141.04, sublevel: 1, group: 5},
          %{x: 164.87, y: -202.03, sublevel: 1, group: 6},
          %{x: 161.89, y: -207.89, sublevel: 1, group: 6},
          %{x: 167.92, y: -208.11, sublevel: 1, group: 6},
          %{x: 249.76, y: -168.48, sublevel: 1, group: 7},
          %{x: 249.78, y: -175.12, sublevel: 1, group: 7},
          %{x: 243.11, y: -175.38, sublevel: 1, group: 7},
          %{x: 243.12, y: -168.76, sublevel: 1, group: 7},
          %{x: 244.18, y: -136.96, sublevel: 1, group: 8},
          %{x: 241.73, y: -143.11, sublevel: 1, group: 8},
          %{x: 248.17, y: -142.56, sublevel: 1, group: 8}
        ],
      },
      %{
        name: "Blazing Pyromancer",
        id: 251861,
        count: 12,
        health: 2430152,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1254294, name: "Pyroblast", interruptible: true},
          %{id: 1254301, name: "Flamestrike"},
          %{id: 1254336, name: "Ignition"},
          %{id: 1254338, name: "Ignition"}
        ],
        positions: [
          %{x: 216.07, y: -126.40, sublevel: 1, group: 9},
          %{x: 389.41, y: -195.58, sublevel: 1, group: 13},
          %{x: 429.92, y: -204.92, sublevel: 1, group: 16},
          %{x: 451.07, y: -151.75, sublevel: 1, group: 18},
          %{x: 509.85, y: -195.81, sublevel: 1, group: 23}
        ],
      },
      %{
        name: "Runed Spellbreaker",
        id: 240973,
        count: 12,
        health: 2733921,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1244907, name: "Runic Glaive"},
          %{id: 1283901, name: "Shield Slam"},
          %{id: 1283905, name: "Shield Slam"}
        ],
        positions: [
          %{x: 504.22, y: -173.47, sublevel: 1, group: 24},
          %{x: 628.70, y: -121.12, sublevel: 1, group: 27},
          %{x: 686.43, y: -134.35, sublevel: 1, group: 29},
          %{x: 681.29, y: -146.37, sublevel: 1, group: 29}
        ],
      },
      %{
        name: "Voidling",
        id: 234069,
        count: 1,
        health: 607538,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1248229, name: "Void Infusion"},
          %{id: 1255434, name: "Void Gash", dispellable: true}
        ],
        positions: [
          %{x: 743.16, y: -173.58, sublevel: 1, group: 30},
          %{x: 746.97, y: -171.02, sublevel: 1, group: 30},
          %{x: 751.13, y: -168.69, sublevel: 1, group: 30},
          %{x: 745.62, y: -177.40, sublevel: 1, group: 30},
          %{x: 749.72, y: -174.95, sublevel: 1, group: 30},
          %{x: 754.35, y: -172.47, sublevel: 1, group: 30},
          %{x: 785.69, y: -299.80, sublevel: 1, group: 33},
          %{x: 788.66, y: -304.19, sublevel: 1, group: 33},
          %{x: 791.69, y: -308.25, sublevel: 1, group: 33},
          %{x: 790.11, y: -297.38, sublevel: 1, group: 33},
          %{x: 792.90, y: -301.49, sublevel: 1, group: 33},
          %{x: 795.92, y: -305.77, sublevel: 1, group: 33},
          %{x: 667.12, y: -393.36, sublevel: 1, group: 37},
          %{x: 669.10, y: -401.17, sublevel: 1, group: 37},
          %{x: 669.12, y: -404.92, sublevel: 1, group: 37},
          %{x: 669.22, y: -397.44, sublevel: 1, group: 37},
          %{x: 667.24, y: -408.93, sublevel: 1, group: 37},
          %{x: 597.84, y: -411.73, sublevel: 1, group: 43},
          %{x: 602.49, y: -411.79, sublevel: 1, group: 43},
          %{x: 606.99, y: -411.52, sublevel: 1, group: 43},
          %{x: 599.86, y: -407.88, sublevel: 1, group: 43},
          %{x: 604.44, y: -407.64, sublevel: 1, group: 43},
          %{x: 597.57, y: -423.02, sublevel: 1, group: 43},
          %{x: 602.20, y: -422.95, sublevel: 1, group: 43},
          %{x: 607.35, y: -422.76, sublevel: 1, group: 43},
          %{x: 604.15, y: -427.30, sublevel: 1, group: 43},
          %{x: 599.49, y: -427.15, sublevel: 1, group: 43},
          %{x: 556.04, y: -423.31, sublevel: 1, group: 47},
          %{x: 560.90, y: -419.79, sublevel: 1, group: 47},
          %{x: 566.35, y: -420.02, sublevel: 1, group: 47},
          %{x: 569.45, y: -424.07, sublevel: 1, group: 47},
          %{x: 555.57, y: -430.93, sublevel: 1, group: 47},
          %{x: 560.06, y: -434.49, sublevel: 1, group: 47},
          %{x: 565.75, y: -434.40, sublevel: 1, group: 47},
          %{x: 569.12, y: -430.81, sublevel: 1, group: 47},
          %{x: 352.80, y: -491.43, sublevel: 1, group: 49},
          %{x: 352.77, y: -496.35, sublevel: 1, group: 49},
          %{x: 352.77, y: -501.06, sublevel: 1, group: 49},
          %{x: 348.06, y: -496.44, sublevel: 1, group: 49},
          %{x: 347.97, y: -500.96, sublevel: 1, group: 49},
          %{x: 348.16, y: -491.65, sublevel: 1, group: 49},
          %{x: 229.04, y: -521.77, sublevel: 1, group: 52},
          %{x: 232.20, y: -525.70, sublevel: 1, group: 52},
          %{x: 235.26, y: -529.52, sublevel: 1, group: 52},
          %{x: 238.51, y: -533.06, sublevel: 1, group: 52},
          %{x: 242.34, y: -530.19, sublevel: 1, group: 52},
          %{x: 238.80, y: -526.94, sublevel: 1, group: 52},
          %{x: 236.12, y: -523.02, sublevel: 1, group: 52},
          %{x: 233.25, y: -519.38, sublevel: 1, group: 52},
          %{x: 259.31, y: -393.98, sublevel: 1, group: 53},
          %{x: 256.30, y: -397.48, sublevel: 1, group: 53},
          %{x: 252.88, y: -400.86, sublevel: 1, group: 53},
          %{x: 249.65, y: -404.75, sublevel: 1, group: 53},
          %{x: 246.31, y: -408.86, sublevel: 1, group: 53},
          %{x: 249.77, y: -412.13, sublevel: 1, group: 53},
          %{x: 253.05, y: -408.45, sublevel: 1, group: 53},
          %{x: 256.50, y: -404.63, sublevel: 1, group: 53},
          %{x: 259.70, y: -401.09, sublevel: 1, group: 53},
          %{x: 262.71, y: -397.27, sublevel: 1, group: 53},
          %{x: 343.36, y: -502.08, sublevel: 1, group: 49},
          %{x: 342.85, y: -496.78, sublevel: 1, group: 49},
          %{x: 343.36, y: -491.98, sublevel: 1, group: 49}
        ],
      },
      %{
        name: "Hollowsoul Shredder",
        id: 234065,
        count: 5,
        health: 1442903,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1227020, name: "Dimensional Shred"},
          %{id: 1248229, name: "Void Infusion"}
        ],
        positions: [
          %{x: 752.41, y: -203.58, sublevel: 1, group: 31},
          %{x: 760.28, y: -198.35, sublevel: 1, group: 31},
          %{x: 768.13, y: -193.77, sublevel: 1, group: 31},
          %{x: 773.16, y: -236.84, sublevel: 1, group: 32},
          %{x: 788.65, y: -228.60, sublevel: 1, group: 32},
          %{x: 687.99, y: -442.43, sublevel: 1, group: 35},
          %{x: 683.04, y: -447.89, sublevel: 1, group: 35},
          %{x: 664.28, y: -441.74, sublevel: 1, group: 36},
          %{x: 667.06, y: -448.03, sublevel: 1, group: 36},
          %{x: 690.23, y: -391.40, sublevel: 1, group: 34},
          %{x: 613.43, y: -394.03, sublevel: 1, group: 42},
          %{x: 625.99, y: -417.64, sublevel: 1, group: 39},
          %{x: 625.79, y: -424.36, sublevel: 1, group: 39},
          %{x: 612.71, y: -443.67, sublevel: 1, group: 41},
          %{x: 553.35, y: -395.04, sublevel: 1, group: 46},
          %{x: 543.17, y: -403.68, sublevel: 1, group: 46},
          %{x: 293.25, y: -495.22, sublevel: 1, group: 50},
          %{x: 123.40, y: -301.89, sublevel: 1, group: 57},
          %{x: 120.90, y: -293.22, sublevel: 1, group: 57},
          %{x: 125.99, y: -309.96, sublevel: 1, group: 57},
          %{x: 183.92, y: -339.02, sublevel: 1, group: 55},
          %{x: 187.39, y: -347.62, sublevel: 1, group: 55}
        ],
      },
      %{
        name: "Dreaded Voidwalker",
        id: 234064,
        count: 7,
        health: 1670730,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1248229, name: "Void Infusion"},
          %{id: 1248327, name: "Shadow Bolt", interruptible: true}
        ],
        positions: [
          %{x: 779.82, y: -230.57, sublevel: 1, group: 32},
          %{x: 690.13, y: -450.07, sublevel: 1, group: 35},
          %{x: 660.14, y: -448.15, sublevel: 1, group: 36},
          %{x: 686.65, y: -398.25, sublevel: 1, group: 34},
          %{x: 682.77, y: -391.52, sublevel: 1, group: 34},
          %{x: 663.53, y: -397.99, sublevel: 1, group: 37},
          %{x: 637.37, y: -396.78, sublevel: 1, group: 40},
          %{x: 619.90, y: -393.17, sublevel: 1, group: 42},
          %{x: 615.75, y: -437.50, sublevel: 1, group: 41},
          %{x: 619.39, y: -443.91, sublevel: 1, group: 41},
          %{x: 585.86, y: -395.34, sublevel: 1, group: 45},
          %{x: 589.97, y: -401.91, sublevel: 1, group: 45},
          %{x: 589.32, y: -429.07, sublevel: 1, group: 44},
          %{x: 216.81, y: -490.57, sublevel: 1, group: 51}
        ],
      },
      %{
        name: "Shadowrift Voidcaller",
        id: 234068,
        count: 12,
        health: 2430152,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1217087, name: "Consuming Shadows"},
          %{id: 1255462, name: "Call of the Void"},
          %{id: 1265977, name: "Consuming Shadows"}
        ],
        positions: [
          %{x: 652.93, y: -419.42, sublevel: 1, group: 38},
          %{x: 562.31, y: -427.17, sublevel: 1, group: 47},
          %{x: 213.71, y: -481.79, sublevel: 1, group: 51},
          %{x: 130.32, y: -367.55, sublevel: 1, group: 56}
        ],
      },
      %{
        name: "Devouring Tyrant",
        id: 234066,
        count: 12,
        health: 2733921,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1248138, name: "Void Bomb"},
          %{id: 1248219, name: "Void Bomb"},
          %{id: 1248229, name: "Void Infusion"},
          %{id: 1264687, name: "Devouring Strike"}
        ],
        positions: [
          %{x: 545.20, y: -395.97, sublevel: 1, group: 46},
          %{x: 615.49, y: -385.69, sublevel: 1, group: 42},
          %{x: 308.01, y: -359.05, sublevel: 1, group: 54},
          %{x: 177.25, y: -347.95, sublevel: 1, group: 55},
          %{x: 120.24, y: -362.01, sublevel: 1, group: 56}
        ],
      },
      %{
        name: "Void Infuser",
        id: 249086,
        count: 7,
        health: 1366961,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1245068, name: "Consuming Void", dispellable: true},
          %{id: 1248229, name: "Void Infusion"},
          %{id: 1264693, name: "Terror Wave", interruptible: true}
        ],
        positions: [
          %{x: 663.44, y: -405.03, sublevel: 1, group: 37},
          %{x: 623.46, y: -386.48, sublevel: 1, group: 42},
          %{x: 620.23, y: -421.02, sublevel: 1, group: 39},
          %{x: 609.33, y: -438.05, sublevel: 1, group: 41},
          %{x: 616.22, y: -449.81, sublevel: 1, group: 41},
          %{x: 598.49, y: -417.36, sublevel: 1, group: 43},
          %{x: 605.88, y: -417.70, sublevel: 1, group: 43},
          %{x: 584.19, y: -435.06, sublevel: 1, group: 44},
          %{x: 551.21, y: -402.45, sublevel: 1, group: 46},
          %{x: 294.04, y: -503.62, sublevel: 1, group: 50},
          %{x: 294.39, y: -486.79, sublevel: 1, group: 50},
          %{x: 221.70, y: -483.60, sublevel: 1, group: 51},
          %{x: 311.58, y: -350.33, sublevel: 1, group: 54},
          %{x: 302.86, y: -351.60, sublevel: 1, group: 54},
          %{x: 129.04, y: -294.73, sublevel: 1, group: 57},
          %{x: 131.51, y: -303.29, sublevel: 1, group: 57},
          %{x: 176.24, y: -337.30, sublevel: 1, group: 55}
        ],
      },
      %{
        name: "Arcanotron Custos",
        id: 231861,
        count: 0,
        health: 12657041,
        creature_type: "Mechanical",
        is_boss: true,
        encounter_id: 2659,
        spells: [
          %{id: 474345, name: "Refueling Protocol"},
          %{id: 474496, name: "Repulsing Slam"},
          %{id: 1214038, name: "Ethereal Shackles", dispellable: true},
          %{id: 1214081, name: "Arcane Expulsion"},
          %{id: 1243905, name: "Unstable Energy"}
        ],
        positions: [
          %{x: 465.50, y: -172.02, sublevel: 1}
        ],
      },
      %{
        name: "Seranel Sunlash",
        id: 231863,
        count: 0,
        health: 11074911,
        creature_type: "Not specified",
        is_boss: true,
        encounter_id: 2659,
        spells: [
          %{id: 1224903, name: "Suppression Zone"},
          %{id: 1225015, name: "Suppression Zone"},
          %{id: 1225135, name: "Feedback"},
          %{id: 1225193, name: "Wave of Silence"},
          %{id: 1225201, name: "Wave of Silence"},
          %{id: 1225205, name: "Wave of Silence"},
          %{id: 1225792, name: "Runic Mark"},
          %{id: 1225796, name: "Runic Mark"},
          %{id: 1246446, name: "Null Reaction"},
          %{id: 1248689, name: "Hastening Ward", dispellable: true},
          %{id: 1271317, name: "Hastening Ward"}
        ],
        positions: [
          %{x: 732.43, y: -141.74, sublevel: 1}
        ],
      },
      %{
        name: "Gemellus",
        id: 231864,
        count: 0,
        health: 17403431,
        creature_type: "Not specified",
        is_boss: true,
        encounter_id: 2659,
        spells: [
          %{id: 1223847, name: "Triplicate"},
          %{id: 1223936, name: "Synaptic Nexus"},
          %{id: 1224104, name: "Void Secretions"},
          %{id: 1224299, name: "Astral Grasp"},
          %{id: 1224401, name: "Cosmic Radiation"},
          %{id: 1253707, name: "Neural Link"},
          %{id: 1253709, name: "Neural Link"},
          %{id: 1284954, name: "Cosmic Sting"},
          %{id: 1284958, name: "Cosmic Sting"}
        ],
        positions: [
          %{x: 517.03, y: -430.45, sublevel: 1, group: 60}
        ],
      },
      %{
        name: "Degentrius",
        id: 231865,
        count: 0,
        health: 12657041,
        creature_type: "Aberration",
        is_boss: true,
        encounter_id: 2659,
        spells: [
          %{id: 1215087, name: "Unstable Void Essence"},
          %{id: 1215897, name: "Devouring Entropy"},
          %{id: 1269631, name: "Entropy Orb"},
          %{id: 1271066, name: "Entropy Blast"},
          %{id: 1280113, name: "Hulking Fragment"},
          %{id: 1280119, name: "Hulking Fragment"},
          %{id: 1284627, name: "Umbral Splinters", dispellable: true},
          %{id: 1284633, name: "Stygian Ichor"}
        ],
        positions: [
          %{x: 70.87, y: -477.87, sublevel: 1}
        ],
      },
      %{
        name: "Brightscale Wyrm",
        id: 232106,
        count: 1,
        health: 303769,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 467068, name: "Energy Infusion"},
          %{id: 1254595, name: "Energy Release"}
        ],
        positions: [
          %{x: 395.19, y: -195.85, sublevel: 1, group: 13},
          %{x: 383.51, y: -193.40, sublevel: 1, group: 13},
          %{x: 385.43, y: -190.35, sublevel: 1, group: 13},
          %{x: 394.96, y: -192.61, sublevel: 1, group: 13},
          %{x: 392.46, y: -190.01, sublevel: 1, group: 13},
          %{x: 389.22, y: -189.58, sublevel: 1, group: 13},
          %{x: 447.57, y: -182.44, sublevel: 1, group: 19},
          %{x: 450.90, y: -182.54, sublevel: 1, group: 19},
          %{x: 453.81, y: -182.71, sublevel: 1, group: 19},
          %{x: 456.87, y: -182.71, sublevel: 1, group: 19},
          %{x: 456.89, y: -186.40, sublevel: 1, group: 19},
          %{x: 453.69, y: -186.42, sublevel: 1, group: 19},
          %{x: 450.83, y: -186.06, sublevel: 1, group: 19},
          %{x: 447.67, y: -186.03, sublevel: 1, group: 19},
          %{x: 447.56, y: -189.58, sublevel: 1, group: 19},
          %{x: 450.45, y: -189.75, sublevel: 1, group: 19},
          %{x: 453.63, y: -189.75, sublevel: 1, group: 19},
          %{x: 457.03, y: -189.84, sublevel: 1, group: 19},
          %{x: 454.40, y: -145.98, sublevel: 1, group: 18},
          %{x: 449.83, y: -145.49, sublevel: 1, group: 18},
          %{x: 455.80, y: -156.38, sublevel: 1, group: 18},
          %{x: 457.95, y: -152.80, sublevel: 1, group: 18},
          %{x: 457.33, y: -148.56, sublevel: 1, group: 18},
          %{x: 452.53, y: -158.37, sublevel: 1, group: 18},
          %{x: 468.65, y: -197.88, sublevel: 1, group: 20},
          %{x: 472.13, y: -197.94, sublevel: 1, group: 20},
          %{x: 475.19, y: -197.95, sublevel: 1, group: 20},
          %{x: 468.84, y: -194.25, sublevel: 1, group: 20},
          %{x: 471.89, y: -194.36, sublevel: 1, group: 20},
          %{x: 475.02, y: -194.48, sublevel: 1, group: 20},
          %{x: 468.90, y: -190.80, sublevel: 1, group: 20},
          %{x: 471.90, y: -190.98, sublevel: 1, group: 20},
          %{x: 474.92, y: -190.82, sublevel: 1, group: 20},
          %{x: 478.32, y: -190.90, sublevel: 1, group: 20},
          %{x: 478.31, y: -194.53, sublevel: 1, group: 20},
          %{x: 478.45, y: -198.22, sublevel: 1, group: 20},
          %{x: 468.57, y: -143.27, sublevel: 1, group: 21},
          %{x: 471.76, y: -143.20, sublevel: 1, group: 21},
          %{x: 475.33, y: -143.35, sublevel: 1, group: 21},
          %{x: 468.42, y: -146.79, sublevel: 1, group: 21},
          %{x: 471.69, y: -146.57, sublevel: 1, group: 21},
          %{x: 475.31, y: -146.49, sublevel: 1, group: 21},
          %{x: 475.25, y: -150.28, sublevel: 1, group: 21},
          %{x: 471.78, y: -150.30, sublevel: 1, group: 21},
          %{x: 468.20, y: -150.42, sublevel: 1, group: 21},
          %{x: 468.45, y: -139.65, sublevel: 1, group: 21},
          %{x: 471.76, y: -139.57, sublevel: 1, group: 21},
          %{x: 475.30, y: -139.48, sublevel: 1, group: 21}
        ],
      },
      %{
        name: "Arcane Sentry",
        id: 234062,
        count: 16,
        health: 3645228,
        creature_type: "Mechanical",
        is_boss: false,
        spells: [
          %{id: 473258, name: "Crowd Dispersal"},
          %{id: 1282050, name: "Arcane Beam"},
          %{id: 1282051, name: "Arcane Beam"},
          %{id: 1282053, name: "Arcane Residue"},
          %{id: 1282055, name: "Ethereal Shackles", dispellable: true}
        ],
        positions: [
          %{x: 67.98, y: -153.09, sublevel: 1, group: 1},
          %{x: 422.90, y: -173.07, sublevel: 1, group: 15},
          %{x: 485.32, y: -202.24, sublevel: 1, group: 22}
        ],
      },
      %{
        name: "Vigilant Librarian",
        id: 234067,
        count: 0,
        health: 1518845,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 194.62, y: -169.12, sublevel: 1}
        ],
      },
      %{
        name: "Sunblade Enforcer",
        id: 234124,
        count: 5,
        health: 1518845,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1252910, name: "Arcane Blade"},
          %{id: 1253224, name: "Charge"},
          %{id: 1265561, name: "Arcane Blade", dispellable: true}
        ],
        positions: [
          %{x: 74.00, y: -143.82, sublevel: 1, group: 1},
          %{x: 62.43, y: -143.98, sublevel: 1, group: 1},
          %{x: 121.32, y: -139.14, sublevel: 1, group: 2},
          %{x: 120.52, y: -148.24, sublevel: 1, group: 2},
          %{x: 141.74, y: -218.58, sublevel: 1, group: 4},
          %{x: 393.51, y: -158.51, sublevel: 1, group: 12},
          %{x: 408.08, y: -188.54, sublevel: 1, group: 14},
          %{x: 415.17, y: -188.23, sublevel: 1, group: 14},
          %{x: 361.65, y: -184.61, sublevel: 1, group: 10},
          %{x: 436.73, y: -205.80, sublevel: 1, group: 16},
          %{x: 509.39, y: -203.80, sublevel: 1, group: 23},
          %{x: 505.22, y: -149.16, sublevel: 1, group: 25},
          %{x: 505.61, y: -141.88, sublevel: 1, group: 25},
          %{x: 509.41, y: -167.46, sublevel: 1, group: 24},
          %{x: 509.85, y: -179.89, sublevel: 1, group: 24},
          %{x: 655.32, y: -124.84, sublevel: 1, group: 28},
          %{x: 652.92, y: -131.89, sublevel: 1, group: 28}
        ],
      },
      %{
        name: "Lightward Healer",
        id: 234486,
        count: 5,
        health: 1291018,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1254306, name: "Power Word: Shield", dispellable: true},
          %{id: 1255187, name: "Holy Fire", dispellable: true}
        ],
        positions: [
          %{x: 114.56, y: -143.60, sublevel: 1, group: 2},
          %{x: 146.29, y: -212.51, sublevel: 1, group: 4},
          %{x: 387.44, y: -158.24, sublevel: 1, group: 12},
          %{x: 407.79, y: -195.00, sublevel: 1, group: 14},
          %{x: 368.98, y: -191.57, sublevel: 1, group: 10},
          %{x: 429.02, y: -197.92, sublevel: 1, group: 16},
          %{x: 432.91, y: -138.68, sublevel: 1, group: 17},
          %{x: 516.52, y: -196.79, sublevel: 1, group: 23},
          %{x: 593.28, y: -116.14, sublevel: 1, group: 26},
          %{x: 600.88, y: -118.64, sublevel: 1, group: 26},
          %{x: 649.86, y: -138.81, sublevel: 1, group: 28},
          %{x: 678.96, y: -138.04, sublevel: 1, group: 29}
        ],
      },
      %{
        name: "Gemellus",
        id: 239636,
        count: 0,
        health: 17403431,
        creature_type: "Not specified",
        is_boss: true,
        encounter_id: 2659,
        spells: [
          %{id: 1223936, name: "Synaptic Nexus"},
          %{id: 1224104, name: "Void Secretions"},
          %{id: 1224299, name: "Astral Grasp"},
          %{id: 1224401, name: "Cosmic Radiation"},
          %{id: 1253707, name: "Neural Link"},
          %{id: 1253709, name: "Neural Link"},
          %{id: 1284954, name: "Cosmic Sting"},
          %{id: 1284958, name: "Cosmic Sting"}
        ],
        positions: [
          %{x: 517.79, y: -403.94, sublevel: 1, group: 60}
        ],
      },
      %{
        name: "Void-Infused Brightscale",
        id: 241354,
        count: 1,
        health: 276154,
        creature_type: "Beast",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 632.15, y: -402.29, sublevel: 1, group: 40},
          %{x: 634.52, y: -402.42, sublevel: 1, group: 40},
          %{x: 636.63, y: -402.29, sublevel: 1, group: 40},
          %{x: 638.87, y: -402.41, sublevel: 1, group: 40},
          %{x: 641.60, y: -402.42, sublevel: 1, group: 40},
          %{x: 631.53, y: -406.77, sublevel: 1, group: 40},
          %{x: 634.14, y: -406.77, sublevel: 1, group: 40},
          %{x: 636.75, y: -406.52, sublevel: 1, group: 40},
          %{x: 639.12, y: -406.64, sublevel: 1, group: 40},
          %{x: 641.85, y: -406.89, sublevel: 1, group: 40}
        ],
      },
      %{
        name: "Celestial Drifter",
        id: 241397,
        count: 0,
        health: 1822614,
        creature_type: "Not specified",
        is_boss: true,
        encounter_id: 2659,
        spells: [
          %{id: 1248015, name: "Astral Scouting"}
        ],
        positions: [
          %{x: 495.19, y: -418.55, sublevel: 1, group: 60}
        ],
      },
      %{
        name: "Unstable Voidling",
        id: 255376,
        count: 0,
        health: 227827,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1248229, name: "Void Infusion"},
          %{id: 1264951, name: "Void Eruption"}
        ],
        positions: [
          %{x: 656.42, y: -414.69, sublevel: 1, group: 38},
          %{x: 653.03, y: -413.18, sublevel: 1, group: 38},
          %{x: 656.56, y: -424.87, sublevel: 1, group: 38},
          %{x: 652.67, y: -425.76, sublevel: 1, group: 38},
          %{x: 649.33, y: -424.30, sublevel: 1, group: 38},
          %{x: 649.42, y: -414.52, sublevel: 1, group: 38}
        ],
      },
      %{
        name: "Hollowsoul Shredder",
        id: 257447,
        count: 5,
        health: 1442903,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1227020, name: "Dimensional Shred"},
          %{id: 1248229, name: "Void Infusion"}
        ],
        positions: [
          %{x: 369.65, y: -507.38, sublevel: 1, group: 48},
          %{x: 370.05, y: -492.42, sublevel: 1, group: 48}
        ],
      },
      %{
        name: "Spellwoven Familiar",
        id: 259387,
        count: 1,
        health: 1063192,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 1279994, name: "Blink"},
          %{id: 1279995, name: "Blink"}
        ],
        positions: [
          %{x: 385.36, y: -171.44, sublevel: 1, group: 11},
          %{x: 414.47, y: -195.26, sublevel: 1, group: 14},
          %{x: 361.71, y: -191.95, sublevel: 1, group: 10},
          %{x: 436.54, y: -198.07, sublevel: 1, group: 16},
          %{x: 439.86, y: -146.25, sublevel: 1, group: 17},
          %{x: 439.61, y: -138.73, sublevel: 1, group: 17},
          %{x: 487.85, y: -194.32, sublevel: 1, group: 22},
          %{x: 492.72, y: -198.10, sublevel: 1, group: 22},
          %{x: 492.54, y: -205.36, sublevel: 1, group: 22},
          %{x: 512.08, y: -137.97, sublevel: 1, group: 25},
          %{x: 511.56, y: -153.52, sublevel: 1, group: 25},
          %{x: 635.87, y: -117.15, sublevel: 1, group: 27},
          %{x: 658.16, y: -117.57, sublevel: 1, group: 28}
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
