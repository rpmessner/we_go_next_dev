# WoW Diagnostic Tool

## Purpose
A diagnostic tool for raid progression and Mythic+ dungeons. Diagnoses mechanic failures, coaches players privately, and improves group performance. Built for Hand of Algalon on Wyrmrest Accord.

**Primary Focus:** Raid progression (MVP for Midnight launch)
**Secondary Focus:** Mythic+ analysis (works automatically, enhanced features post-MVP)

## Long-Term Vision
**Real-Time Diagnostic Dashboard**: A web application that runs alongside WoW and provides:
1. **Live dashboard during pulls** - Glanceable mechanic failures, deaths, danger indicators
2. **Between-pull analysis** - What went wrong, who needs coaching, are we improving
3. **Strategy diagrams** - Annotated minimap images for Discord coordination

### Target Launch: Midnight Expansion Raids (Early 2026)
- **Midnight release:** Expected late January - March 2026
- **First raids:** The Voidspire (6 bosses), The Dreamrift (1 boss), March of Quel'Danas (2 bosses)
- **MVP Goal:** Working diagnostic tool ready for Day 1 raid progression

### Mythic+ Support
The same combat log powers both raid and M+ analysis. Core features work identically:
- **Deaths** - Same tracking, M+ adds time penalty context (post-MVP)
- **Interrupts** - Critical for both; M+ kick rotations are life or death
- **Avoidable damage** - Same detection, M+ aggregates per-dungeon (post-MVP)

**MVP:** M+ analysis works out of the box (same analyzers as raid)
**Post-MVP:** M+-specific features (death timer cost, affix tracking, dungeon summaries)

### Current Phase: Foundation ✅
- Working Elixir parser that reads WoW combat logs
- Parses encounter boundaries and combat events
- Successfully tested on 603MB combat log with 20 encounters

### Key Differentiator
This is NOT a damage meter. It's a **coaching tool** that:
- Identifies mechanic failures (who stood in fire, missed soaks, failed interrupts)
- Generates private feedback for individual players
- Builds boss profiles iteratively during progression
- Helps raid leaders diagnose wipes without public callouts

## Three Output Modes

### 1. During Pull (Live Dashboard)
- Who's dead and why
- Mechanic failures as they happen
- Current danger indicators
- Glanceable while raid leading

### 2. Between Pulls (Analysis Report)
- What killed us / why we wiped
- Per-player mechanic failures with timestamps
- Comparison to previous attempts
- Actionable items for next pull

### 3. Strategy Communication (Discord)
- Annotated minimap diagrams
- Position markers, movement arrows, assignments
- Can overlay actual death locations from combat data
- Exportable PNG images for Discord

## Iterative Boss Criteria Building

Since you can't predict what mechanics cause problems during progression:

1. **Discovery Mode** - Surface "interesting events" (deaths, big damage, debuffs)
2. **Pattern Recognition** - Notice "people keep dying to X ability"
3. **Mark as Tracked** - Flag ability as avoidable/interrupt/soak/etc
4. **Dashboard Updates** - Next pull shows failures for tracked mechanics
5. **Save Profile** - Export boss config for future raid nights

## Data Sources

### Primary: WoW Combat Log (Used by Parser)
**Location:** `/mnt/g/World of Warcraft/_retail_/Logs/WoWCombatLog-*.txt`

This is the **only** data source the parser uses. These are raw combat log files written by the WoW game client in real-time during gameplay. Format:
```
11/22/2025 11:20:43.174-5  COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,...
11/22/2025 11:39:35.297-5  ENCOUNTER_START,2887,"Plexus Sentinel",15,20,2652
11/22/2025 11:40:38.319-5  UNIT_DIED,0000000000000000,nil,...,Player-3676-0E1BB922,"Favikul-Area52-US",...
```

### NOT Used: Warcraft Logs CSV Exports
**Location:** `./data/` directory (legacy, not used by parser)

The `data/` folder contains CSV exports from warcraftlogs.com website - these are **processed/aggregated** data, not raw combat logs. They were used in early exploration but are **not** used by the combat log parser. Example content:
```csv
"Name","Amount","Casts","Avg Cast",...
"Diabolic Ritual","694526998$26.47%694.53m","-","-",...
```

### Future: Strategy Diagrams
- **Minimap Backgrounds**: Datamined arena maps for strategy diagrams (post-MVP)

## Character List
All characters on **Wyrmrest Accord** (US)

### Main Raiding Character
- **Mittwoch** - Warlock (Demonology/Affliction)
- **Guild**: Hand of Algalon
- **Current Content**: Mythic Manaforge Omega

### Alts
Nekoken (Druid), Elehal (Mage), Kitsuneken (DK), Kumaken (Shaman), Pannonica (DH), Kossil (Priest), Shoryuken (Monk), Kyouken (Rogue), Tatsuken (Warrior), Soryuken (Evoker), Kekonen (Paladin)

## Project Organization

### Directory Structure
```
wow_analysis/
├── combat_log_parser/              # Elixir combat log parser (Mix project)
│   ├── lib/
│   │   ├── combat_log_parser.ex           # Main API
│   │   └── combat_log_parser/
│   │       ├── encounter.ex               # Encounter data structure
│   │       ├── log_reader.ex              # File parsing
│   │       └── damage_analyzer.ex         # Damage analysis
│   ├── test_parse.exs                     # Test/demo script
│   └── mix.exs                            # Project config
├── data/                           # Legacy Warcraft Logs CSV exports (NOT used by parser)
├── docs/
│   ├── sessions/                   # Immutable session logs
│   ├── ROADMAP.md                  # Development roadmap
│   ├── TECHNICAL_ARCHITECTURE.md   # Tech stack details
│   └── HANDOFF.md                  # Next steps for implementation
├── CLAUDE.md                       # This file
└── analysis_output_*.txt           # Parser output files
```

### Session Documentation
- Location: `docs/sessions/YYYY-MM-DD_description.md`
- **Immutable**: Never edit old session logs, always create new ones
- **Exception**: If information is later found to be incorrect, you may:
  1. ~~Strike through~~ the incorrect text using `~~strikethrough~~`
  2. Add a clarification remark (e.g., "*[Note: This was incorrect, see session X]*")
- These are the **only** allowable modifications to historical session logs

## Quick Reference

### Key Locations
- **Project Root**: `/home/rpmessner/dev/games/wow_analysis/`
- **Combat Logs**: `/mnt/g/World of Warcraft/_retail_/Logs/`
- **Session Logs**: `docs/sessions/`

### Documentation
- **Roadmap**: `docs/ROADMAP.md` - Development phases and priorities
- **Architecture**: `docs/TECHNICAL_ARCHITECTURE.md` - Tech stack decisions
- **Handoff**: `docs/HANDOFF.md` - Next implementation steps
- **Sessions**: `docs/sessions/` - Historical session logs

### Running the Parser
```bash
cd combat_log_parser
mix compile
mix run test_parse.exs  # Analyzes most recent combat log
```

## Technical Details

### Combat Log Events for Diagnostics
- `SPELL_DAMAGE` - Avoidable damage (standing in bad)
- `SPELL_INTERRUPT` - Interrupt assignments (and missed)
- `SPELL_AURA_APPLIED` - Debuffs that shouldn't happen
- `UNIT_DIED` - Deaths with cause analysis
- `SWING_DAMAGE`, `SPELL_PERIODIC_DAMAGE` - Damage patterns

### Tech Stack
- **Parser**: Elixir (streams, pattern matching, fault tolerance)
- **Dashboard**: Phoenix LiveView (real-time updates)
- **Diagrams**: Image generation with minimap backgrounds
- **State**: OTP GenServers, ETS for fast lookups

## Recent Updates

### 2025-11-24: Added Mythic+ as Secondary Goal
- M+ analysis works automatically (same combat log, same analyzers)
- Raid progression remains primary focus for MVP
- M+-specific features (death timers, affix tracking) planned for post-MVP

### 2025-11-24: Project Pivot to Diagnostic Tool
- Shifted from personal DPS analysis to raid-wide diagnostic focus
- Target launch: Midnight expansion raids (early 2026)
- Three output modes: live dashboard, between-pull analysis, strategy diagrams
- Iterative boss criteria building for progression
- Private coaching focus (not public callouts)

### 2025-11-23: WoWAnalyzer Research
- Studied WoWAnalyzer architecture patterns
- Identified normalizer pipeline approach
- Created initial roadmap (now superseded by diagnostic focus)

### 2025-11-22: Combat Log Parser Working
- Built Elixir parser for WoW combat logs
- Successfully parsed 603MB log with 20 encounters
- Foundation established for real-time processing

## Development Philosophy

### PRIME DIRECTIVE: MVP for Midnight Raids
**The tool MUST be usable for Day 1 Midnight progression (late Jan - March 2026).**

When making scope decisions:
- Cut features before missing the launch window
- "Good enough" beats "perfect but late"
- Core loop (deaths → failures → reports) is non-negotiable
- Everything else is negotiable

If falling behind schedule:
1. Cut strategy diagrams (Phase 6)
2. Simplify criteria system (hardcode common mechanics)
3. Skip polish (Phase 7)
4. Reduce report tiers to just "raid lead" view

**Post-Midnight:** After launch, deadline pressure is off. Take time for polish and new features without a hard target.

### Other Principles
- **Progression-focused**: Build what we need as we discover problems
- **Private coaching**: Help players improve without embarrassment
- **Iterative**: Start generic, add boss-specific criteria during prog
- **Real-time**: Information when it matters (during and between pulls)
