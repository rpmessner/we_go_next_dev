#!/usr/bin/env python3
"""Generate static Elixir data modules from extracted MDT dungeon data + spell names."""

import json
import os
import re

TOOLS_DIR = os.path.dirname(__file__)
DUNGEONS_JSON = os.path.join(TOOLS_DIR, "dungeons.json")
SPELL_NAMES_JSON = os.path.join(TOOLS_DIR, "spell_names.json")
OUTPUT_DIR = "/home/rpmessner/dev/games/wow-addons/we_go_next/we_go_next_dev/we_go_next/lib/we_go_next/game_data"


def snake_case(name):
    """Convert a dungeon name to snake_case module-friendly form."""
    s = re.sub(r"['\-\s]+", "_", name)
    s = re.sub(r"[^a-zA-Z0-9_]", "", s)
    s = re.sub(r"_+", "_", s).strip("_").lower()
    return s


def module_case(name):
    """Convert a dungeon name to PascalCase."""
    words = re.sub(r"['\-\s]+", " ", name).split()
    return "".join(w.capitalize() for w in words)


def elixir_string(s):
    """Escape a string for Elixir."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def generate_spell_module(spell_names):
    """Generate the spell name lookup module."""
    lines = [
        "defmodule WeGoNext.GameData.Spells do",
        '  @moduledoc "Static spell ID to name mapping from Wowhead."',
        "",
        "  @spell_names %{",
    ]

    for spell_id in sorted(spell_names.keys(), key=int):
        name = spell_names[spell_id]
        lines.append(f"    {spell_id} => {elixir_string(name)},")

    lines.append("  }")
    lines.append("")
    lines.append("  @doc \"Get spell name by ID.\"")
    lines.append("  def name(spell_id) when is_integer(spell_id) do")
    lines.append('    Map.get(@spell_names, spell_id, "Unknown Spell #{spell_id}")')
    lines.append("  end")
    lines.append("")
    lines.append("  @doc \"Get all spell names as a map of ID => name.\"")
    lines.append("  def all, do: @spell_names")
    lines.append("end")

    return "\n".join(lines) + "\n"


def generate_dungeon_module(dungeon, spell_names):
    """Generate a per-dungeon data module."""
    slug = snake_case(dungeon["name"])
    mod_name = module_case(dungeon["name"])

    lines = [
        f"defmodule WeGoNext.GameData.Dungeons.{mod_name} do",
        f'  @moduledoc "Static data for {dungeon["name"]} (MDT index {dungeon["index"]})."',
        "",
        "  def info do",
        "    %{",
        f"      name: {elixir_string(dungeon['name'])},",
        f"      slug: {elixir_string(slug)},",
        f"      mdt_index: {dungeon['index']},",
        f"      map_id: {dungeon['map_id']},",
        f"      total_count: {dungeon['total_count']},",
        f"      floors: {len(dungeon.get('floors', []))},",
        "    }",
        "  end",
        "",
    ]

    # Enemies
    lines.append("  def enemies do")
    lines.append("    [")

    for enemy in dungeon["enemies"]:
        spell_entries = []
        for s in enemy["spells"]:
            sid = s["spell_id"]
            sname = spell_names.get(str(sid), f"Unknown Spell {sid}")
            flags = []
            if s["interruptible"]:
                flags.append("interruptible: true")
            if s["magic"]:
                flags.append("dispellable: true")
            flags_str = ", ".join(flags)
            if flags_str:
                spell_entries.append(
                    f"          %{{id: {sid}, name: {elixir_string(sname)}, {flags_str}}}"
                )
            else:
                spell_entries.append(
                    f"          %{{id: {sid}, name: {elixir_string(sname)}}}"
                )

        clone_entries = []
        for c in enemy["clones"]:
            parts = [f"x: {c['x']:.2f}", f"y: {c['y']:.2f}", f"sublevel: {c['sublevel']}"]
            if c.get("group"):
                parts.append(f"group: {c['group']}")
            clone_entries.append("          %{" + ", ".join(parts) + "}")

        lines.append("      %{")
        lines.append(f"        name: {elixir_string(enemy['name'])},")
        lines.append(f"        id: {enemy['id']},")
        lines.append(f"        count: {enemy['count']},")
        lines.append(f"        health: {enemy['health']},")
        lines.append(f'        creature_type: {elixir_string(enemy["creature_type"])},')
        lines.append(f"        is_boss: {str(enemy['is_boss']).lower()},")
        if enemy.get("encounter_id"):
            lines.append(f"        encounter_id: {enemy['encounter_id']},")
        lines.append("        spells: [")
        lines.append(",\n".join(spell_entries))
        lines.append("        ],")
        lines.append("        positions: [")
        lines.append(",\n".join(clone_entries))
        lines.append("        ],")
        lines.append("      },")

    lines.append("    ]")
    lines.append("  end")
    lines.append("")

    # Interruptible spells (convenience accessor)
    lines.append("  def interruptible_spells do")
    lines.append("    enemies()")
    lines.append("    |> Enum.flat_map(fn enemy ->")
    lines.append("      enemy.spells")
    lines.append("      |> Enum.filter(& &1[:interruptible])")
    lines.append("      |> Enum.map(&Map.put(&1, :mob_name, enemy.name))")
    lines.append("    end)")
    lines.append("  end")
    lines.append("")

    # Bosses (convenience accessor)
    lines.append("  def bosses do")
    lines.append("    Enum.filter(enemies(), & &1.is_boss)")
    lines.append("  end")
    lines.append("")

    # Trash mobs (convenience accessor)
    lines.append("  def trash do")
    lines.append("    Enum.reject(enemies(), & &1.is_boss)")
    lines.append("  end")

    lines.append("end")

    return "\n".join(lines) + "\n"


def generate_dungeons_index(dungeons):
    """Generate the index module that ties all dungeons together."""
    lines = [
        "defmodule WeGoNext.GameData.Dungeons do",
        '  @moduledoc "Index of all Midnight Season 1 M+ dungeons."',
        "",
    ]

    # Aliases
    for d in dungeons:
        mod = module_case(d["name"])
        lines.append(f"  alias WeGoNext.GameData.Dungeons.{mod}")
    lines.append("")

    # all/0
    lines.append("  def all do")
    lines.append("    [")
    for d in dungeons:
        mod = module_case(d["name"])
        lines.append(f"      {mod}.info(),")
    lines.append("    ]")
    lines.append("  end")
    lines.append("")

    # by_slug/1
    lines.append("  def by_slug(slug)")
    lines.append("")
    for d in dungeons:
        mod = module_case(d["name"])
        slug = snake_case(d["name"])
        lines.append(f'  def by_slug({elixir_string(slug)}), do: {mod}')
    lines.append("  def by_slug(_), do: nil")
    lines.append("")

    # by_map_id/1
    lines.append("  def by_map_id(map_id)")
    lines.append("")
    for d in dungeons:
        mod = module_case(d["name"])
        lines.append(f"  def by_map_id({d['map_id']}), do: {mod}")
    lines.append("  def by_map_id(_), do: nil")
    lines.append("")

    # all_interruptible_spells/0
    lines.append("  def all_interruptible_spells do")
    lines.append("    [")
    for d in dungeons:
        mod = module_case(d["name"])
        lines.append(f"      {mod}.interruptible_spells(),")
    lines.append("    ]")
    lines.append("    |> List.flatten()")
    lines.append("  end")

    lines.append("end")

    return "\n".join(lines) + "\n"


def main():
    with open(DUNGEONS_JSON) as f:
        dungeons = json.load(f)

    with open(SPELL_NAMES_JSON) as f:
        spell_names = json.load(f)

    print(f"Loaded {len(dungeons)} dungeons, {len(spell_names)} spell names")

    os.makedirs(os.path.join(OUTPUT_DIR, "dungeons"), exist_ok=True)

    # Generate spell module
    spell_code = generate_spell_module(spell_names)
    spell_path = os.path.join(OUTPUT_DIR, "spells.ex")
    with open(spell_path, "w") as f:
        f.write(spell_code)
    print(f"  Generated {spell_path}")

    # Generate per-dungeon modules
    for dungeon in dungeons:
        slug = snake_case(dungeon["name"])
        code = generate_dungeon_module(dungeon, spell_names)
        path = os.path.join(OUTPUT_DIR, "dungeons", f"{slug}.ex")
        with open(path, "w") as f:
            f.write(code)
        print(f"  Generated {path}")

    # Generate index module
    index_code = generate_dungeons_index(dungeons)
    index_path = os.path.join(OUTPUT_DIR, "dungeons.ex")
    with open(index_path, "w") as f:
        f.write(index_code)
    print(f"  Generated {index_path}")

    print("\nDone!")


if __name__ == "__main__":
    main()
