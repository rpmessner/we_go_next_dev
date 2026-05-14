defmodule WeGoNext.GameData.Dungeons.Skyreach do
  @moduledoc "Static data for Skyreach (MDT index 151)."

  def info do
    %{
      name: "Skyreach",
      slug: "skyreach",
      mdt_index: 151,
      map_id: 161,
      total_count: 431,
      floors: 1,
    }
  end

  def enemies do
    [
      %{
        name: "Soaring Chakram Master",
        id: 76132,
        count: 5,
        health: 1518845,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1254666, name: "Ricocheting Chakram"}
        ],
        positions: [
          %{x: 297.11, y: -93.16, sublevel: 1, group: 1},
          %{x: 330.89, y: -175.87, sublevel: 1, group: 10},
          %{x: 316.09, y: -176.71, sublevel: 1, group: 10},
          %{x: 653.06, y: -369.38, sublevel: 1, group: 26},
          %{x: 668.98, y: -377.01, sublevel: 1, group: 26},
          %{x: 681.92, y: -259.76, sublevel: 1, group: 32},
          %{x: 597.21, y: -274.38, sublevel: 1, group: 27}
        ],
      },
      %{
        name: "Driving Gale-Caller",
        id: 78932,
        count: 7,
        health: 1366961,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1255377, name: "Repel", interruptible: true}
        ],
        positions: [
          %{x: 327.26, y: -57.02, sublevel: 1, group: 4},
          %{x: 358.93, y: -184.32, sublevel: 1, group: 11},
          %{x: 368.74, y: -197.31, sublevel: 1, group: 11},
          %{x: 321.75, y: -223.98, sublevel: 1, group: 13},
          %{x: 613.25, y: -421.72, sublevel: 1, group: 25},
          %{x: 650.15, y: -231.22, sublevel: 1, group: 31},
          %{x: 635.70, y: -221.50, sublevel: 1, group: 31}
        ],
      },
      %{
        name: "Raging Squall",
        id: 250992,
        count: 1,
        health: 911307,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 1254676, name: "Wind Claws"},
          %{id: 1254677, name: "Wind Claws"},
          %{id: 1254678, name: "Wrathful Wind"},
          %{id: 1254679, name: "Wrathful Wind"},
          %{id: 1255922, name: "Wind Blast"}
        ],
        positions: [
          %{x: 331.22, y: -70.23, sublevel: 1, group: 4},
          %{x: 317.28, y: -69.02, sublevel: 1, group: 4},
          %{x: 363.48, y: -87.59, sublevel: 1, group: 7},
          %{x: 382.73, y: -109.89, sublevel: 1, group: 7},
          %{x: 306.60, y: -229.23, sublevel: 1, group: 13},
          %{x: 373.90, y: -75.35, sublevel: 1, group: 6},
          %{x: 319.25, y: -241.04, sublevel: 1, group: 13},
          %{x: 597.50, y: -420.14, sublevel: 1, group: 25},
          %{x: 605.45, y: -434.15, sublevel: 1, group: 25}
        ],
      },
      %{
        name: "Outcast Servant",
        id: 75976,
        count: 1,
        health: 911307,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [

        ],
        positions: [
          %{x: 375.85, y: -136.10, sublevel: 1, group: 9},
          %{x: 361.57, y: -143.41, sublevel: 1, group: 9},
          %{x: 224.07, y: -329.45, sublevel: 1, group: 17},
          %{x: 237.17, y: -324.37, sublevel: 1, group: 17},
          %{x: 251.45, y: -330.44, sublevel: 1, group: 17},
          %{x: 255.29, y: -346.37, sublevel: 1, group: 17},
          %{x: 187.44, y: -332.77, sublevel: 1, group: 18},
          %{x: 175.33, y: -342.88, sublevel: 1, group: 18},
          %{x: 263.55, y: -401.78, sublevel: 1, group: 19},
          %{x: 249.74, y: -405.89, sublevel: 1, group: 19}
        ],
      },
      %{
        name: "Blinding Sun Priestess",
        id: 79462,
        count: 5,
        health: 1366961,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 152953, name: "Blinding Light", interruptible: true},
          %{id: 1273356, name: "Solar Barrier", dispellable: true}
        ],
        positions: [
          %{x: 299.89, y: -256.97, sublevel: 1, group: 14},
          %{x: 249.59, y: -280.91, sublevel: 1, group: 15},
          %{x: 270.18, y: -386.52, sublevel: 1, group: 19},
          %{x: 470.83, y: -319.71, sublevel: 1, group: 29},
          %{x: 587.17, y: -288.63, sublevel: 1, group: 27}
        ],
      },
      %{
        name: "Initiate of the Rising Sun",
        id: 79466,
        count: 7,
        health: 1215076,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1254669, name: "Solar Bolt", interruptible: true}
        ],
        positions: [
          %{x: 287.50, y: -314.43, sublevel: 1, group: 16},
          %{x: 576.94, y: -212.77, sublevel: 1, group: 30},
          %{x: 301.30, y: -322.78, sublevel: 1, group: 16}
        ],
      },
      %{
        name: "Adept of the Dawn",
        id: 79467,
        count: 7,
        health: 1518845,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1254671, name: "Fiery Talon"},
          %{id: 1254672, name: "Fiery Talon"}
        ],
        positions: [
          %{x: 297.13, y: -273.64, sublevel: 1, group: 14},
          %{x: 285.41, y: -262.51, sublevel: 1, group: 14},
          %{x: 236.38, y: -271.02, sublevel: 1, group: 15},
          %{x: 175.33, y: -359.42, sublevel: 1, group: 18},
          %{x: 591.81, y: -217.68, sublevel: 1, group: 30},
          %{x: 480.17, y: -334.19, sublevel: 1, group: 29},
          %{x: 463.43, y: -334.46, sublevel: 1, group: 29},
          %{x: 611.24, y: -283.54, sublevel: 1, group: 27}
        ],
      },
      %{
        name: "Herald of Sunrise",
        id: 78933,
        count: 15,
        health: 2354210,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 1254355, name: "Solar Orb"},
          %{id: 1258217, name: "Solar Fire"},
          %{id: 1258220, name: "Solar Fire"}
        ],
        positions: [
          %{x: 250.38, y: -263.89, sublevel: 1, group: 15},
          %{x: 490.93, y: -432.14, sublevel: 1, group: 24},
          %{x: 589.82, y: -199.63, sublevel: 1, group: 30},
          %{x: 499.30, y: -263.87, sublevel: 1, group: 28},
          %{x: 302.33, y: -305.17, sublevel: 1, group: 16}
        ],
      },
      %{
        name: "Solar Construct",
        id: 76087,
        count: 12,
        health: 2278268,
        creature_type: "Mechanical",
        is_boss: false,
        spells: [
          %{id: 1253446, name: "Solar Flame"},
          %{id: 1253448, name: "Solar Nova"}
        ],
        positions: [
          %{x: 651.87, y: -209.85, sublevel: 1, group: 31},
          %{x: 235.58, y: -345.81, sublevel: 1, group: 17},
          %{x: 192.74, y: -352.17, sublevel: 1, group: 18},
          %{x: 250.25, y: -385.26, sublevel: 1, group: 19}
        ],
      },
      %{
        name: "Skyreach Sun Talon",
        id: 79093,
        count: 2,
        health: 607538,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1254689, name: "Bloodcrazed"},
          %{id: 1254690, name: "Bloodcrazed"}
        ],
        positions: [
          %{x: 161.35, y: -506.88, sublevel: 1, group: 21},
          %{x: 160.24, y: -520.41, sublevel: 1, group: 21},
          %{x: 148.75, y: -525.48, sublevel: 1, group: 21},
          %{x: 139.06, y: -518.00, sublevel: 1, group: 21},
          %{x: 139.00, y: -506.99, sublevel: 1, group: 21},
          %{x: 147.36, y: -501.12, sublevel: 1, group: 21},
          %{x: 113.26, y: -471.22, sublevel: 1, group: 22},
          %{x: 101.16, y: -472.34, sublevel: 1, group: 22},
          %{x: 97.26, y: -486.36, sublevel: 1, group: 22},
          %{x: 106.56, y: -496.08, sublevel: 1, group: 22},
          %{x: 118.03, y: -492.91, sublevel: 1, group: 22},
          %{x: 121.75, y: -479.80, sublevel: 1, group: 22}
        ],
      },
      %{
        name: "Sun Talon Tamer",
        id: 76154,
        count: 5,
        health: 1564410,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1254686, name: "Mark of Death"},
          %{id: 1254687, name: "Mark of Death"}
        ],
        positions: [
          %{x: 149.99, y: -512.66, sublevel: 1, group: 21},
          %{x: 109.20, y: -482.66, sublevel: 1, group: 22}
        ],
      },
      %{
        name: "Ranjit",
        id: 75964,
        count: 0,
        health: 11074911,
        creature_type: "Humanoid",
        is_boss: true,
        encounter_id: 966,
        spells: [
          %{id: 153757, name: "Fan of Blades"},
          %{id: 156793, name: "Chakram Vortex"},
          %{id: 1252690, name: "Gale Surge"},
          %{id: 1252691, name: "Gale Surge"},
          %{id: 1252733, name: "Gale Surge"},
          %{id: 1255472, name: "Dive"},
          %{id: 1258140, name: "Coalesced Wind"},
          %{id: 1258152, name: "Wind Chakram"},
          %{id: 1258160, name: "Wind Chakram"},
          %{id: 1281396, name: "Chakram Vortex"}
        ],
        positions: [
          %{x: 373.49, y: -250.78, sublevel: 1}
        ],
      },
      %{
        name: "Araknath",
        id: 76141,
        count: 0,
        health: 11074911,
        creature_type: "Mechanical",
        is_boss: true,
        encounter_id: 966,
        spells: [
          %{id: 154110, name: "Fiery Smash"},
          %{id: 154113, name: "Fiery Smash"},
          %{id: 154132, name: "Fiery Smash"},
          %{id: 154135, name: "Supernova"},
          %{id: 154149, name: "Energize"},
          %{id: 1252877, name: "Solar Infusion"},
          %{id: 1258205, name: "Solar Infusion"},
          %{id: 1283770, name: "Defensive Protocol"}
        ],
        positions: [
          %{x: 186.52, y: -417.44, sublevel: 1, group: 20}
        ],
      },
      %{
        name: "Skyreach Sun Construct Prototype",
        id: 76142,
        count: 0,
        health: 11074911,
        creature_type: "Mechanical",
        is_boss: false,
        spells: [
          %{id: 154159, name: "Energize"},
          %{id: 1281874, name: "Heat Exhaustion"},
          %{id: 1287905, name: "Light Ray"}
        ],
        positions: [
          %{x: 208.04, y: -411.16, sublevel: 1, group: 20},
          %{x: 207.30, y: -428.11, sublevel: 1, group: 20},
          %{x: 195.17, y: -438.21, sublevel: 1, group: 20}
        ],
      },
      %{
        name: "Rukhran",
        id: 76143,
        count: 0,
        health: 8543503,
        creature_type: "Beast",
        is_boss: true,
        encounter_id: 966,
        spells: [
          %{id: 159381, name: "Searing Quills"},
          %{id: 159382, name: "Searing Quills"},
          %{id: 1253510, name: "Sunbreak"},
          %{id: 1253519, name: "Burning Claws"},
          %{id: 1253520, name: "Burning Claws"}
        ],
        positions: [
          %{x: 188.79, y: -486.95, sublevel: 1, group: 23}
        ],
      },
      %{
        name: "Dread Raven",
        id: 76149,
        count: 15,
        health: 2733921,
        creature_type: "Beast",
        is_boss: false,
        spells: [
          %{id: 1254566, name: "Dire Screech"},
          %{id: 1254569, name: "Dire Screech"},
          %{id: 1258174, name: "Dread Wind"}
        ],
        positions: [
          %{x: 257.22, y: -76.64, sublevel: 1, group: 2},
          %{x: 375.49, y: -153.50, sublevel: 1, group: 9},
          %{x: 415.55, y: -117.03, sublevel: 1, group: 8},
          %{x: 673.74, y: -179.84, sublevel: 1, group: 33}
        ],
      },
      %{
        name: "Blooded Bladefeather",
        id: 76205,
        count: 5,
        health: 1670730,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1254670, name: "Rushing Winds", dispellable: true}
        ],
        positions: [
          %{x: 281.41, y: -91.78, sublevel: 1, group: 1},
          %{x: 355.53, y: -38.20, sublevel: 1, group: 5},
          %{x: 352.10, y: -54.59, sublevel: 1, group: 5},
          %{x: 607.07, y: -406.50, sublevel: 1, group: 25},
          %{x: 620.60, y: -435.27, sublevel: 1, group: 25},
          %{x: 694.58, y: -270.62, sublevel: 1, group: 32},
          %{x: 601.31, y: -297.41, sublevel: 1, group: 27}
        ],
      },
      %{
        name: "Sunwings",
        id: 76227,
        count: 0,
        health: 1012563,
        creature_type: "Elemental",
        is_boss: false,
        spells: [
          %{id: 1253367, name: "Solar Flare"},
          %{id: 1253368, name: "Burning Pursuit"},
          %{id: 1253416, name: "Blaze of Glory"},
          %{id: 1253511, name: "Burning Pursuit"}
        ],
        positions: [
          %{x: 207.13, y: -504.62, sublevel: 1, group: 23},
          %{x: 210.45, y: -492.74, sublevel: 1, group: 23},
          %{x: 209.54, y: -479.00, sublevel: 1, group: 23}
        ],
      },
      %{
        name: "High Sage Viryx",
        id: 76266,
        count: 0,
        health: 10283846,
        creature_type: "Humanoid",
        is_boss: true,
        encounter_id: 966,
        spells: [
          %{id: 153954, name: "Cast Down"},
          %{id: 154396, name: "Solar Blast", interruptible: true},
          %{id: 1253538, name: "Scorching Ray"},
          %{id: 1253840, name: "Lens Flare"}
        ],
        positions: [
          %{x: 700.67, y: -152.76, sublevel: 1, group: 34}
        ],
      },
      %{
        name: "Arakkoa Magnifying Glass",
        id: 76285,
        count: 0,
        health: 303769,
        creature_type: "Mechanical",
        is_boss: false,
        spells: [
          %{id: 154043, name: "Blazing Ground"},
          %{id: 1253543, name: "Scorching Ray"}
        ],
        positions: [
          %{x: 722.37, y: -144.51, sublevel: 1, group: 34}
        ],
      },
      %{
        name: "Adorned Bladetalon",
        id: 79303,
        count: 12,
        health: 2582037,
        creature_type: "Humanoid",
        is_boss: false,
        spells: [
          %{id: 1254380, name: "Shear"},
          %{id: 1254460, name: "Blade Rush"},
          %{id: 1254475, name: "Blade Rush"}
        ],
        positions: [
          %{x: 291.54, y: -59.52, sublevel: 1, group: 3},
          %{x: 342.72, y: -205.73, sublevel: 1, group: 12},
          %{x: 506.86, y: -443.69, sublevel: 1, group: 24},
          %{x: 654.34, y: -386.61, sublevel: 1, group: 26},
          %{x: 698.45, y: -252.01, sublevel: 1, group: 32}
        ],
      },
      %{
        name: "Solar Orb",
        id: 251880,
        count: 0,
        health: 10283846,
        creature_type: "Not specified",
        is_boss: false,
        spells: [
          %{id: 1254329, name: "Solar Flare"},
          %{id: 1254332, name: "Solar Flare"}
        ],
        positions: [
          %{x: 504.58, y: -426.98, sublevel: 1, group: 24},
          %{x: 509.98, y: -277.23, sublevel: 1, group: 28},
          %{x: 581.38, y: -224.18, sublevel: 1, group: 30},
          %{x: 236.33, y: -283.64, sublevel: 1, group: 15}
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
