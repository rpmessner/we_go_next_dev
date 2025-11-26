# Session: Damage Taken Tracker with Role Detection

**Date:** 2025-11-25
**Duration:** ~1 hour
**Focus:** Build damage taken analyzer with tank/DPS separation

---

## Summary

Built the `DamageTakenAnalyzer` module that tracks damage taken by all players during encounters. Key feature: automatically detects tanks and separates their damage from DPS/healers, since tank damage is expected while DPS/healer damage may be avoidable.

---

## What Was Built

### New File: `damage_taken_analyzer.ex`

Location: `combat_log_parser/lib/combat_log_parser/analyzers/damage_taken_analyzer.ex`

**Features:**
- Tracks total damage taken per player
- Breaks down damage by ability (name, total, hit count, average)
- Breaks down damage by source
- **Tank detection heuristic**: Top 2 players receiving NPC melee damage are tanks
- Separates output into "TANKS (expected damage)" and "DPS/HEALERS (avoidable?)"
- `top_avoidable_abilities/2` - shows only damage hitting non-tanks

### Main API Updates

Added to `combat_log_parser.ex`:
- `analyze_damage_taken/1` - returns structured damage stats
- `print_damage_taken_summary/2` - formatted output with options

---

## Tank Detection

### The Problem

WoW combat logs have a `COMBATLOG_OBJECT_MAINTANK` flag (`0x00040000`) in unit flags, but this is only set if the raid leader explicitly assigns Main Tank roles. Most raids don't bother - it's optional UI convenience.

### The Solution

Detect tanks by **behavior**: whoever is receiving significant melee damage from NPCs (`SWING_DAMAGE` from `Creature-*` GUIDs) is tanking.

```elixir
# Tank detection heuristic
defp detect_tanks(players) do
  players
  |> Map.values()
  |> Enum.filter(&(&1.melee_from_npcs > 0))
  |> Enum.sort_by(& &1.melee_from_npcs, :desc)
  |> Enum.take(2)  # Top 2 = tanks
  |> Enum.map(& &1.player_guid)
  |> MapSet.new()
end
```

**Why top 2?** Most raid content uses 2 tanks. This could be made configurable if needed for single-tank fights or 3-tank encounters.

### Verified Results

From Plexus Sentinel (Heroic):
- `Holyeversong-Stormrage-US`: 20M melee damage received → TANK
- `Awnyxxia-Aggramar-US`: 11M melee damage received → TANK
- Everyone else: 0M melee → DPS/HEALER

---

## Output Format

```
1. Plexus Sentinel (Heroic) - KILL (3:50)

   TANKS (expected damage):
  Awnyxxia-Aggramar-US [TANK]: 56.8M total
         Melee: 11.3M (17 hits, 664k avg)
         Atomize: 9.9M (3 hits, 3.3M avg)
         Purging Lightning: 9.4M (30 hits, 314k avg)
  Holyeversong-Stormrage-US [TANK]: 53.3M total
         Melee: 20.9M (14 hits, 1.5M avg)
         ...

   DPS/HEALERS (avoidable?):
  Manitu-Proudmoore-US: 161.1M total
         Purging Lightning: 43.2M (44 hits, 983k avg)
         Powered Automaton: 32.0M (20 hits, 1.6M avg)
         ...

   Top Avoidable Abilities (DPS/Healers only):
  1. Powered Automaton: 518.4M (344 hits, 1.5M avg)
  2. Purging Lightning: 448.3M (514 hits, 872k avg)
  ...
```

---

## Data Structure

The `analyze/1` function now returns a map:

```elixir
%{
  tanks: [%PlayerDamage{role: :tank, ...}, ...],
  dps_healers: [%PlayerDamage{role: :dps_healer, ...}, ...],
  all: [%PlayerDamage{}, ...]  # Combined, sorted by total
}
```

`PlayerDamage` struct:
```elixir
defstruct [
  :player_name,
  :player_guid,
  :role,              # :tank or :dps_healer
  total: 0,
  melee_from_npcs: 0, # Used for tank detection
  by_ability: %{},    # %{ability_name => %{total: N, hits: N, ability_id: id}}
  by_source: %{}      # %{source_name => total_damage}
]
```

---

## Technical Notes

### Unit Flags Research

WoW combat log unit flags are documented at `warcraft.wiki.gg/wiki/UnitFlag`:
- `COMBATLOG_OBJECT_MAINTANK`: `0x00040000`
- `COMBATLOG_OBJECT_MAINASSIST`: `0x00080000`

These are NOT reliably set in most raids, hence the heuristic approach.

### Source GUID Detection

NPCs have GUIDs starting with `Creature-`:
```elixir
defp is_npc_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Creature-")
```

Players start with `Player-`:
```elixir
defp is_player_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Player-")
```

---

## Files Modified

1. **Created:** `combat_log_parser/lib/combat_log_parser/analyzers/damage_taken_analyzer.ex`
2. **Modified:** `combat_log_parser/lib/combat_log_parser.ex` (added API functions)
3. **Modified:** `combat_log_parser/test_parse.exs` (added damage summary call)

---

## Why This Matters

For raid diagnostics:
- **Tanks** taking 50M+ damage from boss melee is **expected** - they're doing their job
- **DPS** taking 150M damage from "Powered Automaton" is **problematic** - they need to move
- Now raid leaders can identify avoidable damage without tank numbers polluting the results
- "Top Avoidable Abilities" shows what mechanics are actually causing problems

---

## Next Steps

See `docs/HANDOFF.md` for next phase - likely **Interrupt Tracker**:
- Track `SPELL_INTERRUPT` events
- Show interrupted spells vs total casts
- Identify missed interrupts
- Track interrupt assignments/rotations
