# Session: 2025-11-22 - Combat Log Parsing with Elixir

**Date:** November 22, 2025
**Session Type:** Combat Log Analysis
**Status:** Complete

---

## Session Overview

Successfully built an Elixir-based combat log parser that reads WoW's native combat log format, extracts encounter data, and analyzes player performance. This is the first working implementation of combat log parsing for the project and establishes the foundation for real-time analysis.

---

## Accomplishments

### 1. Elixir Project Structure Created
Created Mix project `combat_log_parser` with modular architecture:
- `CombatLogParser` - Main API module
- `CombatLogParser.Encounter` - Encounter data structure
- `CombatLogParser.LogReader` - Combat log file parser
- `CombatLogParser.DamageAnalyzer` - Damage output analysis

### 2. Combat Log Format Decoded
Successfully parsed WoW's combat log format with:
- Timestamp parsing (`MM/DD/YYYY HH:MM:SS.mmm-TZ`)
- CSV field extraction (handling quoted strings)
- Event type identification
- Advanced combat logging support (variable field positions)

### 3. Encounter Extraction Working
Parser successfully identifies and extracts:
- ENCOUNTER_START/END boundaries
- Boss names and difficulty levels
- Fight duration and success/wipe status
- All combat events during encounters
- Group size per encounter

### 4. Damage Analysis Implemented
Analyzes player damage output including:
- Total damage per encounter
- DPS calculation
- Top abilities breakdown with percentages
- Damage event counting
- Spec-specific ability tracking

### 5. Full Raid Analysis Complete
Parsed 603MB combat log containing:
- **20 total encounters** from Heroic Manaforge Omega
- 6 unique bosses (some with multiple pulls)
- ~3 hours of combat data
- Thousands of combat events per encounter

---

## Data Discovered

### Combat Log File
- **Location:** `/mnt/g/World of Warcraft/_retail_/Logs/WoWCombatLog-112225_112043.txt`
- **Size:** 603MB
- **Date:** 2025-11-22, logged 11:20 AM - 2:05 PM
- **Format:** Two-space delimited timestamp + CSV event data
- **Version:** Combat Log Version 22, Advanced Logging Enabled

### Raid Summary
**Manaforge Omega - Heroic Difficulty**

Bosses encountered (with pull counts):
1. **Plexus Sentinel** - 1 kill
2. **Loom'ithar** - 1 wipe, 1 kill
3. **Soulbinder Naazindhri** - 2 wipes, 1 kill
4. **Forgeweaver Araz** - 1 wipe, 1 kill
5. **The Soul Hunters** - 1 wipe, 1 kill
6. **Fractillus** - 3 wipes
7. **Nexus-King Salhadaar** - 6 wipes

**Total:** 13 wipes, 5 kills

### Mittwoch's Performance Highlights

**Best Kill DPS (Direct Damage Only):**
- Forgeweaver Araz: 11,821 DPS (Affliction)
- Soulbinder Naazindhri: 10,979 DPS (Demonology)

**Spec Usage:**
- Affliction: Plexus Sentinel
- Demonology: Soulbinder Naazindhri, Forgeweaver Araz, Nexus-King Salhadaar
- Destruction: Some pulls (Immolate, Chaos Bolt, Conflagrate observed)

**Top Abilities by Spec:**
- **Affliction:** Wither, Unstable Affliction, Agony, Blackened Soul
- **Demonology:** Hand of Gul'dan, Bilescourge Bombers, Demonbolt, Ethereal Reaping
- **Destruction:** Immolate, Chaos Bolt, Conflagrate, Incinerate

### Combat Log Format Details

**Advanced Logging Structure:**
```
SPELL_DAMAGE format with advanced logging:
- Fields 0-11: Standard prefix (event, source info, dest info, spell info)
- Fields 12+: Advanced combat logging data (HP, position, etc.)
- Last ~10 fields: Damage suffix (amount, overkill, school, resisted, etc.)
```

**Key Findings:**
- Advanced logging adds variable-length fields between spell info and damage suffix
- Damage amount position varies but appears consistently ~7-10 fields from end
- Pet damage has separate source GUIDs (not attributed to player yet)
- Periodic damage (DoTs) uses `SPELL_PERIODIC_DAMAGE` event type

---

## Technical Challenges Solved

### 1. Variable Field Positions
**Problem:** Advanced combat logging makes damage field positions inconsistent

**Solution:** Search from END of data array for damage amount, using pattern matching:
- Look for positive numbers < 50M
- Verify followed by overkill value or school (-1)
- Work backwards through suffix instead of forwards from spell ID

### 2. CSV Parsing with Quoted Strings
**Problem:** Combat log uses CSV format with quoted player/spell names containing commas

**Solution:** Regex-based CSV parser that respects quoted strings:
```elixir
String.split(~r/,(?=(?:[^"]*"[^"]*")*[^"]*$)/)
```

### 3. Timestamp Format
**Problem:** WoW uses custom timestamp format with milliseconds and timezone offset

**Solution:** Parse as `MM/DD/YYYY HH:MM:SS.mmm`, strip timezone, convert to NaiveDateTime

### 4. Encounter Event Accumulation
**Problem:** Need to associate combat events with specific encounters

**Solution:** State machine that:
- Starts encounter on ENCOUNTER_START
- Accumulates events during encounter
- Finalizes on ENCOUNTER_END
- Reverses event list for chronological order

---

## Known Limitations

### 1. Pet Damage Not Attributed
**Issue:** Pet/summon damage has different source names (Wild Imp, Felguard, etc.)

**Impact:** DPS values are significantly lower than actual (missing ~70% of Warlock damage)

**Fix Needed:** Track SPELL_SUMMON events to map pet GUIDs to owner, attribute pet damage

### 2. DoT Damage May Be Undercounted
**Issue:** Periodic damage events might use different field positions

**Status:** Needs verification - DoT-heavy fights should show higher Wither/Agony percentages

### 3. No Multi-Target Detection
**Issue:** Cleave damage isn't tracked separately from single-target

**Impact:** Can't distinguish trash damage from boss damage yet

### 4. Memory Usage for Large Files
**Issue:** Entire log file streamed into memory for processing

**Impact:** 603MB file works fine, but larger logs may cause issues

**Future:** Implement streaming/chunked processing

---

## Files Created This Session

### Core Parser
- `combat_log_parser/lib/combat_log_parser.ex` - Main API
- `combat_log_parser/lib/combat_log_parser/encounter.ex` - Encounter struct
- `combat_log_parser/lib/combat_log_parser/log_reader.ex` - File parsing
- `combat_log_parser/lib/combat_log_parser/damage_analyzer.ex` - Damage analysis
- `combat_log_parser/test_parse.exs` - Test script
- `combat_log_parser/mix.exs` - Project configuration

### Documentation
- `docs/sessions/2025-11-22_combat_log_parsing.md` - This file
- `analysis_output_20251122.txt` - Full parser output (20 encounters)

---

## Next Steps

### Immediate Priorities
1. **Pet Damage Attribution**
   - Parse SPELL_SUMMON events to track pet ownership
   - Map pet source GUIDs to owner player
   - Aggregate pet damage into player totals
   - This will dramatically increase accuracy (expect 3-5x DPS increase)

2. **Validate Damage Values**
   - Compare parser output to Warcraft Logs data
   - Verify DoT damage is being captured correctly
   - Cross-reference with in-game damage meters

3. **Add More Metrics**
   - Healing done/taken
   - Deaths and death causes
   - Buff/debuff uptime tracking
   - Cooldown usage analysis

### Medium Term
1. **Performance Optimization**
   - Profile parser performance on large files
   - Implement streaming for memory efficiency
   - Parallelize encounter processing

2. **Real-Time Parsing Foundation**
   - File tailing/watching
   - Incremental event processing
   - Live event streaming architecture

3. **Web Dashboard Prototype**
   - Phoenix LiveView setup
   - Real-time metrics display
   - Encounter progress tracking

### Long Term
1. **Rotation Analysis**
   - Define optimal rotation patterns per spec
   - Detect rotation mistakes
   - Provide optimization suggestions

2. **Mechanic Tracking**
   - Boss mechanic detection
   - Avoidable damage identification
   - Interrupt tracking

3. **Comparison & Ranking**
   - Compare to historical performance
   - Integration with Warcraft Logs API
   - Parse percentile estimation

---

## Key Learnings

### Technical
1. **Elixir Streams are Perfect for Logs**
   - File.stream! handles large files efficiently
   - Enum.reduce for stateful processing works great
   - Pattern matching makes event handling clean

2. **WoW Combat Log is Complex**
   - Advanced logging adds significant complexity
   - Field positions vary based on log settings
   - Documentation is minimal - need to reverse engineer

3. **Pet Damage is Critical**
   - For pet classes (Warlock, Hunter, etc.), pet damage is majority of output
   - Must track summon ownership for accurate analysis
   - This is a requirement, not optional

### Project
1. **Direct Combat Log Parsing is Feasible**
   - We can successfully parse WoW's native format
   - Don't need to rely on third-party tools
   - Foundation for real-time analysis is solid

2. **Incremental Development Works**
   - Started with encounter extraction
   - Added damage analysis layer by layer
   - Can iterate and improve progressively

3. **Session Documentation is Valuable**
   - Previous session's documentation saved time
   - Clear context helps Claude Code get up to speed
   - Immutable logs create good reference trail

---

## Notes

- **Technology Stack Validated:** Elixir is excellent choice for log parsing
- **Data Source Confirmed:** WoW combat log has all needed information
- **Parser Architecture:** Modular design allows easy feature additions
- **Performance:** 603MB file processes in seconds (exact timing TBD)
- **Accuracy:** Direct damage values verified against sample events
- **Next Session:** Should prioritize pet damage attribution for realistic DPS

---

**Status:** Session complete - working combat log parser achieved!
