# Handoff Document: Next Steps

**Last Updated:** 2025-11-25 (Phase 1 Complete - All Analyzers Done)
**Target:** MVP ready for Midnight expansion raids (Late Jan - March 2026)

This document outlines the immediate next steps for implementing the WoW Raid Diagnostic Tool.

---

## Current State

### What's Built

**Death Analyzer** (Complete)
- Location: `combat_log_parser/lib/combat_log_parser/analyzers/death_analyzer.ex`
- Parses `UNIT_DIED` events for player deaths
- Tracks rolling window of last 10 damage events per player
- Captures death recap with killing blow and overkill
- Tested on 603MB combat log with 20 encounters

**Damage Taken Analyzer** (Complete)
- Location: `combat_log_parser/lib/combat_log_parser/analyzers/damage_taken_analyzer.ex`
- Tracks total damage taken per player
- Breaks down by ability and source
- **Tank detection**: Identifies tanks by NPC melee damage received
- Separates tank vs DPS/healer damage in output
- Shows "Top Avoidable Abilities" excluding tank damage

**Interrupt Analyzer** (Complete)
- Location: `combat_log_parser/lib/combat_log_parser/analyzers/interrupt_analyzer.ex`
- Parses `SPELL_INTERRUPT` for successful interrupts
- Tracks `SPELL_CAST_SUCCESS` for enemy casts (detects missed kicks)
- Per-player interrupt counts with spell breakdown
- Per-spell statistics (interrupted vs completed casts)
- Shows which important casts went off uninterrupted

**Debuff Analyzer** (Complete - NEW)
- Location: `combat_log_parser/lib/combat_log_parser/analyzers/debuff_analyzer.ex`
- Parses `SPELL_AURA_APPLIED`, `SPELL_AURA_REMOVED`, `SPELL_AURA_APPLIED_DOSE`
- Tracks debuff applications per player with duration
- Per-spell statistics (total applications, players affected)
- Identifies players with most debuffs (potential mechanic failures)
- Helper functions: `players_with_debuff/3`, `raid_wide_debuffs/2`

**Core Parser** (Complete)
- Reads WoW combat logs from `/mnt/g/World of Warcraft/_retail_/Logs/`
- Parses encounter boundaries (`ENCOUNTER_START`/`ENCOUNTER_END`)
- Stores events per encounter
- Handles advanced combat logging field positions

### What's NOT Built Yet
- Phoenix web app
- Live file watching
- Criteria system
- Boss profiles

---

## Immediate Next Session: Phoenix Web App

**Goal:** Create basic Phoenix web interface for viewing encounter data.

### Why This Is Next

Phase 1 (Core Event Processing) is complete. Phase 2 is Discovery Mode:
- Need a UI to browse encounters and view analysis results
- Foundation for the live dashboard (Phase 4)
- Makes the tool usable beyond command-line output

### Tasks

1. **Create Phoenix application**
   - Add Phoenix as dependency to mix.exs
   - Generate basic Phoenix app structure
   - Configure for LiveView (real-time updates later)

2. **Create encounter list view**
   - Route: `/` - list all encounters from loaded log
   - Show: boss name, difficulty, kill/wipe, duration, death count

3. **Create encounter detail view**
   - Route: `/encounters/:id`
   - Tabs or sections for: Deaths, Damage Taken, Interrupts, Debuffs
   - Use existing analyzer output formatters

4. **Add log file loading**
   - File picker or path input to load a combat log
   - Store parsed encounters in ETS or Agent for quick access

### Expected UI

```
ENCOUNTERS
─────────────────────────────────────────
1. Plexus Sentinel (Heroic) - KILL 3:50  [6 deaths]
2. Loom'ithar (Heroic) - WIPE 0:04       [0 deaths]
3. Loom'ithar (Heroic) - KILL 4:01       [6 deaths]
...

[Click encounter to see details]
```

---

## Phase Status

### Phase 1: Core Event Processing ✅ COMPLETE
- [x] Death analyzer ✓
- [x] Damage taken tracker ✓
- [x] Interrupt tracker ✓
- [x] Debuff tracker ✓

### Phase 2: Discovery Mode (Current) ← **START HERE**
- [ ] Phoenix web app setup
- [ ] Basic encounter list view
- [ ] Event summary tables
- [ ] Pull comparison

### Phase 3: Criteria System (Mar 2026)
- [ ] Mechanic type definitions
- [ ] Criteria builder UI
- [ ] Boss profile save/load
- [ ] Failure detection

### Phase 4: Live Dashboard (May 2026)
- [ ] File watching (real-time log tailing)
- [ ] LiveView dashboard
- [ ] Death/failure feeds
- [ ] Alerts

### Phase 5: Reports (Jul 2026)
- [ ] Pull summary generation
- [ ] Player reports
- [ ] Progress tracking

### Phase 6: Strategy Diagrams (Sep 2026)
- [ ] Minimap integration
- [ ] Annotation tools
- [ ] PNG export

### Phase 7: Polish (Nov 2026)
- [ ] Testing with current content
- [ ] UX refinement
- [ ] Documentation

---

## Technical Reference

### Combat Log Field Positions (Advanced Logging)

With advanced combat logging enabled, damage events have this structure:

**SPELL_DAMAGE / SPELL_PERIODIC_DAMAGE:**
```
Index 0:    Event type
Index 1-4:  Source (GUID, name, flags, raid flags)
Index 5-8:  Dest (GUID, name, flags, raid flags)
Index 9:    Spell ID
Index 10:   Spell name
Index 11:   Spell school
Index 12-30: Advanced unit info (HP, power, position, etc.)
Index 31:   Damage amount
Index 32:   Overkill (-1 if none)
Index 33+:  School, resisted, blocked, absorbed, critical, etc.
```

**SWING_DAMAGE:**
- No spell info (indices 9-11)
- Damage at index 28, overkill at index 29

**UNIT_DIED:**
```
Index 0:    Event type
Index 1-4:  Recap info (zeroes/nil)
Index 5:    Dest GUID (dead unit)
Index 6:    Dest name
```

### Tank Detection

Tanks are detected by behavior, not flags:
- Track `SWING_DAMAGE` from `Creature-*` GUIDs to `Player-*` GUIDs
- Top 2 players by melee damage received = tanks
- WoW's `COMBATLOG_OBJECT_MAINTANK` flag (`0x00040000`) is unreliable

### Codebase Structure

```
combat_log_parser/
├── lib/
│   ├── combat_log_parser.ex        # Main API
│   └── combat_log_parser/
│       ├── analyzers/
│       │   ├── death_analyzer.ex        # Death tracking ✓
│       │   ├── damage_taken_analyzer.ex # Damage tracking ✓
│       │   ├── interrupt_analyzer.ex    # Interrupt tracking ✓
│       │   └── debuff_analyzer.ex       # Debuff tracking ✓
│       ├── application.ex
│       ├── encounter.ex            # Encounter struct
│       └── log_reader.ex           # File parsing
├── test_parse.exs                  # Test script
└── mix.exs
```

### Running the Parser

```bash
cd combat_log_parser
mix compile
mix run test_parse.exs
```

---

## Data Sources

**Primary (Used by Parser):**
- WoW Combat Log: `/mnt/g/World of Warcraft/_retail_/Logs/WoWCombatLog-*.txt`
- Written by game client in real-time
- Advanced combat logging enabled

**Legacy (NOT Used):**
- `./data/` directory contains Warcraft Logs CSV exports
- These are processed/aggregated data from warcraftlogs.com
- Not used by the parser

---

## Success Criteria for MVP

By Midnight launch, the tool should:

- [ ] Watch combat log in real-time
- [ ] Display deaths as they happen
- [ ] Track user-defined mechanics (criteria system)
- [ ] Show failures on live dashboard
- [ ] Generate between-pull summary
- [ ] Be stable for 3+ hour raid nights
- [ ] Have at least one boss profile tested with real progression

---

## Reference Documentation

- `CLAUDE.md` - Project overview, data sources, session log rules
- `docs/ROADMAP.md` - Full development phases
- `docs/TECHNICAL_ARCHITECTURE.md` - System design
- `docs/sessions/` - Historical session logs
- `docs/WOWANALYZER_PATTERNS.md` - Event processing patterns

---

**Ready to start:** Open the next session with "Let's set up the Phoenix web app"
