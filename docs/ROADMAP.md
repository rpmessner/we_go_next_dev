# WoW Raid Diagnostic Tool - Development Roadmap

**Project:** Raid Diagnostic & Coaching Dashboard
**Target Launch:** Midnight Expansion Raids (March 2026)
**Last Updated:** 2025-11-28

---

## Vision

Build a raid leadership tool that provides:
1. **Instant between-pull analysis** - diagnosing what went wrong, ready during runback
2. **Strategy diagrams** with annotated minimaps for Discord
3. **Private coaching** reports for individual players

This is NOT a damage meter. It's a diagnostic tool for progression raiding.

### Why Between-Pull Focus (Not Live)

WoW buffers combat log writes during active combat - data can be delayed by minutes. The external log file is **not suitable for true real-time** during pulls. However:
- Log flushes immediately on `ENCOUNTER_END`
- We poll the file and detect new encounters within seconds
- Analysis is ready during runback/rebuff - when it's actually actionable
- No addon required, works with stock WoW combat logging

True live-during-combat would require a companion addon (post-MVP consideration).

---

## Timeline to Midnight

**Now:** November 2025
**Midnight Launch:** March 2, 2026
**Raid Opening:** Mid-March 2026 (typically 1-2 weeks after launch)
**Available Time:** ~3-4 months until raid opening

### Milestone Schedule

| Milestone | Target | Description |
|-----------|--------|-------------|
| **M1: Core Events** | ✅ Nov 2025 | Death tracking, damage taken analysis |
| **M2: Discovery Mode** | ✅ Nov 2025 | Surface interesting events, basic UI |
| **M3: Criteria System** | ✅ Nov 2025 | Mark/track mechanics, failure detection |
| **M4: File Watching** | ✅ Nov 2025 | Auto-refresh on encounter end |
| **M5: Analysis Reports** | ✅ Nov 2025 | Between-pull summaries, trends |
| **M6: Pre-Launch Polish** | Early Mar 2026 | Final testing, bug fixes |
| **MVP Launch** | **Mid-March 2026** | **Ready for Midnight raids Day 1** |
| **Post-MVP: Strategy Diagrams** | Q2-Q3 2026 | Minimap annotations, Discord export |
| **Post-MVP: Addon Distribution** | Q3-Q4 2026 | In-game results sharing |

---

## Phase 1: Core Event Processing

**Goal:** Extract diagnostic-relevant events from combat logs
**Target:** December 2025

### 1A: Death Analysis (Priority: CRITICAL)

The most important diagnostic: who died and why.

**Tasks:**
- [x] Parse `UNIT_DIED` events
- [x] Track last N damage events before death (death recap)
- [x] Identify killing blow (ability, source)
- [x] Calculate overkill amount
- [x] Track time of death in encounter
- [ ] Aggregate deaths per player across pulls

**Output:** "Player X died at 2:34 to [Ability] from [Source]. Took 450k damage in last 3 seconds."

### 1B: Damage Taken Tracking (Priority: HIGH)

Track what's hitting the raid.

**Tasks:**
- [ ] Parse `SPELL_DAMAGE`, `SPELL_PERIODIC_DAMAGE`, `SWING_DAMAGE`
- [ ] Track damage by ability (group similar damage)
- [ ] Track damage by target (who's taking damage)
- [ ] Identify high-damage abilities (potential mechanics)
- [ ] Calculate DTPS (damage taken per second) per player
- [ ] Flag players taking significantly more damage than others

**Output:** "[Ability X] hit 8 players for average 120k damage. Player Y took 3 hits."

### 1C: Interrupt Tracking (Priority: HIGH) ✅ COMPLETE

Critical for many mechanics.

**Tasks:**
- [x] Parse `SPELL_INTERRUPT` events
- [x] Parse `SPELL_CAST_SUCCESS` for completed enemy casts
- [x] Track successful interrupts (who interrupted what)
- [x] Detect missed interrupts (cast completed without interrupt)
- [ ] Build interrupt assignment tracking (future: who was supposed to kick)

**Output:** Shows per-player interrupt counts, per-spell interrupt rates, and missed kicks.

### 1D: Debuff Tracking (Priority: MEDIUM) ✅ COMPLETE

Many mechanics apply debuffs that need handling.

**Tasks:**
- [x] Parse `SPELL_AURA_APPLIED`, `SPELL_AURA_REMOVED`, `SPELL_AURA_APPLIED_DOSE`
- [x] Track debuff applications by player
- [x] Track debuff duration
- [x] Identify debuffs applied to multiple players (raid-wide mechanics)
- [x] Flag players with most debuff applications

**Output:** Shows top debuffs raid-wide and players with most debuff applications.

---

## Phase 2: Discovery Mode

**Goal:** Surface interesting events without predefined criteria
**Target:** January 2026

### 2A: Event Aggregation

**Tasks:**
- [ ] Group events by ability/spell ID
- [ ] Calculate frequency, total damage, affected players
- [ ] Rank abilities by "interestingness" (damage, frequency, deaths caused)
- [ ] Filter out noise (auto-attacks, minor damage)
- [ ] Present top N "notable" abilities per pull

### 2B: Basic Web Interface

**Tasks:**
- [ ] Create Phoenix application
- [ ] Simple pull selector (list encounters from log)
- [ ] Event summary view (deaths, damage sources, interrupts)
- [ ] Sortable/filterable tables
- [ ] Basic styling (TailwindCSS)

### 2C: Pull Comparison

**Tasks:**
- [ ] Compare current pull to previous attempts
- [ ] Highlight what changed (more deaths, new damage source)
- [ ] Show improvement trends (fewer failures over attempts)
- [ ] Pull timeline showing key events

---

## Phase 3: Criteria System ✅ COMPLETE

**Goal:** Allow marking abilities as tracked mechanics
**Completed:** November 2025

### 3A: Mechanic Types ✅

Defined categories for tracked abilities:

- **Avoidable Damage** - Damage that shouldn't happen (standing in fire)
- **Required Interrupt** - Casts that must be kicked
- **Soak Mechanic** - Damage that needs to be shared
- **Spread Mechanic** - Debuff requiring players to separate
- **Stack Mechanic** - Requires grouping up
- **Tank Mechanic** - Tank-specific handling
- **Healer Mechanic** - Requires healing response

### 3B: Criteria Builder UI ✅

**Tasks:**
- [x] Click ability in damage tab to create criteria
- [x] Select mechanic type from modal
- [x] Threshold configuration (hardcoded defaults, UI future)
- [ ] Add notes/description (future)
- [ ] Preview what this criteria would flag (future)

### 3C: Boss Profiles (Partial)

**Tasks:**
- [x] Criteria auto-associated with boss encounter
- [x] Criteria loaded when viewing boss encounter
- [ ] Export/import profiles (JSON) - future
- [ ] Share profiles with raid team - future

### 3D: Failure Detection ✅

**Tasks:**
- [x] Match events against active criteria
- [x] Generate failure records (who, what, when)
- [x] Aggregate failures per player and per mechanic
- [x] Display failures prominently in UI

---

## Phase 4: File Watching & Auto-Refresh

**Goal:** Automatically detect new encounters and refresh dashboard
**Target:** May 2026

**Note:** Due to WoW's combat log buffering, we cannot get true real-time data during active combat. This phase focuses on **instant detection when encounters end**.

### 4A: File Watching

**Tasks:**
- [ ] Poll combat log file for changes (every 500ms-1s)
- [ ] Detect new `ENCOUNTER_END` events
- [ ] Handle file rotation (WoW log file changes)
- [ ] Maintain read position between polls

### 4B: Auto-Refresh Dashboard

**Tasks:**
- [ ] Push new encounter to LiveView when detected
- [ ] Auto-run all analyzers on new encounter
- [ ] Update encounter list in real-time
- [ ] Show "Encounter in progress..." during combat (optional)

### 4C: Dashboard Polish

**Tasks:**
- [ ] Most recent encounter prominently displayed
- [ ] Quick navigation between pulls
- [ ] Glanceable summary (deaths, key failures)
- [ ] Sound notification when new encounter ready (optional)

---

## Phase 5: Analysis Reports

**Goal:** Between-pull summaries and coaching reports
**Target:** July 2026

### 5A: Pull Summary Report ✅ COMPLETE

**Tasks:**
- [x] Automatic generation when encounter ends
- [x] Deaths with causes
- [x] Mechanic failures ranked by impact
- [x] What killed us (if wipe)
- [x] Players needing coaching identified
- [x] Actionable recommendations generated
- [ ] Comparison to previous best attempt (future)

### 5B: Player Reports

**Tasks:**
- [ ] Per-player breakdown of their failures
- [ ] Private (not shown to raid, only to you)
- [ ] Exportable (copy/paste to Discord DM)
- [ ] Trends over multiple pulls
- [ ] Specific, actionable feedback

### 5C: Progress Tracking

**Tasks:**
- [ ] Track attempts per boss
- [ ] Best attempt progress (lowest boss %)
- [ ] Failure trends (are we improving on mechanic X?)
- [ ] Session summary (tonight's progression)

---

## Phase 6: Strategy Diagrams

**Goal:** Visual aids for raid coordination
**Target:** September 2026

### 6A: Minimap Integration

**Tasks:**
- [ ] Source datamined minimap backgrounds
- [ ] Map encounter areas to minimap coordinates
- [ ] Display minimap in web interface

### 6B: Annotation Tools

**Tasks:**
- [ ] Place markers (raid markers, custom icons)
- [ ] Draw arrows (movement paths)
- [ ] Add text labels
- [ ] Define positions (group assignments)
- [ ] Color coding by role/group

### 6C: Data Overlay

**Tasks:**
- [ ] Overlay death locations from combat data
- [ ] Show where damage events occurred
- [ ] Heat maps of problematic areas
- [ ] Movement patterns (if position data available)

### 6D: Export

**Tasks:**
- [ ] Export as PNG image
- [ ] Optimized for Discord embedding
- [ ] Include legend/key
- [ ] Batch export (multiple phases/positions)

---

## Phase 6B: Addon-Based Results Distribution (Optional)

**Goal:** Automated distribution of analysis results to raid members
**Target:** Post-MVP (Q3-Q4 2026)

### Why an Addon?

**Without addon (MVP):**
- Raid lead reads we_go_next web UI
- Manually calls out failures to raid
- Players don't see their personal stats

**With addon:**
- we_go_next writes analysis to SavedVariables
- Server operator `/reload` → addon reads results
- Addon broadcasts via addon comm to all raid members
- Each player sees personalized performance breakdown
- No verbal callouts needed

### Workflow

```
Combat Log → we_go_next analyzes → Writes WeGoNextResults.lua
                                          ↓
                        Server operator /reload in WoW
                                          ↓
                        WeGoNext addon reads SavedVariables
                                          ↓
                        Addon broadcasts via C_ChatInfo.SendAddonMessage
                                          ↓
                        All raid members' addons display results
```

### 6B.1: WoW Addon (WeGoNext)

**Tasks:**
- [ ] Create addon structure with TOC file
- [ ] Read `WeGoNextResults` SavedVariable after reload
- [ ] Broadcast results via addon communication channel (`RAID`)
- [ ] Listen for broadcasts from other addon users
- [ ] Display personalized stats to each player
- [ ] Slash commands: `/wgn show`, `/wgn share`

**SavedVariables Format:**
```lua
WeGoNextResults = {
    encounter = {id = 2887, name = "...", pull_number = 12},
    summary = {result = "WIPE", percent = 43, ...},
    players = {
        ["Mittwoch-WyrmrestAccord"] = {
            deaths = 2,
            causes = {"Diabolic Ritual", ...},
            tips = {"Move faster..."},
        },
        -- ... all raid members
    }
}
```

### 6B.2: we_go_next Integration

**Tasks:**
- [ ] Add SavedVariables writer module
- [ ] Web UI button: "Prepare Results for Sharing"
- [ ] Generate personalized coaching tips per player
- [ ] Write to WoW SavedVariables path
- [ ] Show instructions: "Run /reload then /wgn share"

**File Path:**
```
/mnt/g/World of Warcraft/_retail_/WTF/Account/{account}/SavedVariables/WeGoNext.lua
```

### 6B.3: Player UI

**In-game display options:**
- **Chat output:** Simple text summary to raid chat
- **Whispers:** Personal stats whispered to each player
- **Custom frame:** Popup window with detailed breakdown
- **Slash command:** `/wgn me` to re-view personal stats

**Example Output:**
```
╔════════════════════════════════════╗
║  Pull #12 - Plexus Sentinel       ║
║  WIPE at 43% (3:45)                ║
╠════════════════════════════════════╣
║  Your Performance:                 ║
║  ✓ Interrupts: 4/4 (100%)          ║
║  ✗ Deaths: 2 (Diabolic Ritual)     ║
║  ⚠ Avoidable Damage: 850k          ║
║                                    ║
║  Tip: Move faster out of ritual    ║
╚════════════════════════════════════╝
```

### 6B.4: MCP Usage (Development Only)

MCP server (`wow_mcp`) is used **only during addon development**:
- Deploy addon: `mix deploy_bridge --version retail`
- Test SavedVariables parsing
- Debug addon issues

**Not used during raids** - runtime workflow is:
1. we_go_next writes SavedVariables file directly
2. You `/reload`
3. Addon handles everything else

### Implementation Notes

- **Similar to Method Raid Tools:** Raid lead shares, everyone receives via addon comm
- **Opt-in:** Players without addon installed see nothing (no spam)
- **Privacy:** Only players in your raid group receive broadcasts
- **Caching:** Results cached in addon for `/wgn show` after initial broadcast

---

## Phase 7: Polish & Launch Prep

**Goal:** Production-ready for Midnight raids
**Target:** November 2026 - January 2026

### 7A: Testing with Current Content

**Tasks:**
- [ ] Test with Manaforge Omega progression
- [ ] Test with alt raids
- [ ] Validate accuracy of failure detection
- [ ] Performance testing (long raid nights)

### 7B: UX Refinement

**Tasks:**
- [ ] Dashboard layout optimization
- [ ] Keyboard shortcuts
- [ ] Mobile-friendly views (for checking between pulls)
- [ ] Customizable layouts

### 7C: Documentation

**Tasks:**
- [ ] User guide
- [ ] Boss profile sharing guide
- [ ] Troubleshooting common issues

---

## Technical Priorities

### Critical Path (Blocks Everything)
1. Death analysis - Core diagnostic ✅
2. File watching - Enables auto-refresh on encounter end ✅
3. Criteria system - Enables meaningful tracking ✅

### High Value (Core Features)
4. Damage taken tracking ✅
5. Interrupt tracking ✅
6. Between-pull dashboard ✅
7. Pull summaries ✅

### Medium Value (Full Experience)
8. Debuff tracking ✅
9. Strategy diagrams
10. Progress tracking
11. Player reports

### Nice to Have (Polish)
12. Sound alerts
13. Mobile views
14. Profile sharing
15. Heat maps

---

## Success Criteria

### MVP (Midnight Launch)
- [x] File watching detects encounter end within seconds
- [x] Deaths and failures displayed immediately after pull
- [x] Criteria system working (mark abilities to track)
- [x] Failures shown on dashboard
- [x] Between-pull summary generated automatically
- [ ] Stable for 3+ hour raid nights

### Full Product
- [ ] Strategy diagrams with minimap
- [ ] Player coaching reports
- [ ] Progress tracking across sessions
- [ ] Boss profile library
- [ ] Polished, professional UI

---

## PRIME DIRECTIVE

**MVP MUST launch with Midnight raids (late Jan - March 2026).**

### Scope Cuts if Behind Schedule

If we're falling behind, cut in this order:

1. **Phase 6 (Strategy Diagrams)** - Nice to have, not essential
2. **Phase 7 (Polish)** - Ship rough, fix later
3. **Phase 5C (Progress Tracking)** - Manual tracking is fine
4. **Phase 3B (Criteria Builder UI)** - Hardcode common mechanics instead
5. **Phase 5B (Player Reports)** - Just raid lead view first

### Non-Negotiable for MVP

These MUST work for launch:
- [x] Death tracking with cause (Phase 1A) ✅
- [x] File watching with encounter detection (Phase 4A) ✅
- [x] Dashboard showing deaths/failures after pull ends (Phase 4C) ✅
- [x] Basic criteria matching (Phase 3D) ✅
- [x] Between-pull summary (Phase 5A) ✅

**All non-negotiable MVP features are complete!**

Everything else can come in patches after launch.

**Post-Midnight:** Once we ship for Midnight, deadline pressure relaxes. We can take time for polish, new features, and proper iteration without a hard target.

---

## Notes

- **Iteration over perfection**: Ship working features, refine based on actual raid use
- **Current content testing**: Use ongoing Manaforge Omega progression to validate
- **Private by default**: Tool is for raid leaders, not public shaming
- **Build during progression**: Best tested when we're actually struggling with content
- **Launch date is sacred**: Cut scope, not the deadline

---

## Archived: Previous Roadmap

The previous roadmap (focused on personal DPS and spec-specific rotation analysis) has been superseded by this raid diagnostic focus. Key concepts like normalizer pipelines and event processing remain relevant but are now in service of mechanic detection rather than rotation optimization.

See `docs/sessions/2025-11-23_wowanalyzer_research.md` for the previous direction.
