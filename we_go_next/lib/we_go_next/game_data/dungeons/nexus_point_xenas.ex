defmodule WeGoNext.GameData.Dungeons.NexusPointXenas do
  @moduledoc "Static data for Nexus Point Xenas (MDT index 155)."

  def info do
    %{
      name: "Nexus Point Xenas",
      slug: "nexus_point_xenas",
      mdt_index: 155,
      map_id: 559,
      total_count: 596,
      floors: 1,
    }
  end

  def enemies do
    [
      %{
        name: "Shadowguard Defender",
        id: 241643,
        count: 5,
        health: 1549222,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1249645, name: "Null Sunder"},
          %{id: 1252218, name: "Leech Veil"},
          %{id: 1282745, name: "Null Sunder"}
        ],
        positions: [
          %{x: 398.11, y: -374.23, sublevel: 1, group: 3},
          %{x: 407.15, y: -369.60, sublevel: 1, group: 3},
          %{x: 476.90, y: -354.04, sublevel: 1, group: 4},
          %{x: 477.24, y: -364.23, sublevel: 1, group: 4},
          %{x: 443.98, y: -362.88, sublevel: 1, group: 1},
          %{x: 335.53, y: -365.86, sublevel: 1, group: 24},
          %{x: 338.01, y: -376.31, sublevel: 1, group: 24},
          %{x: 290.75, y: -338.00, sublevel: 1, group: 27},
          %{x: 295.23, y: -346.96, sublevel: 1, group: 27},
          %{x: 279.81, y: -323.57, sublevel: 1, group: 32},
          %{x: 235.03, y: -339.49, sublevel: 1, group: 30},
          %{x: 242.49, y: -318.10, sublevel: 1, group: 31},
          %{x: 235.53, y: -323.57, sublevel: 1, group: 31},
          %{x: 262.39, y: -294.72, sublevel: 1, group: 34},
          %{x: 217.73, y: -252.34, sublevel: 1, group: 40}
        ],
      },
      %{
        name: "Reformed Voidling",
        id: 248501,
        count: 1,
        health: 637915,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1252218, name: "Leech Veil"}
        ],
        positions: [
          %{x: 527.46, y: -372.14, sublevel: 1, group: 5},
          %{x: 527.07, y: -381.78, sublevel: 1, group: 5},
          %{x: 556.92, y: -403.67, sublevel: 1, group: 6},
          %{x: 553.43, y: -394.72, sublevel: 1, group: 6},
          %{x: 564.02, y: -342.23, sublevel: 1, group: 9},
          %{x: 570.85, y: -335.51, sublevel: 1, group: 9},
          %{x: 633.53, y: -340.99, sublevel: 1, group: 11},
          %{x: 631.75, y: -350.62, sublevel: 1, group: 11},
          %{x: 597.71, y: -287.75, sublevel: 1, group: 13},
          %{x: 598.71, y: -277.80, sublevel: 1, group: 13},
          %{x: 605.67, y: -292.73, sublevel: 1, group: 13},
          %{x: 625.50, y: -282.60, sublevel: 1, group: 14},
          %{x: 632.22, y: -290.28, sublevel: 1, group: 14},
          %{x: 663.88, y: -217.11, sublevel: 1, group: 18},
          %{x: 671.84, y: -222.58, sublevel: 1, group: 18},
          %{x: 681.66, y: -180.14, sublevel: 1, group: 21},
          %{x: 701.90, y: -195.04, sublevel: 1, group: 21},
          %{x: 728.80, y: -158.13, sublevel: 1, group: 22}
        ],
      },
      %{
        name: "Corewright Arcanist",
        id: 241644,
        count: 5,
        health: 1458091,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1249815, name: "Transference", dispellable: true},
          %{id: 1249818, name: "Arcane Zap"},
          %{id: 1252218, name: "Leech Veil"},
          %{id: 1277451, name: "Arcane Zap"},
          %{id: 1278882, name: "Arcane Zap"},
          %{id: 1285445, name: "Arcane Explosion", interruptible: true},
          %{id: 1285450, name: "Arcane Explosion"}
        ],
        positions: [
          %{x: 417.79, y: -335.24, sublevel: 1, group: 2},
          %{x: 451.94, y: -361.88, sublevel: 1, group: 1},
          %{x: 271.84, y: -377.80, sublevel: 1, group: 26},
          %{x: 250.95, y: -361.38, sublevel: 1, group: 28},
          %{x: 270.85, y: -327.55, sublevel: 1, group: 32},
          %{x: 219.11, y: -327.06, sublevel: 1, group: 35},
          %{x: 256.42, y: -301.68, sublevel: 1, group: 34},
          %{x: 209.16, y: -245.96, sublevel: 1, group: 40},
          %{x: 210.15, y: -221.58, sublevel: 1, group: 41},
          %{x: 184.28, y: -232.03, sublevel: 1, group: 41}
        ],
      },
      %{
        name: "Hollowsoul Scrounger",
        id: 241645,
        count: 3,
        health: 1215076,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1227020, name: "Dimensional Shred"},
          %{id: 1252204, name: "Leech Veil"},
          %{id: 1252218, name: "Leech Veil"}
        ],
        positions: [
          %{x: 414.20, y: -344.15, sublevel: 1, group: 2},
          %{x: 455.42, y: -355.41, sublevel: 1, group: 1},
          %{x: 579.80, y: -316.61, sublevel: 1, group: 10},
          %{x: 589.25, y: -324.57, sublevel: 1, group: 10},
          %{x: 603.18, y: -356.41, sublevel: 1},
          %{x: 642.98, y: -322.08, sublevel: 1, group: 12},
          %{x: 652.51, y: -316.08, sublevel: 1, group: 12},
          %{x: 642.24, y: -247.92, sublevel: 1, group: 15},
          %{x: 659.90, y: -261.88, sublevel: 1, group: 15},
          %{x: 692.24, y: -264.87, sublevel: 1, group: 16},
          %{x: 686.27, y: -274.32, sublevel: 1, group: 16},
          %{x: 619.10, y: -226.56, sublevel: 1, group: 17},
          %{x: 618.11, y: -242.48, sublevel: 1, group: 17},
          %{x: 693.23, y: -272.33, sublevel: 1, group: 16},
          %{x: 611.14, y: -233.03, sublevel: 1, group: 17},
          %{x: 702.19, y: -184.56, sublevel: 1, group: 21},
          %{x: 693.39, y: -176.58, sublevel: 1, group: 21},
          %{x: 724.08, y: -149.61, sublevel: 1, group: 22}
        ],
      },
      %{
        name: "Flux Engineer",
        id: 241647,
        count: 7,
        health: 1518845,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1257124, name: "Mana Battery"},
          %{id: 1269283, name: "Suppression Field"},
          %{id: 1282950, name: "Suppression Field"}
        ],
        positions: [
          %{x: 294.73, y: -396.21, sublevel: 1, group: 25},
          %{x: 292.24, y: -402.68, sublevel: 1, group: 25},
          %{x: 267.79, y: -385.69, sublevel: 1, group: 26},
          %{x: 251.94, y: -279.79, sublevel: 1, group: 38},
          %{x: 210.15, y: -309.64, sublevel: 1, group: 36},
          %{x: 202.19, y: -311.63, sublevel: 1, group: 36},
          %{x: 207.17, y: -275.81, sublevel: 1, group: 39},
          %{x: 200.20, y: -281.78, sublevel: 1, group: 39}
        ],
      },
      %{
        name: "Nexus Adept",
        id: 248708,
        count: 7,
        health: 759423,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1271094, name: "Umbra Bolt", interruptible: true}
        ],
        positions: [
          %{x: 216.92, y: -242.79, sublevel: 1, group: 40},
          %{x: 262.39, y: -378.80, sublevel: 1, group: 26},
          %{x: 300.20, y: -338.50, sublevel: 1, group: 27},
          %{x: 255.92, y: -293.23, sublevel: 1, group: 34}
        ],
      },
      %{
        name: "Circuit Seer",
        id: 248373,
        count: 15,
        health: 2187135,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1249801, name: "Arcing Mana"},
          %{id: 1249806, name: "Arcing Mana"},
          %{id: 1257100, name: "Circuit Sense"},
          %{id: 1257103, name: "Erratic Surge"},
          %{id: 1257105, name: "Erratic Zap"}
        ],
        positions: [
          %{x: 252.50, y: -345.45, sublevel: 1, group: 29},
          %{x: 269.85, y: -313.13, sublevel: 1, group: 33},
          %{x: 224.08, y: -295.22, sublevel: 1, group: 37},
          %{x: 193.24, y: -218.60, sublevel: 1, group: 41}
        ],
      },
      %{
        name: "Cursed Voidcaller",
        id: 248706,
        count: 3,
        health: 607538,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1252218, name: "Leech Veil"},
          %{id: 1281636, name: "Creeping Void"}
        ],
        positions: [
          %{x: 532.95, y: -379.08, sublevel: 1, group: 5},
          %{x: 587.55, y: -360.53, sublevel: 1, group: 8},
          %{x: 577.92, y: -360.57, sublevel: 1, group: 8},
          %{x: 640.18, y: -287.43, sublevel: 1, group: 14},
          %{x: 626.57, y: -273.33, sublevel: 1, group: 14},
          %{x: 714.13, y: -148.34, sublevel: 1, group: 22}
        ],
      },
      %{
        name: "Dreadflail",
        id: 248506,
        count: 8,
        health: 2582037,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1252218, name: "Leech Veil"},
          %{id: 1252436, name: "Void Lash"},
          %{id: 1252437, name: "Void Lash"},
          %{id: 1252438, name: "Void Lash"},
          %{id: 1252621, name: "Flailstorm"},
          %{id: 1252622, name: "Flailstorm"},
          %{id: 1252628, name: "Flailstorm"}
        ],
        positions: [
          %{x: 649.55, y: -255.72, sublevel: 1, group: 15}
        ],
      },
      %{
        name: "Duskfright Herald",
        id: 241660,
        count: 15,
        health: 1944120,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1252062, name: "Entropic Leech"},
          %{id: 1252076, name: "Dark Beckoning"},
          %{id: 1252134, name: "Dark Beckoning"},
          %{id: 1254096, name: "Forfeit Essence"},
          %{id: 1259359, name: "Devour the Unworthy"}
        ],
        positions: [
          %{x: 567.56, y: -374.62, sublevel: 1, group: 7},
          %{x: 606.67, y: -282.78, sublevel: 1, group: 13},
          %{x: 643.48, y: -311.63, sublevel: 1, group: 12},
          %{x: 691.34, y: -189.05, sublevel: 1, group: 21}
        ],
      },
      %{
        name: "Grand Nullifier",
        id: 251853,
        count: 7,
        health: 1518845,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1252218, name: "Leech Veil"},
          %{id: 1258681, name: "Nullify", interruptible: true},
          %{id: 1258684, name: "Void Ritual"},
          %{id: 1264295, name: "Nullblast"},
          %{id: 1281634, name: "Dusk Frights"},
          %{id: 1281637, name: "Dusk Frights"}
        ],
        positions: [
          %{x: 634.36, y: -278.18, sublevel: 1, group: 14},
          %{x: 686.02, y: -226.44, sublevel: 1, group: 18},
          %{x: 653.25, y: -206.97, sublevel: 1, group: 18},
          %{x: 564.36, y: -396.87, sublevel: 1, group: 6},
          %{x: 561.38, y: -330.20, sublevel: 1, group: 9},
          %{x: 621.08, y: -344.13, sublevel: 1, group: 11}
        ],
      },
      %{
        name: "Null Sentinel",
        id: 248502,
        count: 15,
        health: 2430152,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1252218, name: "Leech Veil"},
          %{id: 1252406, name: "Dreadbellow"},
          %{id: 1252414, name: "Nullwark Blast"},
          %{id: 1252417, name: "Nullwark Blast"},
          %{id: 1252429, name: "Nullwark Blast"}
        ],
        positions: [
          %{x: 583.58, y: -351.84, sublevel: 1, group: 8},
          %{x: 589.82, y: -313.59, sublevel: 1, group: 10},
          %{x: 717.11, y: -159.07, sublevel: 1, group: 22}
        ],
      },
      %{
        name: "Lingering Image",
        id: 241642,
        count: 15,
        health: 2217514,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1257701, name: "Searing Rend"},
          %{id: 1257736, name: "Searing Rend"},
          %{id: 1257745, name: "Searing Rend"},
          %{id: 1257746, name: "Radiant Scar"},
          %{id: 1264354, name: "Luciferin Flare"},
          %{id: 1281657, name: "Blistering Smite"}
        ],
        positions: [
          %{x: 405.91, y: -335.47, sublevel: 1, group: 2},
          %{x: 446.47, y: -351.93, sublevel: 1, group: 1},
          %{x: 671.84, y: -212.63, sublevel: 1, group: 18},
          %{x: 427.76, y: -277.90, sublevel: 1, group: 42},
          %{x: 411.40, y: -184.02, sublevel: 1, group: 51},
          %{x: 451.05, y: -182.83, sublevel: 1, group: 47}
        ],
      },
      %{
        name: "Radiant Swarm",
        id: 254932,
        count: 2,
        health: 531596,
        creature_type: "Not specified",
        is_boss: false,
        spells: [
          %{id: 1263775, name: "Fixate"},
          %{id: 1282944, name: "Cluster Weakness"}
        ],
        positions: [
          %{x: 409.16, y: -272.33, sublevel: 1, group: 44},
          %{x: 407.17, y: -283.28, sublevel: 1, group: 44},
          %{x: 449.95, y: -271.34, sublevel: 1, group: 43},
          %{x: 449.45, y: -284.77, sublevel: 1, group: 43},
          %{x: 348.72, y: -152.95, sublevel: 1, group: 58},
          %{x: 354.38, y: -154.95, sublevel: 1, group: 58},
          %{x: 345.60, y: -159.28, sublevel: 1, group: 58},
          %{x: 352.94, y: -160.58, sublevel: 1, group: 58},
          %{x: 396.18, y: -166.97, sublevel: 1, group: 56},
          %{x: 399.43, y: -173.62, sublevel: 1, group: 56},
          %{x: 496.72, y: -166.36, sublevel: 1, group: 48},
          %{x: 502.10, y: -172.60, sublevel: 1, group: 48},
          %{x: 474.57, y: -171.93, sublevel: 1, group: 49},
          %{x: 469.55, y: -165.26, sublevel: 1, group: 49},
          %{x: 387.27, y: -151.25, sublevel: 1, group: 55},
          %{x: 380.12, y: -149.21, sublevel: 1, group: 55}
        ],
      },
      %{
        name: "Lightwrought",
        id: 254926,
        count: 7,
        health: 1291018,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 1263892, name: "Holy Bolt", interruptible: true},
          %{id: 1277557, name: "Burning Radiance", dispellable: true}
        ],
        positions: [
          %{x: 415.62, y: -220.59, sublevel: 1, group: 45},
          %{x: 440.00, y: -221.58, sublevel: 1, group: 45},
          %{x: 348.05, y: -169.45, sublevel: 1, group: 58},
          %{x: 354.20, y: -145.89, sublevel: 1, group: 58},
          %{x: 392.86, y: -179.05, sublevel: 1, group: 56},
          %{x: 463.41, y: -169.98, sublevel: 1, group: 49}
        ],
      },
      %{
        name: "Flarebat",
        id: 254928,
        count: 3,
        health: 2217514,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1263783, name: "Holy Echo", dispellable: true},
          %{id: 1263785, name: "Holy Echo"}
        ],
        positions: [
          %{x: 399.70, y: -277.31, sublevel: 1, group: 44},
          %{x: 444.98, y: -278.30, sublevel: 1, group: 43},
          %{x: 387.35, y: -169.52, sublevel: 1, group: 56},
          %{x: 429.55, y: -209.15, sublevel: 1, group: 45},
          %{x: 467.68, y: -177.39, sublevel: 1, group: 49}
        ],
      },
      %{
        name: "Kasreth",
        id: 241539,
        count: 0,
        health: 9967420,
        creature_type: "Humanoid",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1250553, name: "Arcane Zap"},
          %{id: 1251626, name: "Leyline Array"},
          %{id: 1251767, name: "Reflux Charge"},
          %{id: 1251772, name: "Reflux Charge"},
          %{id: 1257509, name: "Corespark Detonation"},
          %{id: 1257512, name: "Corespark Detonation"},
          %{id: 1257524, name: "Corespark Detonation"},
          %{id: 1264040, name: "Flux Collapse"},
          %{id: 1264042, name: "Arcane Spill"},
          %{id: 1264048, name: "Flux Collapse"},
          %{id: 1265894, name: "Corespark Detonation"},
          %{id: 1276485, name: "Sparkburn"},
          %{id: 1282915, name: "Reflux Charge"}
        ],
        positions: [
          %{x: 177.61, y: -179.10, sublevel: 1}
        ],
      },
      %{
        name: "Corewarden Nysarra",
        id: 241542,
        count: 0,
        health: 31642602,
        creature_type: "Aberration",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1247937, name: "Umbral Lash"},
          %{id: 1248007, name: "Umbral Lash"},
          %{id: 1249014, name: "Eclipsing Step"},
          %{id: 1249027, name: "Eclipsing Step"},
          %{id: 1252875, name: "Eclipsing Step"},
          %{id: 1252883, name: "Devour the Unworthy"},
          %{id: 1254096, name: "Forfeit Essence"},
          %{id: 1259359, name: "Devour the Unworthy"},
          %{id: 1271433, name: "Lightscar Flare"}
        ],
        positions: [
          %{x: 744.41, y: -121.82, sublevel: 1, group: 23}
        ],
      },
      %{
        name: "Lothraxion",
        id: 241546,
        count: 0,
        health: 12657041,
        creature_type: "Humanoid",
        is_boss: true,
        encounter_id: 2658,
        spells: [
          %{id: 1253855, name: "Brilliant Dispersion"},
          %{id: 1253950, name: "Searing Rend"},
          %{id: 1255208, name: "Searing Rend"},
          %{id: 1255310, name: "Radiant Scar"},
          %{id: 1255335, name: "Searing Rend"},
          %{id: 1255503, name: "Brilliant Dispersion"},
          %{id: 1257595, name: "Divine Guile"},
          %{id: 1257613, name: "Divine Guile"},
          %{id: 1271511, name: "Core Exposure"},
          %{id: 1282791, name: "Mirrored Rend"}
        ],
        positions: [
          %{x: 432.53, y: -138.81, sublevel: 1, group: 50}
        ],
      },
      %{
        name: "Smudge",
        id: 248769,
        count: 0,
        health: 151885,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 1257268, name: "Forfeit Essence"}
        ],
        positions: [

        ],
      },
      %{
        name: "[DNT] Conduit Stalker",
        id: 250299,
        count: 0,
        health: 253141,
        creature_type: "Not specified",
        is_boss: false,
        spells: [
          %{id: 1251579, name: "Leyline Array"}
        ],
        positions: [

        ],
      },
      %{
        name: "Null Guardian",
        id: 251024,
        count: 0,
        health: 556910,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1282663, name: "Melee"},
          %{id: 1282664, name: "Melee"},
          %{id: 1282665, name: "Void Lash"},
          %{id: 1282678, name: "Flailstorm"},
          %{id: 1282679, name: "Flailstorm"}
        ],
        positions: [

        ],
      },
      %{
        name: "Wretched Supplicant",
        id: 251031,
        count: 0,
        health: 326286,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1282722, name: "Nullify", interruptible: true},
          %{id: 1282723, name: "Dusk Frights"}
        ],
        positions: [

        ],
      },
      %{
        name: "Fractured Image",
        id: 251568,
        count: 0,
        health: 120838,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1255310, name: "Radiant Scar"},
          %{id: 1255533, name: "Flicker"},
          %{id: 1257601, name: "Divine Guile", interruptible: true},
          %{id: 1269220, name: "Mirrored Rend"},
          %{id: 1269222, name: "Flicker"},
          %{id: 1271956, name: "Mirrored Rend"}
        ],
        positions: [
          %{x: 422.82, y: -122.91, sublevel: 1, group: 50},
          %{x: 434.53, y: -124.07, sublevel: 1, group: 50}
        ],
      },
      %{
        name: "Nullifier",
        id: 251852,
        count: 0,
        health: 552308,
        creature_type: "Aberration",
        is_boss: false,
        spells: [

        ],
        positions: [

        ],
      },
      %{
        name: "Voidcaller",
        id: 251878,
        count: 0,
        health: 1380770,
        creature_type: "Aberration",
        is_boss: false,
        spells: [

        ],
        positions: [

        ],
      },
      %{
        name: "Mana Battery",
        id: 252825,
        count: 0,
        health: 227827,
        creature_type: "Not specified",
        is_boss: false,
        spells: [
          %{id: 1257126, name: "Corespark Overload"}
        ],
        positions: [

        ],
      },
      %{
        name: "Corespark Conduit",
        id: 252852,
        count: 0,
        health: 729045,
        creature_type: "Not specified",
        is_boss: false,
        spells: [

        ],
        positions: [

        ],
      },
      %{
        name: "Corewarden Nysarra",
        id: 254227,
        count: 0,
        health: 72904560,
        creature_type: "Aberration",
        is_boss: false,
        spells: [
          %{id: 1271388, name: "Umbral Lash"}
        ],
        positions: [
          %{x: 759.94, y: -115.60, sublevel: 1, group: 23},
          %{x: 760.59, y: -125.07, sublevel: 1, group: 23},
          %{x: 756.51, y: -135.02, sublevel: 1, group: 23}
        ],
      },
      %{
        name: "Broken Pipe",
        id: 254459,
        count: 0,
        health: 150698,
        creature_type: "Not specified",
        is_boss: false,
        spells: [
          %{id: 1262088, name: "Flux Collapse"},
          %{id: 1262630, name: "Arcane Spill"}
        ],
        positions: [

        ],
      },
      %{
        name: "Corespark Pylon",
        id: 254485,
        count: 0,
        health: 268941,
        creature_type: "Not specified",
        is_boss: false,
        spells: [
          %{id: 1262084, name: "Flux Collapse"},
          %{id: 1262088, name: "Flux Collapse"},
          %{id: 1262630, name: "Arcane Spill"}
        ],
        positions: [

        ],
      },
      %{
        name: "Fractured Image",
        id: 255179,
        count: 0,
        health: 113415,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1264429, name: "Lightscar Flare"},
          %{id: 1265984, name: "Lightscar Flare"}
        ],
        positions: [
          %{x: 449.54, y: -135.76, sublevel: 1, group: 50},
          %{x: 444.48, y: -129.05, sublevel: 1, group: 50}
        ],
      },
      %{
        name: "Mana Battery",
        id: 259569,
        count: 0,
        health: 268941,
        creature_type: "Not specified",
        is_boss: false,
        spells: [
          %{id: 1257126, name: "Corespark Overload"}
        ],
        positions: [

        ],
      },
      %{
        name: "Core Technician",
        id: 249711,
        count: 0,
        health: 534633,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 405.47, y: -345.52, sublevel: 1, group: 2}
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
