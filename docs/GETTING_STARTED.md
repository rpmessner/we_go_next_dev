# Getting Started - WoW Performance Analysis Project

This document provides context for Claude and collaborators working on this project in future sessions.

---

## Quick Start for New Sessions

1. **Read** `PROJECT_CONTEXT.md` - Understand project goals and character roster
2. **Review** latest session in `docs/sessions/` - See what was done recently
3. **Check** `data/` directory - See what combat data is available
4. **Ask user** - What they want to accomplish this session

---

## Project Goal

Build a **real-time combat analysis dashboard** that parses WoW's combat log as it's being written and provides live performance feedback during gameplay.

**Current Phase:** Historical analysis using Warcraft Logs CSV exports to understand data structures and build analysis foundations.

**End Goal:** Web application that runs in browser alongside WoW client, analyzing combat in real-time and providing optimization suggestions.

---

## Important Context

### User's Main Character
- **Mittwoch** - Warlock on Wyrmrest Accord (US)
- Guild: Hand of Algalon
- Plays Demonology and Affliction specs
- See `PROJECT_CONTEXT.md` for full character roster (11 alts)

### Technology Stack
- **Primary Language:** Elixir
- **Why Elixir:** User knows Elixir really well, doesn't know Python much at all
- **Real-time Dashboard:** Phoenix LiveView
- **ML (if needed):** Nx/Axon/Bumblebee with Livebook
- **See:** `docs/TECHNICAL_ARCHITECTURE.md` for complete architecture details

### Data Sources Priority
1. **WoW Combat Log** (source of truth): `/mnt/g/World of Warcraft/_retail_/Logs/`
2. **Warcraft Logs CSV Exports**: `data/` directory
3. **Warcraft Logs API**: Future integration

### What NOT to Use
- **Details Addon**: Being deprecated by Blizzard, don't invest time parsing it
- **Python**: User doesn't know it well; stick to Elixir

### File Naming Conventions
- All lowercase
- Use underscores, not spaces
- Must be terminal-friendly for tab completion
- Example: `mittwoch_damage_done.csv` not `Mittwoch Damage Done.csv`

### Session Logs
- **Immutable**: Never edit old session logs, always create new ones
- **Location**: `docs/sessions/YYYY-MM-DD_description.md`
- **Purpose**: Backward-facing record of all project interactions
- **Required**: Document every session with comprehensive notes

---

## Project Structure

```
wow_analysis/
├── data/                           # Combat data exports
│   ├── guild_reports.csv          # Guild raid log list
│   └── [boss_name_difficulty]/    # Per-encounter folders
│       ├── mittwoch_damage_done.csv
│       ├── mittwoch_damage_taken.csv
│       ├── mittwoch_casts.csv
│       └── [other_exports].csv
├── docs/
│   ├── sessions/                   # Session logs (immutable)
│   │   └── YYYY-MM-DD_*.md
│   └── GETTING_STARTED.md          # This file
├── PROJECT_CONTEXT.md              # Core project documentation
└── weekly_performance_review.md    # Performance review template
```

---

## Data Sources Explained

### 1. WoW Combat Log (Primary Source)

**Location:** `/mnt/g/World of Warcraft/_retail_/Logs/`

**What it is:**
- Real-time log file written by WoW client during gameplay
- Contains all combat events, damage, healing, buffs, deaths, etc.
- This is the ultimate source of truth for all combat data
- User has this enabled

**Future Use:**
- Parse in real-time as file is being written
- Extract combat events for live analysis
- Build optimization engine on top of this data

**Current Use:**
- Not yet implemented
- Need to examine format and structure
- Will be foundation for real-time dashboard

### 2. Warcraft Logs CSV Exports (Current Source)

**Location:** `data/` directory in project

**What it is:**
- Manual CSV exports from warcraftlogs.com
- User uploads combat logs to Warcraft Logs website
- Website processes logs and provides analysis tools
- User exports specific encounter data as CSV files

**Available Export Types:**
- Damage Done (ability-by-ability breakdown)
- Damage Taken (incoming damage sources)
- Casts (spell cast counts and timing)
- Summons (pet/summon activity)
- Guild Reports (list of uploaded raid logs)

**Limitations:**
- Manual export process
- Doesn't include parse percentiles in CSV
- Historical data only (not real-time)
- Limited to what Warcraft Logs chooses to export

**Current Use:**
- Learning data structures
- Building analysis templates
- Understanding performance metrics

### 3. Warcraft Logs API (Future Integration)

**Documentation:** https://www.warcraftlogs.com/api/docs

**What it is:**
- GraphQL API (v2)
- Programmatic access to Warcraft Logs data
- Requires OAuth client credentials

**Potential Uses:**
- Query parse percentiles and rankings
- Retrieve detailed encounter data
- Compare performance against other players
- Historical analysis at scale

**Current Status:**
- Not yet implemented
- Need to set up API credentials
- Web scraping blocked (403 errors)

---

## Technical Environment

### System Setup
- **OS:** WSL2 (Windows Subsystem for Linux)
- **Project Location:** `/home/rpmessner/wow_analysis/`
- **WoW Installation:** `/mnt/g/World of Warcraft/` (Windows mount)
- **Downloads Folder:** `/mnt/c/Users/rpmes/Downloads/`

### WoW Installation Paths
- **Retail:** `/mnt/g/World of Warcraft/_retail_/`
- **Combat Logs:** `/mnt/g/World of Warcraft/_retail_/Logs/`
- **SavedVariables:** `/mnt/g/World of Warcraft/_retail_/WTF/Account/THEUGLYCANADIAN/Wyrmrest Accord/[Character]/SavedVariables/`

### Access Permissions
- Claude has read access to WoW Logs directory
- Can read files in `/mnt/g/World of Warcraft/_retail_/Logs/**`
- Can read files in `/mnt/g/World of Warcraft/_retail_/**`

---

## Development Roadmap

### Phase 1: Historical Analysis (Complete ✅)
**Goal:** Understand data structures and build analysis foundations

**Tasks:**
- [x] Set up project structure
- [x] Organize Warcraft Logs CSV exports
- [x] Create performance review templates
- [x] Examine combat log format
- [x] Build combat log parser (Elixir)
- [x] Define key performance metrics

### Phase 2: Combat Log Parser (Current)
**Goal:** Read and parse WoW combat log files

**Tasks:**
- [x] Document combat log format specification
- [x] Build event parser (Elixir Mix project)
- [x] Extract damage events
- [x] Test with historical combat logs (603MB, 20 encounters)
- [ ] Add pet damage attribution
- [ ] Extract healing/buff events
- [ ] Handle file rotation and log structure

### Phase 3: Analysis Engine
**Goal:** Analyze combat data for optimization insights

**Tasks:**
- [ ] Define rotation priorities per spec
- [ ] Implement damage analysis
- [ ] Implement uptime tracking
- [ ] Detect rotation mistakes
- [ ] Identify mechanic failures
- [ ] Generate actionable recommendations

### Phase 4: Real-Time Implementation
**Goal:** Parse combat log in real-time during gameplay

**Tasks:**
- [ ] File watching/tailing implementation
- [ ] Real-time event processing
- [ ] Performance optimization
- [ ] Handle concurrent reads (WoW writing, we're reading)
- [ ] Buffer and process events efficiently

### Phase 5: Web Dashboard
**Goal:** Display live analysis in web browser

**Tasks:**
- [ ] Choose tech stack
- [ ] Build real-time communication (WebSocket?)
- [ ] Design UI/UX for dashboard
- [ ] Implement metrics visualization
- [ ] Add alerts and notifications
- [ ] Optimize for low latency

---

## Common Tasks

### Adding New Combat Data

When user provides new Warcraft Logs exports:

1. **Create boss-specific folder**
   ```bash
   mkdir -p data/[boss_name]_[difficulty]
   ```

2. **Copy and rename files** (terminal-friendly names)
   ```bash
   cp "/mnt/c/Users/rpmes/Downloads/[original].csv" \
      data/[boss_name]_[difficulty]/mittwoch_[type].csv
   ```

3. **Types to organize:**
   - `mittwoch_damage_done.csv`
   - `mittwoch_damage_taken.csv`
   - `mittwoch_casts.csv`
   - `mittwoch_summons.csv`
   - `raid_damage_done.csv` (whole raid overview)

### Documenting a Session

At end of each session, create:
```
docs/sessions/YYYY-MM-DD_[topic].md
```

Include:
- Date and session overview
- What was accomplished
- Key decisions made
- Code/files created
- Problems encountered
- Next steps
- Important context for future

### Parsing Combat Logs

To parse and analyze combat logs:
```bash
cd combat_log_parser
mix compile
mix run test_parse.exs
```

To examine raw combat log files:
```bash
ls -lh "/mnt/g/World of Warcraft/_retail_/Logs/"
```

Combat log will be named something like:
- `WoWCombatLog-112225_112043.txt` (format: MMDDYY_HHMMSS)

### Analyzing Performance Data

Check what CSV data is available:
```bash
find data/ -name "*.csv" | sort
```

Read CSV structure:
```bash
head -20 data/[boss_folder]/mittwoch_damage_done.csv
```

---

## Key Performance Metrics

### DPS Metrics
- Overall DPS for encounter
- Damage per ability
- Critical strike percentage
- Cast counts and efficiency

### Uptime Metrics
- DoT uptime percentages (Affliction)
- Buff uptime
- Active time vs. downtime

### Rotation Analysis
- Spell priorities and sequencing
- Resource management (Soul Shards, etc.)
- Cooldown usage timing

### Defensive/Mechanic Metrics
- Damage taken
- Deaths and causes
- Mechanic execution (soaks, interrupts, etc.)

### Comparison Metrics
- Parse percentile (requires Warcraft Logs API)
- Performance vs. other warlocks
- Performance vs. user's own history

---

## Warlock-Specific Context

User plays **Warlock** with focus on **Demonology** and **Affliction** specs.

### Demonology Key Abilities
- Diabolic Ritual (hero talent)
- Hand of Gul'dan
- Demonbolt
- Summon Demonic Tyrant
- Pet damage (Felguard, Wild Imps, Charhounds, etc.)

### Affliction Key Abilities
- Wither (primary DoT)
- Unstable Affliction
- Malefic Rapture (Soul Shard spender)
- Agony
- Summon Darkglare
- DoT uptime is critical

### Performance Indicators
- **Demonology:** Pet damage contribution, Diabolic Ritual damage, Tyrant timing
- **Affliction:** DoT uptime (99%+ is excellent), Malefic Rapture casts, shard generation

---

## Questions to Investigate

These are open questions that future sessions should explore:

1. **Combat Log Format**
   - What's the exact structure of WoW combat log events?
   - How are events timestamped?
   - What information is available?

2. **Real-Time Parsing**
   - How to tail a file being actively written?
   - Performance implications of live parsing?
   - How does WoW handle log file rotation?

3. **Warcraft Logs API**
   - How to get API credentials?
   - What queries are available?
   - Rate limits and authentication?

4. **Rotation Analysis**
   - Where to source optimal rotation priorities?
   - How to define "good" vs. "bad" play?
   - Spec-specific rules and edge cases?

5. **Dashboard Technology**
   - Best tech stack for real-time web dashboard?
   - How to minimize performance impact on WoW?
   - Desktop app vs. web app?

---

## User Expectations

### What User Wants
- Actionable performance insights
- Real-time feedback during gameplay (long-term)
- Understanding of optimal rotation and mechanics
- Progressive development from simple to complex

### What User Doesn't Want
- Historical-only analysis (this is a stepping stone)
- Dependency on soon-to-be-deprecated tools (Details)
- Over-complicated solutions when simple works
- Incomplete session documentation

### Communication Style
- Technical details are welcome
- Explain decisions and tradeoffs
- Be direct about limitations
- Focus on building toward the end goal

---

## Tips for Future Claude Sessions

1. **Always start by reviewing** the latest session log to see what was done recently

2. **Ask about new data** - User may have uploaded new combat logs or CSV exports

3. **Keep long-term goal in mind** - Real-time analysis dashboard is the target, not just reports

4. **Document everything** - Create comprehensive session logs at the end

5. **Terminal-friendly filenames** - Always use lowercase with underscores, no spaces

6. **Don't assume** - Ask for clarification when user intent is unclear

7. **Be proactive** - Suggest next steps based on project roadmap

8. **Performance matters** - We'll eventually parse logs in real-time, keep efficiency in mind

9. **Incremental progress** - Build simple first, then iterate and improve

10. **Context is king** - More documentation is better than less

---

## Quick Reference

### Character Names (Wyrmrest Accord-US)
- **Main:** Mittwoch (Warlock)
- **Alts:** Nekoken, Elehal, Kitsuneken, Kumaken, Pannonica, Kossil, Shoryuken, Kyouken, Tatsuken, Soryuken, Kekonen

### File Locations
- **Project:** `/home/rpmessner/wow_analysis/`
- **Combat Logs:** `/mnt/g/World of Warcraft/_retail_/Logs/`
- **Downloads:** `/mnt/c/Users/rpmes/Downloads/`
- **WoW Install:** `/mnt/g/World of Warcraft/_retail_/`

### Important Files
- `PROJECT_CONTEXT.md` - Core project info
- `docs/sessions/` - Session history
- `data/` - Combat data exports

### Current Status
- **Phase:** Combat Log Parser (Phase 2)
- **Parser Status:** Working Elixir implementation parsing encounters and damage
- **Next:** Add pet damage attribution, expand metrics (healing, deaths, buffs)
- **Blockers:** None currently

---

**Last Updated:** 2025-11-22
**Session Count:** 2
