# Session: 2025-11-21 - Initial Project Setup

**Date:** November 21, 2025
**Session Type:** Project Initialization
**Duration:** ~1 hour

---

## Session Overview

Initial setup of the WoW Performance Analysis project. Established project structure, documented long-term vision, organized existing data exports, and created templates for performance analysis.

---

## Accomplishments

### 1. Project Context Established

Created `PROJECT_CONTEXT.md` with:
- Project purpose and long-term vision
- Character roster (all on Wyrmrest Accord-US)
  - Main: Mittwoch (Warlock)
  - 11 alts across all classes
- Guild: Hand of Algalon
- Data sources and workflow

### 2. Long-Term Vision Defined

**Ultimate Goal:** Real-time combat analysis dashboard that runs in a web browser alongside WoW client

**Approach:**
- Parse WoW's CombatLog.txt in real-time as it's being written
- Provide live performance feedback, rotation optimization, and mechanic warnings
- Display metrics and actionable suggestions during encounters

**Development Phases:**
1. Current: Historical analysis using Warcraft Logs CSV exports
2. Next: Combat log parser development
3. Future: Analysis engine and web dashboard
4. Final: Real-time optimization alerts

### 3. Data Sources Identified

#### Primary Source (Current & Future)
- **WoW Combat Log**: `/mnt/g/World of Warcraft/_retail_/Logs/`
  - User has enabled combat logging in WoW client
  - CombatLog.txt written in real-time during gameplay
  - This will be the source of truth for real-time analysis

#### Historical Analysis Sources
- **Warcraft Logs CSV Exports**: Downloaded from warcraftlogs.com
  - Manual exports for specific boss encounters
  - Include damage done, damage taken, casts, summons, etc.

#### Future Integration
- **Warcraft Logs API**: GraphQL API (v2)
  - Documentation: https://www.warcraftlogs.com/api/docs
  - Requires OAuth client credentials
  - Note: Web scraping blocked with 403 errors

#### Deprecated/Ignored
- **Details Addon**: NOT being tracked
  - Addon is being deprecated by Blizzard soon
  - Will be replaced by WoW's built-in damage meter (which doesn't save logs)
  - Not worth investing time in parsing Details SavedVariables

### 4. Project Structure Created

```
wow_analysis/
├── data/                                    # Warcraft Logs CSV exports
│   ├── guild_reports.csv                   # List of all guild raid reports
│   ├── naazindhri_mythic/                  # Per-boss encounter folders
│   │   ├── mittwoch_casts.csv
│   │   ├── mittwoch_damage_done.csv
│   │   ├── mittwoch_damage_taken.csv
│   │   ├── mittwoch_summons.csv
│   │   └── raid_damage_done.csv
│   └── plexus_sentinel_mythic/
│       └── mittwoch_damage_done.csv
├── docs/
│   └── sessions/                            # Session logs (immutable)
│       └── 2025-11-21_initial_setup.md     # This file
├── PROJECT_CONTEXT.md                       # Project documentation
└── weekly_performance_review.md             # Sample performance review
```

**File Naming Convention:**
- All lowercase with underscores (terminal-friendly, tab-completable)
- No spaces in filenames
- Boss encounters get their own folders under `data/`

### 5. Data Exports Organized

Moved CSV files from Windows Downloads folder to project structure:
- Source: `/mnt/c/Users/rpmes/Downloads/*.csv`
- Destination: `/home/rpmessner/wow_analysis/data/`
- Organized by boss encounter in subdirectories

### 6. Performance Review Template Created

Created `weekly_performance_review.md` as initial template showing:
- Raid activity summary
- Boss-by-boss performance breakdown
- Spec comparison (Demonology vs Affliction)
- Guild raid schedule
- Goals tracking section

**Note:** Template needs user feedback and customization before finalizing

---

## Key Decisions Made

### 1. Real-Time Analysis as Primary Goal
- Project will ultimately focus on real-time combat log parsing
- Historical analysis is a stepping stone to understand data structures
- Web dashboard will run alongside WoW client for live feedback

### 2. Combat Log as Source of Truth
- WoW's native CombatLog.txt is the primary data source
- All other sources (Warcraft Logs, Details) are secondary
- User has enabled combat logging for all future gameplay

### 3. Ignore Details Addon
- Details is being deprecated by Blizzard
- Not worth parsing Details SavedVariables
- Focus on WoW's native combat log instead

### 4. Immutable Session Logs
- All sessions documented in `docs/sessions/`
- Session logs are backward-facing, immutable records
- Each session gets dated filename: `YYYY-MM-DD_description.md`

### 5. Terminal-Friendly Naming
- All files use lowercase with underscores
- No spaces in any filenames
- Easy to tab-complete in terminal

---

## Data Analysis Findings

### CSV Export Types Available

From Warcraft Logs, we can export:
1. **Damage Done** - Ability-by-ability damage breakdown
   - Shows damage amounts, casts, hits, crit %, DPS
   - Includes pet damage breakdown
2. **Damage Taken** - Incoming damage sources
3. **Casts** - Spell cast counts and timing
4. **Summons** - Pet/summon activity
5. **Guild Reports** - List of all uploaded raid logs

### Current Data Limitations

What's **NOT** in the CSV exports:
- Parse percentiles/rankings (need to query API or scrape differently)
- Death counts and causes
- Mechanic execution tracking
- Fight duration and encounter context
- Item level and gear information

### Sample Performance Data

**Soulbinder Naazindhri (Mythic) - Demonology:**
- DPS: 1,861,289
- Top damage source: Diabolic Ritual (26.47%)
- Strong pet damage contribution

**Plexus Sentinel (Mythic) - Affliction:**
- DPS: 1,252,637
- Top damage source: Wither (28.44%)
- Near-perfect DoT uptime (99%+)

---

## Technical Discoveries

### WoW Installation Location
- Path: `/mnt/g/World of Warcraft/`
- Retail installation: `/mnt/g/World of Warcraft/_retail_/`
- Combat logs: `/mnt/g/World of Warcraft/_retail_/Logs/`
- SavedVariables: `/mnt/g/World of Warcraft/_retail_/WTF/Account/THEUGLYCANADIAN/Wyrmrest Accord/[Character]/SavedVariables/`

### Warcraft Logs API
- Uses GraphQL (v2)
- Public endpoint: `https://www.warcraftlogs.com/api/v2/client`
- Requires OAuth client credentials (client_id, client_secret)
- Direct web scraping blocked with 403 errors

### Environment
- OS: WSL2 (Windows Subsystem for Linux)
- Project directory: `/home/rpmessner/wow_analysis/`
- WoW on Windows: `/mnt/g/World of Warcraft/`
- Downloads folder: `/mnt/c/Users/rpmes/Downloads/`

---

## Character Information

### Main Character
- **Name:** Mittwoch
- **Class:** Warlock
- **Realm:** Wyrmrest Accord (US)
- **Guild:** Hand of Algalon
- **Specs Played:** Demonology, Affliction

### Alt Roster (All on Wyrmrest Accord-US)
1. Nekoken - Druid
2. Elehal - Mage
3. Kitsuneken - Death Knight
4. Kumaken - Shaman
5. Pannonica - Demon Hunter
6. Kossil - Priest
7. Shoryuken - Monk
8. Kyouken - Rogue
9. Tatsuken - Warrior
10. Soryuken - Evoker
11. Kekonen - Paladin

### Guild Info
- **Name:** Hand of Algalon
- **Raid Schedule:** Appears to be Thursday/Friday nights
- **Current Content:** Mythic Manaforge Omega (11.0.7 PTR content)
- **Recent Activity:** Nov 21, 15, 14, 7, 1 (2025)

---

## Questions Raised / To Investigate

1. **Warcraft Logs API Access**
   - How to obtain client_id and client_secret?
   - What data can we query via GraphQL?
   - Rate limits and authentication flow?

2. **Combat Log Format**
   - What's the structure of CombatLog.txt?
   - How to parse combat events in real-time?
   - What information is available vs. what Warcraft Logs adds?

3. **Real-Time Parsing**
   - How to tail/watch a file that's being written?
   - How to handle file rotation (WoW might create new log files)?
   - Performance considerations for live parsing?

4. **Analysis Engine**
   - What constitutes "optimal" play for each spec?
   - Where to source rotation priorities and guidelines?
   - How to detect mechanic failures vs. intentional actions?

5. **Web Dashboard**
   - Tech stack for real-time web dashboard?
   - WebSocket vs. polling for live updates?
   - How to run alongside WoW without performance impact?

---

## Next Steps

### Immediate (Next Session)
1. **Finalize Performance Review Template**
   - Get user feedback on current template
   - Adjust sections, metrics, and format
   - Create reusable template file

2. **Examine Combat Log**
   - Read actual CombatLog.txt file
   - Understand event format and structure
   - Document combat log specification

3. **Parse CSV Data**
   - Write scripts to read and analyze CSV exports
   - Generate performance insights programmatically
   - Test with current data exports

### Short Term (Next Few Sessions)
1. Build combat log parser prototype
2. Research Warcraft Logs API authentication
3. Define spec-specific rotation analysis rules
4. Set up basic data analysis pipeline

### Long Term (Project Goals)
1. Real-time combat log parsing
2. Rotation optimization engine
3. Web-based live dashboard
4. Mechanic tracking and alerts

---

## Files Created This Session

1. `/home/rpmessner/wow_analysis/PROJECT_CONTEXT.md`
2. `/home/rpmessner/wow_analysis/weekly_performance_review.md`
3. `/home/rpmessner/wow_analysis/data/guild_reports.csv`
4. `/home/rpmessner/wow_analysis/data/naazindhri_mythic/*`
5. `/home/rpmessner/wow_analysis/data/plexus_sentinel_mythic/*`
6. `/home/rpmessner/wow_analysis/docs/sessions/2025-11-21_initial_setup.md` (this file)

---

## Important Context for Future Sessions

### What Claude Should Know
1. **Long-term goal is real-time analysis**, not just historical reports
2. **Combat log is source of truth**, not Details addon
3. **Details addon is deprecated**, don't invest time in it
4. **Session logs are immutable** - create new files, don't edit old ones
5. **User wants terminal-friendly filenames** - no spaces, lowercase with underscores
6. **Current tier**: Mythic Manaforge Omega (appears to be 11.0.7 PTR content)
7. **Main character**: Mittwoch (Warlock) on Wyrmrest Accord-US
8. **Guild**: Hand of Algalon
9. **Technology stack**: Elixir for entire project (user knows Elixir really well, doesn't know Python much)

### What User Expects
- Actionable performance insights
- Help building toward real-time analysis tool
- Understanding of WoW combat mechanics and optimization
- Progressive development from simple (CSV analysis) to complex (real-time dashboard)

### Technical Environment
- WSL2 Linux environment
- WoW installed on Windows at `/mnt/g/World of Warcraft/`
- Project at `/home/rpmessner/wow_analysis/`
- Combat logging enabled in WoW client

---

## Session Notes

### User Preferences
- Wants terminal-friendly filenames (implemented)
- Wants immutable session logs for historical reference (this document)
- Interested in real-time analysis, not just post-raid review
- Comfortable with technical implementation details

### Challenges Encountered
1. Warcraft Logs blocks web scraping (403 errors)
2. CSV exports don't include parse percentiles
3. Details addon being deprecated by Blizzard
4. Need to understand combat log format for parsing

### Wins
- Clear project vision established
- Data sources identified and organized
- Initial performance analysis completed
- Foundation for future development laid

---

## End of Session

**Status:** Project initialized and ready for development
**Next Session Focus:** Examine combat log format and finalize performance review template
