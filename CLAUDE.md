# WoW Diagnostic Tool

## Purpose
A diagnostic tool for raid progression and Mythic+ dungeons. Diagnoses mechanic failures, coaches players privately, and improves group performance. Built for Hand of Algalon on Wyrmrest Accord.

**Primary Focus:** Raid progression (MVP for Midnight launch)
**Secondary Focus:** Mythic+ analysis (works automatically, enhanced features post-MVP)

## Long-Term Vision
**Between-Pull Diagnostic Dashboard**: A web application that runs alongside WoW and provides:
1. **Instant between-pull analysis** - What went wrong, who needs coaching, are we improving
2. **Strategy diagrams** - Annotated minimap images for Discord coordination
3. **Private coaching reports** - Per-player feedback for Discord DMs

**Note on "Live" Updates:** WoW buffers combat log writes during active combat (can delay minutes). True real-time during pulls would require an in-game addon. Our tool focuses on **instant analysis when encounters end** - the log flushes on `ENCOUNTER_END` and we process immediately. This is when feedback is actionable anyway (during runback/rebuff).

### Target Launch: Midnight Expansion Raids
- **Midnight release:** March 2, 2026
- **Raid opening:** Mid-March 2026 (typically 1-2 weeks after expansion launch)
- **First raids:** The Voidspire (6 bosses), The Dreamrift (1 boss), March of Quel'Danas (2 bosses)
- **MVP Goal:** Working diagnostic tool ready for Day 1 raid progression

### Mythic+ Support
The same combat log powers both raid and M+ analysis. Core features work identically:
- **Deaths** - Same tracking, M+ adds time penalty context (post-MVP)
- **Interrupts** - Critical for both; M+ kick rotations are life or death
- **Avoidable damage** - Same detection, M+ aggregates per-dungeon (post-MVP)

**MVP:** M+ analysis works out of the box (same analyzers as raid)
**Post-MVP:** M+-specific features (death timer cost, affix tracking, dungeon summaries)

### Current Phase: MVP Core Complete ✅
All non-negotiable MVP features are implemented:
- ✅ Working Elixir parser that reads WoW combat logs
- ✅ Parses encounter boundaries and combat events
- ✅ Death analyzer with killing blow and damage recap
- ✅ Damage taken analyzer with tank/non-tank separation
- ✅ Interrupt analyzer with missed kick detection
- ✅ Debuff analyzer with player/spell aggregation
- ✅ Failure analyzer with criteria-based mechanic tracking
- ✅ Pull Summary report with wipe cause, recommendations
- ✅ Phoenix LiveView dashboard with Summary tab
- ✅ File watcher for log monitoring
- ✅ Criteria system for marking trackable mechanics

**Next Phase:** End-to-end integration testing (see `docs/INTEGRATION_ROADMAP.md`)

### Key Differentiator
This is NOT a damage meter. It's a **coaching tool** that:
- Identifies mechanic failures (who stood in fire, missed soaks, failed interrupts)
- Generates private feedback for individual players
- Builds boss profiles iteratively during progression
- Helps raid leaders diagnose wipes without public callouts

## Three Output Modes

### 1. Between Pulls (Primary - Analysis Report)
- What killed us / why we wiped
- Per-player mechanic failures with timestamps
- Comparison to previous attempts
- Actionable items for next pull
- Ready within seconds of encounter ending

### 2. In-Game Distribution (Optional - Post-MVP)
- we_go_next writes analysis to WoW SavedVariables
- Raid lead `/reload` → WeGoNext addon reads results
- Addon broadcasts to all raid members via addon comm
- Each player sees personalized performance breakdown
- No verbal callouts needed (MRT-style sharing)
- **Note:** MCP server used only for addon development, not during raids

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
├── we_go_next/                     # Phoenix/Elixir web app (Mix project)
│   ├── lib/
│   │   ├── we_go_next.ex                  # Main API
│   │   ├── we_go_next/
│   │   │   ├── analyzers/                 # Analysis modules
│   │   │   │   ├── death_analyzer.ex      # Death tracking ✓
│   │   │   │   ├── damage_taken_analyzer.ex # Damage tracking ✓
│   │   │   │   ├── interrupt_analyzer.ex  # Interrupt tracking ✓
│   │   │   │   ├── debuff_analyzer.ex     # Debuff tracking ✓
│   │   │   │   ├── failure_analyzer.ex    # Criteria-based failure detection ✓
│   │   │   │   └── pull_summary.ex        # Between-pull report generation ✓
│   │   │   ├── encounter.ex               # Encounter data structure
│   │   │   ├── encounter_store.ex         # ETS-backed encounter cache
│   │   │   ├── log_reader.ex              # File parsing with byte offsets
│   │   │   ├── importer.ex                # Incremental log import
│   │   │   ├── combat_log_file.ex         # Ecto schema for log files
│   │   │   ├── encounters/
│   │   │   │   └── encounter.ex           # Ecto schema for encounters
│   │   │   ├── accounts.ex                # User management
│   │   │   ├── application.ex             # OTP application
│   │   │   └── repo.ex                    # PostgreSQL Ecto repo
│   │   └── we_go_next_web/
│   │       ├── endpoint.ex                # Phoenix endpoint
│   │       ├── router.ex                  # Routes
│   │       ├── live/
│   │       │   ├── encounter_live/
│   │       │   │   ├── index.ex           # Encounter list LiveView
│   │       │   │   └── show.ex            # Encounter detail LiveView
│   │       │   └── settings_live.ex       # Settings LiveView
│   │       ├── components/                # Reusable components
│   │       └── controllers/               # Error handling
│   ├── test_parse.exs                     # CLI test/demo script
│   ├── mix.exs                            # Project config
│   └── priv/repo/migrations/              # Database migrations
├── data/                           # Legacy Warcraft Logs CSV exports (NOT used by parser)
├── docs/
│   ├── sessions/                   # Immutable session logs
│   ├── ROADMAP.md                  # Development roadmap
│   ├── TECHNICAL_ARCHITECTURE.md   # Tech stack details
│   └── WOW_MCP_INTEGRATION_ROADMAP.md  # MCP for addon development
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
- **Integration**: `docs/INTEGRATION_ROADMAP.md` - End-to-end testing plan
- **Architecture**: `docs/TECHNICAL_ARCHITECTURE.md` - Tech stack decisions
- **Sessions**: `docs/sessions/` - Historical session logs

### Running the App
```bash
cd we_go_next
mix compile
mix phx.server              # Start web UI at http://localhost:4000
# OR
mix run test_parse.exs      # CLI: Analyzes most recent combat log
```

## Technical Details

### Combat Log Events for Diagnostics
- `SPELL_DAMAGE` - Avoidable damage (standing in bad)
- `SPELL_INTERRUPT` - Interrupt assignments (and missed)
- `SPELL_AURA_APPLIED` - Debuffs that shouldn't happen
- `UNIT_DIED` - Deaths with cause analysis
- `SWING_DAMAGE`, `SPELL_PERIODIC_DAMAGE` - Damage patterns

### Tech Stack
- **Backend**: Elixir (streams, pattern matching, fault tolerance)
- **Web Framework**: Phoenix with LiveView (real-time updates)
- **Database**: PostgreSQL with Ecto (encounter persistence, incremental parsing)
- **State Management**: OTP GenServers, ETS cache backed by DB
- **Diagrams**: Image generation with minimap backgrounds (future)

## Recent Updates

### 2025-11-28: MVP Core Complete - Pull Summary Implementation
- Implemented `PullSummary` analyzer that aggregates all analyzer outputs
- Added "Summary" tab as default view in encounter detail LiveView
- Summary includes: wipe cause, deaths breakdown, critical failures, players needing coaching, recommendations
- Updated roadmap: all non-negotiable MVP features now complete
- Created `docs/INTEGRATION_ROADMAP.md` for end-to-end testing plan
- Next step: wire up log selection UI and live file watching for real-time demo

### 2025-11-27: Criteria System and Failure Detection
- Implemented criteria system for tracking specific mechanics
- Added FailureAnalyzer that checks damage/interrupts against criteria
- Failures tab shows mechanic failures by player and by mechanic
- UI allows clicking abilities to mark them as "avoidable", "must interrupt", etc.

### 2025-11-26: Project Renamed to "we_go_next"
- Renamed from generic "combat_log_parser" to raid-themed "we_go_next"
- Name references raid progression phrase ("we go next" after wipes)
- Updated all module namespaces: `CombatLogParser` → `WeGoNext`, `CombatLogParserWeb` → `WeGoNextWeb`
- Migrated database: `combat_log_parser_dev` → `we_go_next_dev`
- All 25 source files updated, project compiles and runs successfully

### 2025-11-25: Phase 1 Complete, Between-Pull Focus Confirmed
- All four core analyzers complete (death, damage, interrupt, debuff)
- Clarified that WoW buffers combat log writes during combat (not suitable for true real-time)
- Confirmed between-pull analysis as primary focus - log flushes on encounter end
- "Live dashboard" renamed to "between-pull dashboard" throughout docs

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
- **Between-pull focus**: Analysis ready during runback when it's actionable
