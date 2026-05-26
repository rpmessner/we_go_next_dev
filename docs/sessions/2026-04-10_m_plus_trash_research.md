# M+ Trash Tracking Research

*2026-04-10 — Research into how combat log analysis tools handle M+ trash between boss encounters*

## Combat Log M+ Events

### CHALLENGE_MODE_START

Fires when the keystone is activated (before the 10-second countdown).

**Format:** `CHALLENGE_MODE_START,"zoneName",instanceID,challengeModeID,keystoneLevel,[affixID,...]`

**Example:**
```
11/21 12:01:44.500  CHALLENGE_MODE_START,"Mists of Tirna Scithe",2290,375,11,[9,122,4,121]
```

Fields:
- `zoneName` (string) — dungeon name
- `instanceID` (number) — instance map ID
- `challengeModeID` (number) — challenge mode map ID (different from instanceID)
- `keystoneLevel` (number) — key level
- `[affixID, ...]` (array) — list of active affix IDs

### CHALLENGE_MODE_END

Fires when the run finishes (timed or depleted).

**Format:** `CHALLENGE_MODE_END,instanceID,success,keystoneLevel,totalTime`

**Example:**
```
11/21 12:35:12.100  CHALLENGE_MODE_END,2290,1,11,1892345
```

Fields:
- `instanceID` (number)
- `success` (1 = timed, 0 = depleted)
- `keystoneLevel` (number)
- `totalTime` (number) — milliseconds, includes death penalty

### ENCOUNTER_START / ENCOUNTER_END

Boss encounters within the dungeon. Same format as raids but `difficultyID = 8` for Mythic Keystone.

```
ENCOUNTER_START,1146,"Randolph Moloch",8,5,2290
ENCOUNTER_END,1146,"Randolph Moloch",8,5,1,145678
```

### MAP_CHANGE

Fires on subzone transitions (floor changes within dungeon).

**Format:** `MAP_CHANGE,uiMapID,"uiMapName",x0,x1,y0,y1`

### COMBATANT_INFO

Logged at each `ENCOUNTER_START` for every player. Contains stats, talents, gear, buffs.

### Trash Pulls — NO Explicit Boundary Markers

**There are no combat log events that mark trash pull start/end.** No `PULL_START`, no `PULL_END`. Between boss encounters, you only get raw combat events (SPELL_DAMAGE, SWING_DAMAGE, UNIT_DIED, etc.).

Pull segmentation must be **inferred from gaps in combat activity**.

## Creature GUID Format (NPC Identification)

NPC GUIDs in combat log: `Creature-0-[serverID]-[instanceID]-[zoneUID]-[npcID]-[spawnUID]`

Example: `Creature-0-1465-0-2105-448-000043F59F`

The `npcID` (5th hyphen-delimited field) is the same ID used by MDT and Wowhead. This means every combat event targeting a trash mob includes the NPC ID, which maps directly to our GameData modules.

**Extraction:** Split GUID on `-`, take index 5.

## How Other Tools Handle M+ Segmentation

### Warcraft Logs

- Entire M+ run is one "fight" bounded by `CHALLENGE_MODE_START` → `CHALLENGE_MODE_END`
- Boss fights identified by `ENCOUNTER_START`/`ENCOUNTER_END` within the run
- **Trash pull boundaries determined by gaps in combat events** (server-side heuristic)
- Each pull becomes a `ReportDungeonPull` with `boss: 0` for trash, `boss: encounterID` for bosses
- Pulls include an `enemies` field listing NPC IDs for mobs in that pull
- Trash pulled into a boss fight is attributed to the boss, removed from trash segment
- If `CHALLENGE_MODE_START` is missing (logging started late), the entire dungeon appears as undifferentiated "trash"

### WoWAnalyzer

- Consumes Warcraft Logs API data, not raw combat logs
- Treats entire M+ dungeon as a single fight with `dungeonPulls` sub-segments
- `WCLDungeonPull` has `boss: 0` for trash, `boss: encounterID` for bosses, `enemies: [[npcID, instanceCount]]`
- Pull segmentation done server-side by WCL, not by WoWAnalyzer
- Detection: `fight.difficulty === 8` (MYTHIC_PLUS_DUNGEON)

### Details! Addon

Uses WoW client events (not combat log text):
1. `CHALLENGE_MODE_START` → initializes M+ tracking
2. `PLAYER_REGEN_DISABLED` (enter combat) / `PLAYER_REGEN_ENABLED` (leave combat) → creates segments
3. `ENCOUNTER_END` → tags segment as boss kill/wipe
4. Each combat segment tagged as: boss, boss-wipe, or trash
5. After boss kills, merges preceding trash segments into "Boss Name (trash)"
6. At `CHALLENGE_MODE_COMPLETED`, merges all segments into overall run

**Key insight:** Details! uses the WoW client's in-combat/out-of-combat state as pull boundaries. The combat log text file doesn't have `PLAYER_REGEN_DISABLED`/`ENABLED` events — these are frame events only available to in-game addons.

## Our Current Parser State

**File:** `lib/we_go_next/combat_log_parser.ex` (Zig NIF)

### scan_boundaries

- Only looks for `ENCOUNTER_START` and `ENCOUNTER_END`
- **Does NOT detect CHALLENGE_MODE_START or CHALLENGE_MODE_END**
- Returns encounter boundaries as byte offset pairs

### parse_events

- Explicitly skips these event types (returns null):
  - `COMBAT_LOG_VERSION`
  - `ZONE_CHANGE`
  - `MAP_CHANGE`
  - `ENCOUNTER_START`
  - `ENCOUNTER_END`
- **Does NOT look for CHALLENGE_MODE events**
- Parses combat events (SPELL_DAMAGE, UNIT_DIED, etc.) within encounter byte ranges only

### What This Means

Currently, WeGoNext only sees boss encounters. All trash events between bosses are invisible — they fall outside any `ENCOUNTER_START`/`ENCOUNTER_END` pair and are never parsed.

## What We'd Need to Add

### 1. Detect M+ Run Boundaries

Add `CHALLENGE_MODE_START` / `CHALLENGE_MODE_END` detection to `scan_boundaries` in the Zig parser. These bracket the entire dungeon run and give us:
- Dungeon name + instance ID (maps to our GameData)
- Key level
- Affixes
- Success/failure + total time

### 2. Parse Events Outside Encounter Boundaries

Currently `parse_events` only reads bytes between `ENCOUNTER_START`..`ENCOUNTER_END`. For M+ trash, we need to parse events in the gaps between encounters (and before the first boss / after the last boss), bounded by `CHALLENGE_MODE_START`..`CHALLENGE_MODE_END`.

### 3. Infer Trash Pull Boundaries

Since there's no explicit pull start/end in the combat log, we need gap detection:
- A "pull" starts when hostile combat events begin after a quiet period
- A "pull" ends when no hostile combat events occur for N seconds (~5-10s threshold)
- Group events by temporal proximity

### 4. Map NPC IDs to GameData

Parse the NPC ID from creature GUIDs (`Creature-0-...-npcID-...`) and map to our MDT GameData enemy IDs. This lets us:
- Know which pack was pulled
- Show results on the dungeon map
- Track interrupt priorities per mob type

### 5. Stop Skipping MAP_CHANGE and ZONE_CHANGE

These events are useful for M+:
- `MAP_CHANGE` tells us which floor the party is on (for multi-level dungeons)
- `ZONE_CHANGE` could help detect dungeon entry/exit

## Recommended Implementation Order

1. **Add CHALLENGE_MODE_START/END to scan_boundaries** — detect M+ runs
2. **Create a new "session" concept** — an M+ run contains multiple encounters + trash segments
3. **Parse trash events** — extend parse_events to work on non-encounter byte ranges
4. **Gap-based pull segmentation** — group trash events into pulls by combat gaps
5. **NPC ID extraction** — parse creature GUIDs to map trash mobs to GameData
6. **Dungeon map overlay** — show per-pack results using GameData positions

## Sources

- [COMBAT_LOG_EVENT — Warcraft Wiki](https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT)
- [GUID — Warcraft Wiki](https://warcraft.wiki.gg/wiki/GUID)
- [WoWAnalyzer GitHub](https://github.com/WoWAnalyzer/WoWAnalyzer)
- [Details! Damage Meter GitHub](https://github.com/Tercioo/Details-Damage-Meter)
- [Mythic Dungeon Tools GitHub](https://github.com/Nnoggie/MythicDungeonTools)
- [Warcraft Logs v2 API Docs](https://www.warcraftlogs.com/v2-api-docs/warcraft/)
- [Mythic+ as trash — WCL Forums](https://forums.combatlogforums.com/t/mythic-as-trash/3449)
