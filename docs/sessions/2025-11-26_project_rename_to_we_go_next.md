# Session: Project Rename to "we_go_next"
**Date:** 2025-11-26
**Focus:** Rename project from `combat_log_parser` to `we_go_next`

## Overview
Completed full project rename from the generic "combat_log_parser" to the raid-themed "we_go_next" - a reference to the common phrase used in raid progression ("we go next" after a wipe).

## Changes Made

### 1. Database Setup
- Created new PostgreSQL database: `we_go_next_dev`
- Migrated all tables (users, combat_log_files, encounters)
- Dropped old database: `combat_log_parser_dev`

### 2. Mix Project Configuration
**File: `mix.exs`**
- Changed app name: `:combat_log_parser` → `:we_go_next`
- Updated module: `CombatLogParser.MixProject` → `WeGoNext.MixProject`
- Updated application module: `CombatLogParser.Application` → `WeGoNext.Application`
- Updated asset build aliases: `tailwind combat_log_parser` → `tailwind we_go_next`

### 3. Configuration Files
Updated all config files (`config/*.exs`):
- Changed app atom: `:combat_log_parser` → `:we_go_next`
- Updated all module references: `CombatLogParser.*` → `WeGoNext.*`
- Updated web module references: `CombatLogParserWeb.*` → `WeGoNextWeb.*`
- Updated database names: `combat_log_parser_dev/test` → `we_go_next_dev/test`
- Updated file watching patterns to look for `lib/we_go_next_web/` instead of `lib/combat_log_parser_web/`

### 4. Directory Structure Rename
```bash
lib/combat_log_parser/     → lib/we_go_next/
lib/combat_log_parser_web/ → lib/we_go_next_web/
lib/combat_log_parser.ex   → lib/we_go_next.ex
lib/combat_log_parser_web.ex → lib/we_go_next_web.ex
test/combat_log_parser_test.exs → test/we_go_next_test.exs
```

### 5. Module Namespace Updates
Applied global find-and-replace across all `.ex` and `.exs` files:
- `CombatLogParserWeb` → `WeGoNextWeb` (25 files)
- `CombatLogParser` → `WeGoNext` (25 files)
- `:combat_log_parser` → `:we_go_next` (all config and source files)

**Files updated:**
- All 25 source files in `lib/we_go_next/`
- All web files in `lib/we_go_next_web/`
- Test files: `test/we_go_next_test.exs`, `test/test_helper.exs`, `test/support/feature_case.ex`, `test/features/encounter_list_test.exs`
- Demo script: `test_parse.exs`

### 6. Verification
- ✅ Clean compilation successful
- ✅ Database migrations ran successfully
- ✅ Assets built successfully
- ✅ Phoenix server started and responded to HTTP requests (200 OK)
- ⚠️ Only warnings: unused imports and default argument style (non-breaking)

## Notes

### Project Directory Not Renamed
The project directory itself remains `~/dev/games/wow_analysis/combat_log_parser`. User will manually rename to `we_go_next`.

### Leftover SQLite Files
Found orphaned SQLite WAL files from pre-PostgreSQL migration:
```
combat_log_parser.db-shm
combat_log_parser.db-wal
combat_log_parser_test.db-shm
combat_log_parser_test.db-wal
```

These can be safely deleted: `rm -f combat_log_parser*.db*`

### Browser Session Caveat
Existing browser sessions may have cached session tokens containing serialized old module names (`CombatLogParserWeb.Router`). Users need to:
- Clear browser cookies for localhost:4000, OR
- Use incognito/private browsing window

Fresh sessions work correctly with the new module names.

## Why "we_go_next"?
The name references common raid progression terminology - after a wipe, the raid leader says "we go next" and the group immediately pulls the boss again. It fits the tool's purpose perfectly:
- Between-pull diagnostic tool
- Helps teams learn from wipes and iterate quickly
- Embodies the raid progression mentality

Much better than the generic "combat_log_parser"!

## Technical Details

### Module Hierarchy (Before → After)
```
CombatLogParser                    → WeGoNext
├── Application                    → Application
├── Repo                           → Repo
├── Accounts                       → Accounts
├── EncounterStore                 → EncounterStore
├── LogReader                      → LogReader
├── Importer                       → Importer
├── CombatLogFile                  → CombatLogFile
├── Encounter                      → Encounter
└── Analyzers                      → Analyzers
    ├── DeathAnalyzer              → DeathAnalyzer
    ├── DamageTakenAnalyzer        → DamageTakenAnalyzer
    ├── InterruptAnalyzer          → InterruptAnalyzer
    └── DebuffAnalyzer             → DebuffAnalyzer

CombatLogParserWeb                 → WeGoNextWeb
├── Endpoint                       → Endpoint
├── Router                         → Router
├── Components                     → Components
├── Live                           → Live
└── Controllers                    → Controllers
```

### Database Schema
Tables remain unchanged (no need to rename):
- `users`
- `combat_log_files`
- `encounters`

Only the database name changed: `combat_log_parser_dev` → `we_go_next_dev`

## Next Steps
1. User will manually rename project directory from `combat_log_parser` to `we_go_next`
2. Clean up SQLite artifacts
3. Update any external references (if any exist)
4. Consider updating CLAUDE.md to reflect the new project name
