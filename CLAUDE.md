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

### Current Phase: Medallion Warehouse and Rules Foundation

The original analyzer/UI MVP exists, but the current architecture work is moving new analytics onto a medallion-style backend:

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
- ✅ Bronze provenance and live/archive log reconciliation
- ✅ Silver projection tables keyed by `gold.dim_encounter.id`
- ✅ Gold `fact_failure` proof-of-concept derived from silver/gold tables
- ✅ Rules schema foundation for authored mechanic criteria

**Current board focus:** finish rules-backed gold criterion snapshots, make `gold.fact_failure` ruleset-aware, then hook silver/gold rebuilds into importer. PR1 acceptance is gated on this path plus silver/move-detection verification.

### Key Differentiator

This is NOT just a damage meter. It's a **coaching tool** that:

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

### Warcraft Logs CSV Exports

**Location:** `./data/` directory

The `data/` folder contains processed CSV exports from warcraftlogs.com. They are **not** bronze parser input and must not be treated like raw combat logs. They are currently acceptable as curated evidence for initial mechanic rule seeds when the spell ID can be resolved from local reference data.

Example content:

```csv
"Name","Amount","Casts","Avg Cast",...
"Diabolic Ritual","694526998$26.47%694.53m","-","-",...
```

Current bundled rules seed uses only local evidence that can be resolved confidently:

- `Arcane Expulsion` spell `1214081`, avoidable, from `data/naazindhri_mythic/mittwoch_damage_taken.csv` and pull-summary docs
- `Void Burst` spell `1269183`, avoidable, from `data/naazindhri_mythic/mittwoch_damage_taken.csv`

Do not invent rule rows for CSV spell names that do not have a reliable local spell ID mapping.

### Future: Strategy Diagrams

- **Minimap Backgrounds**: Datamined arena maps for strategy diagrams (post-MVP)

### Future: Patch-Aware Rule Source Data

New patch/season mechanic source data should be handled by a later bronze/source-data ingestion path. Do not block PR1 on this. The near-term rules foundation should work with local curated data and keep a clean import path for future spell/encounter metadata updates.

## Current Architecture: Bronze, Silver, Gold, Rules

### Layer Ownership

- **Bronze/log ingestion** owns raw WoW combat log files and provenance. `combat_log_files` remains the operational catalog for live and Warcraft Logs archive files.
- **Silver** owns deterministic encounter-grain projections under the `silver` Postgres schema: damage taken, damage done, deaths, interrupt opportunities, debuff applications, and player info.
- **Gold** owns analytic dimensions/facts under the `gold` schema. Current fact proof: `gold.fact_failure`.
- **Rules** owns authored mechanic business configuration under the `rules` schema. Rules are not silver event data and are not mutable gold facts.

### Current Medallion Grain

- `gold.dim_encounter.id` is the analytics encounter grain.
- Silver tables use `encounter_dim_id`, not legacy `public.encounters.id`.
- `gold.dim_player` is conformed from `silver.player_info`.
- `gold.dim_mechanic_criterion` is the criterion snapshot table that facts reference.
- `gold.fact_failure` uses `(encounter_dim_id, player_dim_id, criterion_dim_id)` as its composite key.

### Legacy Boundary

The existing frontend import flow and `public.encounters` are transitional app-domain surfaces used to load combat logs and bridge into the medallion pipeline. `public.mechanic_criteria`, legacy analyzer JSON cache output, and the old encounter detail analysis tabs are legacy-only and must not be used for new medallion views.

The legacy `/encounters/:id` analysis page has been pruned from active routing. Any replacement analysis page should be rebuilt against silver/gold/rules read models, not resurrected from cached analyzer output or the old public criteria flow.

### Rules Layer Decisions

- `rules.ruleset` supports `draft`, `active`, and `archived`.
- Exactly one active ruleset globally for the first implementation pass.
- Backfills/tests should be able to select a ruleset explicitly by ID.
- `rules.mechanic_criterion` validates thresholds by mechanic type:
  - `avoidable`: only `threshold["max_hits"]` as a non-negative integer
  - `interrupt`: optional `threshold["must_interrupt"]`, defaults to `true`
  - `soak`, `spread`, `stack`, `tank_mechanic`, `healer_mechanic`: empty threshold map until fact semantics exist
- Seed rules through `WeGoNext.Rules` and `mix we_go_next.seed_rules`, not migrations.
- Gold facts should identify rules through `criterion_dim_id -> gold.dim_mechanic_criterion`, not a direct mutable rule row.

### Rules Refactor Order

Task board order before importer hook:

1. `#27` Promote `rules.mechanic_criterion` into `gold.dim_mechanic_criterion` snapshots.
2. `#28` Make `Gold.FactFailure.rebuild_for_encounter/1` ruleset-aware.
3. `#14` Hook silver/gold into importer after #28.

Silver verification tasks (`#16`, `#17`, `#19`) can proceed in parallel because they do not depend on rules.

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
we_go_next_dev/
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
│   │   │   ├── bronze/                    # Bronze reconciliation helpers
│   │   │   ├── silver/                    # Silver Ecto schemas
│   │   │   ├── gold/                      # Gold dimensions/facts
│   │   │   ├── rules.ex                   # Rules context
│   │   │   ├── rules/                     # Rules Ecto schemas
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
│   ├── priv/rules/                        # Static curated rules seed JSON
│   ├── mix.exs                            # Project config
│   └── priv/repo/migrations/              # Database migrations
├── data/                           # Warcraft Logs CSV exports used only as curated seed evidence
├── tools/                          # Local spell/dungeon reference JSON
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
  2. Add a clarification remark (e.g., "_[Note: This was incorrect, see session X]_")
- These are the **only** allowable modifications to historical session logs

## Quick Reference

### Key Locations

- **Repo Root**: `/home/rpmessner/dev/games/wow-addons/we_go_next_dev/`
- **Phoenix App**: `/home/rpmessner/dev/games/wow-addons/we_go_next_dev/we_go_next/`
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

### 2026-05-18: Failures View and Legacy Analysis Pruning

- Added `/failures` as the first medallion-backed UI, reading grouped mechanic failures from `gold.fact_failure` and gold dimensions.
- Closed the PR1 backend acceptance gate and moved PR2 UI work behind medallion read models.
- Pruned the legacy encounter detail route and tab components that read cached analyzer JSON and `public.mechanic_criteria`.
- Changed importer legacy JSON analysis cache computation to opt-in only; medallion imports remain the default path for new analytics.

### 2026-05-17: Medallion and Rules Foundation

- Reworked gold/silver failure fact path away from legacy public-domain tables.
- Added `gold.dim_encounter` as the analytics encounter grain.
- Re-keyed silver projections to `encounter_dim_id`.
- Added `gold.dim_mechanic_criterion` as the current criterion snapshot table.
- Added `rules` schema with `rules.ruleset` and `rules.mechanic_criterion`.
- Added idempotent rules seed path via `priv/rules/initial_mechanic_rules.json` and `mix we_go_next.seed_rules`.
- Seeded initial local evidence rules for `Arcane Expulsion` and `Void Burst`.
- Refactored importer encounter insertion to distinguish inserted vs existing rows so future rebuild hooks run only for new encounters.
- Created `docs/rules_layer_refactor.md` for the broader rules-layer plan.

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

## Testing

### Feature Tests with Page Objects

Feature tests (Wallaby integration tests) **must use the page object pattern**. This keeps tests readable and maintainable.

**Page objects location:** `test/support/pages/`

**Pattern:**

```elixir
# Good - using page objects
session
|> HomePage.navigate()
|> HomePage.ensure_page_loaded()
|> HomePage.select_log_file()
|> HomePage.click_import()
|> HomePage.wait_for_encounters()
|> HomePage.click_first_encounter()
|> EncounterDetailPage.ensure_page_loaded()

# Bad - raw selectors in tests
session
|> visit("/")
|> assert_has(css("h1", text: "WoW Raid Diagnostic Tool"))
|> execute_script("var select = document.querySelector...")
|> click(css("button[type='submit']"))
```

**Available page objects:**

- `HomePage` - Encounter list, log selection, import/refresh
- `EncounterDetailPage` - Encounter detail view, tabs, assertions
- `SettingsPage` - Path configuration, file watching

**Creating new page objects:**

1. Create `test/support/pages/your_page.ex`
2. `use Wallaby.DSL`
3. Add `navigate/1`, `ensure_page_loaded/1` functions
4. Add action functions (`click_*`, `fill_in_*`)
5. Add assertion functions (`assert_*`)

**Reference:** See `~/dev/fun/tilex/test/support/pages/` for the original pattern.

### Caching

Explore all other alternatives before reaching for ets table caching

### Running Tests

```bash
# All tests
mix test

# Feature tests only
mix test test/features/

# Specific test
mix test test/features/minimal_flow_test.exs

# With Credo
mix credo
```
