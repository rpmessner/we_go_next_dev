# Session: Death Analyzer Implementation & Codebase Cleanup

**Date:** 2025-11-24 (Session 2)
**Focus:** Built death analyzer, cleaned up legacy code, clarified data sources

---

## Summary

Implemented the first diagnostic analyzer (deaths) and cleaned up legacy code from the old "personal DPS analysis" direction. Also clarified documentation around data sources after discovering confusion between WoW combat logs and Warcraft Logs CSV exports.

---

## Accomplishments

### 1. Death Analyzer Implemented

Created `combat_log_parser/lib/combat_log_parser/analyzers/death_analyzer.ex`:

- Parses `UNIT_DIED` events for player deaths
- Tracks rolling window of last 10 damage events per player
- Captures death recap showing damage leading to death
- Identifies killing blow with overkill amount
- Shows time into fight (e.g., "1:03")
- Formats damage in human-readable form (761k, 22.3M)

**Sample Output:**
```
1. Plexus Sentinel (Heroic) - KILL
   Deaths: 6

  1:03 - Favikul-Area52-US died to [Atomize] from Arcanomatrix Atomizer (27.1M overkill)
         Recap:
           Atomize (22.3M) - Arcanomatrix Atomizer
           Powered Automaton (1.8M) - Plexus Sentinel
           Obliteration Arcanocannon (4.4M) - Plexus Sentinel
```

### 2. Data Source Clarification

Discovered and fixed confusion in documentation about data sources:

| Source | Location | Status |
|--------|----------|--------|
| WoW Combat Log | `/mnt/g/World of Warcraft/_retail_/Logs/*.txt` | **Used by parser** |
| Warcraft Logs CSV | `./data/` | Legacy, NOT used |

Updated CLAUDE.md with clear distinction between these sources.

### 3. Legacy Code Cleanup

**Deleted:**
- `damage_analyzer.ex` - Personal DPS analysis (not needed for raid diagnostics)
- `docs/GETTING_STARTED.md` - Outdated, focused on CSV exports

**Simplified:**
- `combat_log_parser.ex` - Removed personal DPS functions (`analyze_damage/2`, `print_summary/2`)
- `test_parse.exs` - Now only shows encounter count and death summary
- `log_reader.ex` - Fixed unused variable warnings

### 4. M+ Added as Secondary Goal

Updated CLAUDE.md to reflect:
- **Primary focus:** Raid progression (MVP for Midnight launch)
- **Secondary focus:** M+ analysis (works automatically with same analyzers)
- M+-specific features (death timers, affix tracking) planned for post-MVP

### 5. Session Log Amendment Rules

Added exception to immutability rule for session logs:
- ~~Strikethrough~~ incorrect text is allowed
- Clarification remarks are allowed
- These are the **only** modifications permitted

---

## Technical Details

### Combat Log Field Positions (Advanced Logging)

Discovered that with advanced combat logging enabled, field positions differ significantly:

**SPELL_DAMAGE format:**
- Indices 0-8: Event type, source info (4 fields), dest info (4 fields)
- Indices 9-11: Spell info (id, name, school)
- Indices 12-30: Advanced unit info (HP, power, position, etc.)
- Index 31: Damage amount
- Index 32: Overkill

**UNIT_DIED format:**
- Indices 0-4: Event type, recap info (zeroes)
- Index 5: Dest GUID (the dead unit)
- Index 6: Dest name

### Current Codebase Structure

```
combat_log_parser/
├── lib/
│   ├── combat_log_parser.ex        # Main API (parse, analyze_deaths)
│   └── combat_log_parser/
│       ├── analyzers/
│       │   └── death_analyzer.ex   # Death tracking with recap
│       ├── application.ex
│       ├── encounter.ex            # Encounter data structure
│       └── log_reader.ex           # File parsing
├── test_parse.exs                  # Test script
└── mix.exs
```

---

## What's Next

Per the roadmap, immediate next steps are:

1. **Damage Taken Tracker** - What's hitting the raid, who's taking the most
   - Aggregate damage by ability
   - Track damage per player
   - Flag players taking significantly more damage than others

2. **Interrupt Tracker** - Successful kicks and missed interrupts
   - Parse `SPELL_INTERRUPT` events
   - Track `SPELL_CAST_START` for interruptible casts
   - Detect missed interrupts (cast completed without interrupt)

3. **Phoenix Web Setup** - Basic encounter list and event summary views

---

## Files Modified This Session

**Created:**
- `lib/combat_log_parser/analyzers/death_analyzer.ex`
- `docs/sessions/2025-11-24_death_analyzer_and_cleanup.md` (this file)

**Modified:**
- `CLAUDE.md` - Data source clarification, M+ secondary goal, session log rules
- `lib/combat_log_parser.ex` - Removed personal DPS code, kept death analysis
- `lib/combat_log_parser/log_reader.ex` - Fixed unused variable warnings
- `test_parse.exs` - Simplified to only show deaths

**Deleted:**
- `lib/combat_log_parser/damage_analyzer.ex`
- `docs/GETTING_STARTED.md`

---

## Key Context for Next Session

1. **Death analyzer works** - Successfully tested on 603MB combat log, 20 encounters
2. **Field positions are explicit** - Use index 31 for damage amount (advanced logging)
3. **No personal DPS code** - Deleted, will rebuild raid-wide DPS when needed
4. **`./data/` is legacy** - Contains Warcraft Logs CSV exports, NOT used by parser
5. **Combat logs at** `/mnt/g/World of Warcraft/_retail_/Logs/`
6. **MVP target:** Midnight expansion raids (late Jan - March 2026)

---

## Running the Parser

```bash
cd combat_log_parser
mix compile
mix run test_parse.exs
```

Output shows encounter count and death summary with recaps.
