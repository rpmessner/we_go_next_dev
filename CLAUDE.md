# WoW Performance Analysis Project

## Purpose
This project is dedicated to analyzing performance metrics for rpmessner's World of Warcraft characters. The goal is to assess gameplay performance, identify areas for improvement, and track progress over time.

## Long-Term Vision
**Real-Time Combat Analysis Dashboard**: Develop a web application that runs alongside the WoW client and provides real-time feedback on combat performance by parsing the WoW combat log as it's being written. The dashboard will analyze incoming combat data and provide optimization suggestions, mechanic warnings, and performance metrics in real-time during gameplay.

### Current Phase: Combat Log Parser Development ✅
- **Working Elixir parser** that reads WoW combat logs and extracts encounter data
- Parses encounter boundaries, damage events, and performance metrics
- Successfully analyzed 603MB combat log with 20 encounters
- Foundation for real-time analysis is established

### Next Phase: Analysis Engine Enhancement
- Add pet damage attribution (critical for Warlock/Hunter accuracy)
- Expand metrics: healing, deaths, buff uptime, cooldown tracking
- Implement rotation analysis and optimization detection
- Add real-time file watching for live parsing

### Future Phases
1. **Web Dashboard**: Display real-time metrics and suggestions in a browser (Phoenix LiveView)
2. **Optimization Alerts**: Provide actionable feedback during encounters
3. **Mechanic Tracking**: Boss ability detection and avoidable damage identification

## Data Sources
- **WoW Combat Log**: `/mnt/g/World of Warcraft/_retail_/Logs/` (enabled for real-time logging)
  - Primary source of truth for all combat data
  - CombatLog.txt is written in real-time during gameplay
- **Warcraft Logs CSV Exports**: Historical performance data exported from warcraftlogs.com
  - Located in `data/` directory, organized by boss/encounter
- **Warcraft Logs API**: GraphQL API for retrieving parse data and rankings (future integration)
  - API documentation: https://www.warcraftlogs.com/api/docs

## Current Workflow
1. Combat logging enabled in WoW client (writes to `/mnt/g/World of Warcraft/_retail_/Logs/`)
2. Run Elixir parser on combat log files: `mix run test_parse.exs`
3. Parser extracts encounters and analyzes damage output
4. Review performance metrics and identify areas for improvement
5. (Optional) Compare with Warcraft Logs CSV exports for validation

## Types of Analysis
- Parse percentile rankings
- Performance comparisons across characters
- Spec/class performance evaluation
- Fight-specific analysis
- Progression tracking
- Gear and optimization recommendations

## Character List
All characters are on **Wyrmrest Accord** realm (US)

### Main Raiding Character
- **Mittwoch** - Warlock (Demonology/Affliction)
- **Guild**: Hand of Algalon
- **Current Content**: Mythic Manaforge Omega

### Alts
- **Nekoken** - Druid
- **Elehal** - Mage
- **Kitsuneken** - Death Knight
- **Kumaken** - Shaman
- **Pannonica** - Demon Hunter
- **Kossil** - Priest
- **Shoryuken** - Monk
- **Kyouken** - Rogue
- **Tatsuken** - Warrior
- **Soryuken** - Evoker
- **Kekonen** - Paladin

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
├── data/                           # Warcraft Logs CSV exports (historical)
│   ├── guild_reports.csv
│   └── [boss_name]_[difficulty]/  # Per-encounter folders
├── docs/
│   ├── sessions/                   # Immutable session logs
│   └── GETTING_STARTED.md          # Comprehensive guide
├── analysis_output_*.txt           # Parser output files
├── CLAUDE.md                       # This file
└── weekly_performance_review.md    # Performance review template
```

### File Naming Conventions
- All lowercase with underscores
- No spaces (terminal-friendly, tab-completable)
- Example: `mittwoch_damage_done.csv` NOT `Mittwoch Damage Done.csv`

### Session Documentation
- Location: `docs/sessions/YYYY-MM-DD_description.md`
- **Immutable**: Never edit old session logs, always create new ones
- Purpose: Backward-facing record of all project work

## Important Guidelines

### Do NOT Use
- **Details Addon**: Being deprecated by Blizzard soon; not worth parsing
- WoW's built-in damage meter (doesn't save logs)

### DO Use
- **WoW Combat Log** as primary source of truth
- **Warcraft Logs CSV Exports** for historical analysis
- **Warcraft Logs API** for future integration

## Quick Reference

### Key Locations
- **Project Root**: `/home/rpmessner/wow_analysis/`
- **Combat Logs**: `/mnt/g/World of Warcraft/_retail_/Logs/`
- **Downloads**: `/mnt/c/Users/rpmes/Downloads/`
- **Session Logs**: `docs/sessions/`

### Documentation
- **Getting Started**: `docs/GETTING_STARTED.md` - Comprehensive guide for new sessions
- **Session History**: `docs/sessions/` - All past session logs
- **This File**: Core project context and character roster

## Technical Details

### Combat Log Format (Discovered 2025-11-22)
- **Format:** Two-space delimited timestamp + CSV event data
- **Version:** Combat Log Version 22, Advanced Logging Enabled
- **Structure:** `MM/DD/YYYY HH:MM:SS.mmm-TZ  EVENT_TYPE,field1,field2,...`
- **Advanced Logging:** Adds variable-length fields between spell info and damage suffix
- **Damage Position:** Damage amount appears ~7-10 fields from end of data array
- **Pet Tracking:** Pets have separate source GUIDs (need SPELL_SUMMON event tracking)

### Parser Architecture
- **Language:** Elixir (leverages streams for efficient log processing)
- **Location:** `combat_log_parser/` Mix project
- **Entry Point:** `CombatLogParser.parse(log_path)` returns list of encounters
- **Key Modules:**
  - `LogReader` - Streams and parses log files
  - `Encounter` - Encounter data structure with metadata
  - `DamageAnalyzer` - Analyzes damage output per player

### Known Limitations
1. **Pet damage not attributed** - Pet/summon damage has separate source GUIDs
   - Impact: Warlock/Hunter DPS values are 70%+ lower than actual
   - Fix needed: Track SPELL_SUMMON events to map pet owners
2. **DoT damage may be undercounted** - Needs verification with periodic damage events
3. **No multi-target detection** - Can't distinguish trash vs boss damage yet
4. **Memory usage** - Entire log loaded into memory (works for 603MB, may scale issues)

### Running the Parser
```bash
cd combat_log_parser
mix compile
mix run test_parse.exs  # Analyzes most recent combat log
```

## Notes
- Focus on actionable insights that help improve gameplay
- Consider context (raid composition, fight mechanics, gear level) when analyzing performance
- End goal is real-time analysis, not just historical reports
- Build incrementally from simple to complex
- **Parser validated:** Direct combat log parsing is feasible and provides all needed data
