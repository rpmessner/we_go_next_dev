defmodule WeGoNext.GameData.Dungeons.SeatOfTheTriumvirate do
  @moduledoc "Static data for Seat of the Triumvirate (MDT index 11)."

  def info do
    %{
      name: "Seat of the Triumvirate",
      slug: "seat_of_the_triumvirate",
      mdt_index: 11,
      map_id: 239,
      total_count: 568,
      floors: 1,
    }
  end

  def enemies do
    [
      %{
        name: "Merciless Subjugator",
        id: 124171,
        count: 10,
        health: 1974499,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1262506, name: "Leeching Void"},
          %{id: 1262509, name: "Chains of Subjugation"},
          %{id: 1277343, name: "Chains of Subjugation"}
        ],
        positions: [
          %{x: 300.43, y: -423.00, sublevel: 1, group: 19},
          %{x: 270.53, y: -344.23, sublevel: 1, group: 22},
          %{x: 248.69, y: -255.70, sublevel: 1, group: 27},
          %{x: 196.42, y: -454.88, sublevel: 1, group: 3},
          %{x: 153.70, y: -448.28, sublevel: 1, group: 4},
          %{x: 205.62, y: -421.57, sublevel: 1, group: 10},
          %{x: 159.81, y: -410.44, sublevel: 1, group: 7}
        ],
      },
      %{
        name: "Rift Warden",
        id: 122571,
        count: 20,
        health: 2885806,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1264505, name: "Enveloping Darkness"},
          %{id: 1264532, name: "Void Expulsion"},
          %{id: 1264569, name: "Void Expulsion"},
          %{id: 1280330, name: "Rift Essence", dispellable: true}
        ],
        positions: [
          %{x: 166.12, y: -304.67, sublevel: 1, group: 13},
          %{x: 245.32, y: -302.06, sublevel: 1, group: 15},
          %{x: 272.43, y: -381.61, sublevel: 1, group: 18},
          %{x: 261.42, y: -198.20, sublevel: 1, group: 36}
        ],
      },
      %{
        name: "Ruthless Riftstalker",
        id: 122413,
        count: 9,
        health: 1594787,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1262519, name: "Backstab"},
          %{id: 1277339, name: "Shadowmend"},
          %{id: 1277340, name: "Shadowmend", interruptible: true}
        ],
        positions: [
          %{x: 161.62, y: -324.83, sublevel: 1, group: 12},
          %{x: 192.03, y: -316.22, sublevel: 1, group: 14},
          %{x: 188.59, y: -307.90, sublevel: 1, group: 14},
          %{x: 270.28, y: -291.85, sublevel: 1, group: 25},
          %{x: 241.91, y: -228.72, sublevel: 1, group: 28},
          %{x: 242.33, y: -237.74, sublevel: 1, group: 28},
          %{x: 276.81, y: -175.28, sublevel: 1, group: 37},
          %{x: 347.13, y: -233.31, sublevel: 1, group: 35},
          %{x: 350.00, y: -225.07, sublevel: 1, group: 35},
          %{x: 346.73, y: -216.73, sublevel: 1, group: 35},
          %{x: 338.67, y: -235.28, sublevel: 1, group: 35},
          %{x: 302.10, y: -220.48, sublevel: 1, group: 34},
          %{x: 323.36, y: -218.20, sublevel: 1, group: 34},
          %{x: 277.53, y: -221.98, sublevel: 1, group: 33},
          %{x: 286.89, y: -220.33, sublevel: 1, group: 33},
          %{x: 354.13, y: -133.03, sublevel: 1, group: 41},
          %{x: 349.40, y: -66.16, sublevel: 1, group: 45}
        ],
      },
      %{
        name: "Ravenous Umbralfin",
        id: 255320,
        count: 8,
        health: 1442903,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1264670, name: "Devouring Frenzy"},
          %{id: 1264678, name: "Devouring Frenzy"}
        ],
        positions: [
          %{x: 191.01, y: -285.49, sublevel: 1, group: 23},
          %{x: 182.53, y: -279.20, sublevel: 1, group: 23},
          %{x: 214.52, y: -267.13, sublevel: 1, group: 24},
          %{x: 217.49, y: -275.24, sublevel: 1, group: 24},
          %{x: 233.44, y: -384.33, sublevel: 1, group: 17},
          %{x: 248.18, y: -384.76, sublevel: 1, group: 17},
          %{x: 289.28, y: -420.67, sublevel: 1, group: 19},
          %{x: 288.92, y: -430.43, sublevel: 1, group: 19},
          %{x: 298.93, y: -434.08, sublevel: 1, group: 19},
          %{x: 277.54, y: -349.70, sublevel: 1, group: 22},
          %{x: 270.65, y: -355.06, sublevel: 1, group: 22},
          %{x: 238.67, y: -259.37, sublevel: 1, group: 27},
          %{x: 244.67, y: -266.07, sublevel: 1, group: 27},
          %{x: 278.83, y: -231.81, sublevel: 1, group: 33},
          %{x: 288.36, y: -230.24, sublevel: 1, group: 33}
        ],
      },
      %{
        name: "Umbral War-Adept",
        id: 122421,
        count: 15,
        health: 2733921,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1269183, name: "Void Burst"},
          %{id: 1280326, name: "Void Bash"}
        ],
        positions: [
          %{x: 153.31, y: -331.84, sublevel: 1, group: 12},
          %{x: 301.60, y: -363.82, sublevel: 1, group: 21},
          %{x: 267.93, y: -258.30, sublevel: 1, group: 26},
          %{x: 250.12, y: -233.57, sublevel: 1, group: 28},
          %{x: 263.68, y: -178.51, sublevel: 1, group: 37},
          %{x: 339.01, y: -224.57, sublevel: 1, group: 35},
          %{x: 312.38, y: -216.09, sublevel: 1, group: 34}
        ],
      },
      %{
        name: "Dire Voidbender",
        id: 122404,
        count: 8,
        health: 1442903,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1262526, name: "Abyssal Enhancement", interruptible: true, dispellable: true},
          %{id: 1262527, name: "Abyssal Enhancement"}
        ],
        positions: [
          %{x: 300.69, y: -148.76, sublevel: 1, group: 38},
          %{x: 307.42, y: -156.91, sublevel: 1, group: 38},
          %{x: 358.01, y: -124.67, sublevel: 1, group: 41},
          %{x: 363.39, y: -132.03, sublevel: 1, group: 41},
          %{x: 341.69, y: -59.14, sublevel: 1, group: 45},
          %{x: 357.07, y: -73.77, sublevel: 1, group: 45},
          %{x: 451.51, y: -45.55, sublevel: 1, group: 48},
          %{x: 445.03, y: -38.28, sublevel: 1, group: 48},
          %{x: 409.15, y: -75.06, sublevel: 1, group: 46},
          %{x: 419.59, y: -76.28, sublevel: 1, group: 46}
        ],
      },
      %{
        name: "Void-Infused Destroyer",
        id: 252756,
        count: 15,
        health: 2733921,
        creature_type: "Mechanical",
        is_boss: false,
        spells: [
          %{id: 1262335, name: "Void Cleave"},
          %{id: 1262429, name: "Eruption"},
          %{id: 1262441, name: "Eruption"}
        ],
        positions: [
          %{x: 311.70, y: -144.97, sublevel: 1, group: 38},
          %{x: 333.54, y: -153.43, sublevel: 1, group: 40},
          %{x: 310.65, y: -123.58, sublevel: 1, group: 39},
          %{x: 381.69, y: -73.23, sublevel: 1, group: 43},
          %{x: 394.13, y: -89.05, sublevel: 1, group: 43},
          %{x: 366.37, y: -96.21, sublevel: 1, group: 42}
        ],
      },
      %{
        name: "Grand Shadow-Weaver",
        id: 122423,
        count: 15,
        health: 2202325,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1262508, name: "Void Infusion"},
          %{id: 1264286, name: "Gate of the Abyss"}
        ],
        positions: [
          %{x: 453.93, y: -96.52, sublevel: 1, group: 47},
          %{x: 468.26, y: -83.38, sublevel: 1, group: 47},
          %{x: 455.57, y: -35.39, sublevel: 1, group: 48},
          %{x: 403.19, y: -24.57, sublevel: 1, group: 50}
        ],
      },
      %{
        name: "Viceroy Nezhar",
        id: 122056,
        count: 0,
        health: 11074911,
        creature_type: "Humanoid",
        is_boss: true,
        encounter_id: 2811,
        spells: [
          %{id: 244750, name: "Mind Blast", interruptible: true},
          %{id: 246913, name: "Void Phased"},
          %{id: 1263528, name: "Repulse"},
          %{id: 1263529, name: "Collapsing Void"},
          %{id: 1263532, name: "Void Storm"},
          %{id: 1263538, name: "Umbral Tentacles"},
          %{id: 1263542, name: "Mass Void Infusion"}
        ],
        positions: [
          %{x: 427.36, y: -55.23, sublevel: 1, group: 49}
        ],
      },
      %{
        name: "Zuraal the Ascended",
        id: 122313,
        count: 0,
        health: 8859929,
        creature_type: "Humanoid",
        is_boss: true,
        encounter_id: 2811,
        spells: [
          %{id: 244579, name: "Decimate"},
          %{id: 1263282, name: "Decimate"},
          %{id: 1263297, name: "Crashing Void"},
          %{id: 1263399, name: "Oozing Slam"},
          %{id: 1263440, name: "Void Slash"},
          %{id: 1263484, name: "Void Slash"},
          %{id: 1263492, name: "Void Slash"},
          %{id: 1263494, name: "Void Slash"},
          %{id: 1268916, name: "Null Palm"}
        ],
        positions: [
          %{x: 74.56, y: -438.75, sublevel: 1, group: 11}
        ],
      },
      %{
        name: "Saprish",
        id: 122316,
        count: 0,
        health: 23731952,
        creature_type: "Humanoid",
        is_boss: true,
        encounter_id: 2811,
        spells: [
          %{id: 246943, name: "Dark Bond"},
          %{id: 1263523, name: "Overload"},
          %{id: 1280065, name: "Phase Dash"}
        ],
        positions: [
          %{x: 237.62, y: -121.86, sublevel: 1, group: 31}
        ],
      },
      %{
        name: "Darkfang",
        id: 122319,
        count: 0,
        health: 23731952,
        creature_type: "Beast",
        is_boss: true,
        encounter_id: 2811,
        spells: [
          %{id: 245742, name: "Shadow Pounce"},
          %{id: 246943, name: "Dark Bond"}
        ],
        positions: [
          %{x: 248.56, y: -152.24, sublevel: 1, group: 31}
        ],
      },
      %{
        name: "Famished Broken",
        id: 122322,
        count: 1,
        health: 607538,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1269468, name: "Rupture"},
          %{id: 1269469, name: "Rupture"},
          %{id: 1269470, name: "Rupture"}
        ],
        positions: [
          %{x: 184.87, y: -247.10, sublevel: 1, group: 30},
          %{x: 166.59, y: -475.43, sublevel: 1, group: 1},
          %{x: 173.16, y: -476.42, sublevel: 1, group: 1},
          %{x: 179.26, y: -473.87, sublevel: 1, group: 1},
          %{x: 160.84, y: -474.86, sublevel: 1, group: 1},
          %{x: 155.20, y: -471.36, sublevel: 1, group: 1},
          %{x: 191.04, y: -402.27, sublevel: 1, group: 9},
          %{x: 192.51, y: -394.99, sublevel: 1, group: 9},
          %{x: 198.45, y: -391.19, sublevel: 1, group: 9},
          %{x: 202.97, y: -386.35, sublevel: 1, group: 9},
          %{x: 209.57, y: -385.54, sublevel: 1, group: 9},
          %{x: 197.55, y: -476.99, sublevel: 1, group: 2},
          %{x: 199.89, y: -483.43, sublevel: 1, group: 2},
          %{x: 211.96, y: -488.38, sublevel: 1, group: 2},
          %{x: 206.46, y: -483.99, sublevel: 1, group: 2},
          %{x: 218.49, y: -485.55, sublevel: 1, group: 2},
          %{x: 128.70, y: -471.59, sublevel: 1, group: 5},
          %{x: 134.72, y: -468.44, sublevel: 1, group: 5},
          %{x: 140.83, y: -464.99, sublevel: 1, group: 5},
          %{x: 128.72, y: -464.59, sublevel: 1, group: 5},
          %{x: 134.73, y: -461.80, sublevel: 1, group: 5},
          %{x: 135.46, y: -422.76, sublevel: 1, group: 6},
          %{x: 132.56, y: -447.68, sublevel: 1, group: 6},
          %{x: 130.19, y: -435.32, sublevel: 1, group: 6},
          %{x: 130.30, y: -427.80, sublevel: 1, group: 6},
          %{x: 128.57, y: -442.31, sublevel: 1, group: 6},
          %{x: 145.08, y: -394.43, sublevel: 1, group: 8},
          %{x: 148.20, y: -388.44, sublevel: 1, group: 8},
          %{x: 151.61, y: -382.10, sublevel: 1, group: 8},
          %{x: 151.74, y: -395.09, sublevel: 1, group: 8},
          %{x: 154.74, y: -387.80, sublevel: 1, group: 8},
          %{x: 191.10, y: -242.97, sublevel: 1, group: 30},
          %{x: 197.41, y: -238.32, sublevel: 1, group: 30},
          %{x: 191.07, y: -250.32, sublevel: 1, group: 30},
          %{x: 198.10, y: -245.23, sublevel: 1, group: 30},
          %{x: 323.54, y: -394.99, sublevel: 1, group: 20},
          %{x: 328.84, y: -397.98, sublevel: 1, group: 20},
          %{x: 333.32, y: -402.20, sublevel: 1, group: 20},
          %{x: 323.13, y: -400.67, sublevel: 1, group: 20},
          %{x: 327.67, y: -403.82, sublevel: 1, group: 20},
          %{x: 215.63, y: -189.25, sublevel: 1, group: 32},
          %{x: 220.30, y: -187.06, sublevel: 1, group: 32},
          %{x: 225.48, y: -184.47, sublevel: 1, group: 32},
          %{x: 220.30, y: -192.33, sublevel: 1, group: 32},
          %{x: 225.08, y: -189.84, sublevel: 1, group: 32}
        ],
      },
      %{
        name: "Shadowguard Champion",
        id: 122403,
        count: 3,
        health: 1670730,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1262517, name: "Relentless Pursuit"},
          %{id: 1264036, name: "Battle Rage"}
        ],
        positions: [
          %{x: 163.91, y: -334.44, sublevel: 1, group: 12},
          %{x: 163.74, y: -466.97, sublevel: 1, group: 1},
          %{x: 172.64, y: -468.54, sublevel: 1, group: 1},
          %{x: 191.37, y: -445.49, sublevel: 1, group: 3},
          %{x: 185.38, y: -454.28, sublevel: 1, group: 3},
          %{x: 161.08, y: -437.38, sublevel: 1, group: 4},
          %{x: 166.17, y: -449.20, sublevel: 1, group: 4},
          %{x: 195.77, y: -423.69, sublevel: 1, group: 10},
          %{x: 171.01, y: -413.10, sublevel: 1, group: 7},
          %{x: 199.25, y: -400.14, sublevel: 1, group: 9},
          %{x: 206.05, y: -393.69, sublevel: 1, group: 9},
          %{x: 205.21, y: -475.14, sublevel: 1, group: 2},
          %{x: 212.98, y: -479.27, sublevel: 1, group: 2},
          %{x: 138.10, y: -430.76, sublevel: 1, group: 6},
          %{x: 137.34, y: -440.50, sublevel: 1, group: 6},
          %{x: 197.05, y: -276.61, sublevel: 1, group: 23},
          %{x: 189.03, y: -270.08, sublevel: 1, group: 23},
          %{x: 241.11, y: -330.76, sublevel: 1, group: 16},
          %{x: 248.90, y: -326.74, sublevel: 1, group: 16},
          %{x: 247.10, y: -377.37, sublevel: 1, group: 17},
          %{x: 236.73, y: -375.78, sublevel: 1, group: 17},
          %{x: 288.08, y: -363.17, sublevel: 1, group: 21},
          %{x: 293.18, y: -374.06, sublevel: 1, group: 21},
          %{x: 262.56, y: -268.37, sublevel: 1, group: 26},
          %{x: 271.78, y: -268.84, sublevel: 1, group: 26},
          %{x: 218.10, y: -242.03, sublevel: 1, group: 29},
          %{x: 227.94, y: -244.18, sublevel: 1, group: 29},
          %{x: 318.60, y: -227.08, sublevel: 1, group: 34},
          %{x: 308.66, y: -227.56, sublevel: 1, group: 34},
          %{x: 347.17, y: -77.31, sublevel: 1, group: 45},
          %{x: 339.30, y: -69.29, sublevel: 1, group: 45}
        ],
      },
      %{
        name: "Dark Conjurer",
        id: 122405,
        count: 7,
        health: 1291018,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1262510, name: "Umbral Bolt", interruptible: true},
          %{id: 1262522, name: "Pulsing Void"},
          %{id: 1262523, name: "Summon Voidcaller", interruptible: true}
        ],
        positions: [
          %{x: 250.20, y: -335.24, sublevel: 1, group: 16},
          %{x: 201.21, y: -431.53, sublevel: 1, group: 10},
          %{x: 164.74, y: -420.10, sublevel: 1, group: 7},
          %{x: 243.74, y: -366.56, sublevel: 1, group: 17},
          %{x: 278.33, y: -284.65, sublevel: 1, group: 25},
          %{x: 219.67, y: -252.28, sublevel: 1, group: 29},
          %{x: 268.36, y: -167.46, sublevel: 1, group: 37},
          %{x: 371.15, y: -115.32, sublevel: 1, group: 44},
          %{x: 378.66, y: -123.23, sublevel: 1, group: 44},
          %{x: 409.23, y: -34.29, sublevel: 1, group: 50},
          %{x: 398.47, y: -34.68, sublevel: 1, group: 50}
        ],
      },
      %{
        name: "Bound Voidcaller",
        id: 122412,
        count: 0,
        health: 759423,
        creature_type: "Aberration",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 210.18, y: -431.40, sublevel: 1, group: 10},
          %{x: 168.16, y: -405.93, sublevel: 1, group: 7},
          %{x: 243.50, y: -338.33, sublevel: 1, group: 16},
          %{x: 240.23, y: -385.64, sublevel: 1, group: 17},
          %{x: 278.74, y: -294.27, sublevel: 1, group: 25},
          %{x: 227.55, y: -251.97, sublevel: 1, group: 29},
          %{x: 273.14, y: -183.54, sublevel: 1, group: 37},
          %{x: 376.82, y: -110.94, sublevel: 1, group: 44},
          %{x: 383.14, y: -117.56, sublevel: 1, group: 44},
          %{x: 393.70, y: -26.39, sublevel: 1, group: 50},
          %{x: 413.21, y: -25.55, sublevel: 1, group: 50}
        ],
      },
      %{
        name: "Coalesced Void",
        id: 122716,
        count: 0,
        health: 349334,
        creature_type: "Aberration",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 95.75, y: -431.97, sublevel: 1, group: 11},
          %{x: 95.21, y: -445.39, sublevel: 1, group: 11},
          %{x: 88.29, y: -457.81, sublevel: 1, group: 11}
        ],
      },
      %{
        name: "Umbral Tentacle",
        id: 122827,
        count: 0,
        health: 209199,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 249082, name: "Unstable Entrance"},
          %{id: 1268733, name: "Mind Flay"}
        ],
        positions: [
          %{x: 442.49, y: -61.39, sublevel: 1, group: 49},
          %{x: 438.51, y: -69.35, sublevel: 1, group: 49}
        ],
      },
      %{
        name: "L'ura",
        id: 124729,
        count: 0,
        health: 22016924,
        creature_type: "Not specified",
        is_boss: true,
        encounter_id: 2811,
        spells: [
          %{id: 1264159, name: "Disintegrate"},
          %{id: 1264196, name: "Disintegrate"},
          %{id: 1265419, name: "Notes of Despair"},
          %{id: 1265420, name: "Note of Despair"},
          %{id: 1265421, name: "Dirge of Despair"},
          %{id: 1265426, name: "Discordant Beam"},
          %{id: 1265463, name: "Discordant Beam"},
          %{id: 1265689, name: "Grim Chorus"},
          %{id: 1265999, name: "Siphon Void"},
          %{id: 1266001, name: "Backlash"},
          %{id: 1266003, name: "Symphony of the Eternal Night"},
          %{id: 1267207, name: "Abyssal Lance"},
          %{id: 1267274, name: "Void Portal"},
          %{id: 1268598, name: "Abyssal Lance"},
          %{id: 1268646, name: "Abyssal Lance"},
          %{id: 1268647, name: "Abyssal Lance"}
        ],
        positions: [
          %{x: 570.24, y: -189.15, sublevel: 1, group: 51}
        ],
      },
      %{
        name: "Shadewing",
        id: 125340,
        count: 0,
        health: 23731952,
        creature_type: "Beast",
        is_boss: true,
        encounter_id: 2811,
        spells: [
          %{id: 246943, name: "Dark Bond"},
          %{id: 248829, name: "Swoop"},
          %{id: 248830, name: "Swoop"},
          %{id: 248831, name: "Dread Screech", interruptible: true}
        ],
        positions: [
          %{x: 222.83, y: -152.39, sublevel: 1, group: 31}
        ],
      },
      %{
        name: "Depravation Wave Stalker",
        id: 255551,
        count: 0,
        health: 197939,
        creature_type: "Not specified",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 585.25, y: -206.41, sublevel: 1, group: 51},
          %{x: 592.74, y: -193.23, sublevel: 1, group: 51},
          %{x: 589.75, y: -178.80, sublevel: 1, group: 51},
          %{x: 572.84, y: -213.13, sublevel: 1, group: 51}
        ],
      },
      %{
        name: "Void Tentacle",
        id: 256424,
        count: 0,
        health: 303769,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1269081, name: "Void Slam"}
        ],
        positions: [
          %{x: 329.88, y: -310.85, sublevel: 1},
          %{x: 119.61, y: -307.16, sublevel: 1}
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
