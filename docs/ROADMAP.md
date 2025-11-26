# WoW Raid Diagnostic Tool - Development Roadmap

**Project:** Raid Diagnostic & Coaching Dashboard
**Target Launch:** Midnight Expansion Raids (Late Jan - March 2026)
**Last Updated:** 2025-11-24

---

## Vision

Build a raid leadership tool that provides:
1. **Live dashboard** during pulls showing mechanic failures and deaths
2. **Between-pull analysis** diagnosing what went wrong
3. **Strategy diagrams** with annotated minimaps for Discord
4. **Private coaching** reports for individual players

This is NOT a damage meter. It's a diagnostic tool for progression raiding.

---

## Timeline to Midnight

**Now:** November 2025
**Target:** Late January - March 2026 (Midnight launch)
**Available Time:** ~12-14 months

### Milestone Schedule

| Milestone | Target | Description |
|-----------|--------|-------------|
| **M1: Core Events** | Dec 2025 | Death tracking, damage taken analysis |
| **M2: Discovery Mode** | Jan 2026 | Surface interesting events, basic UI |
| **M3: Criteria System** | Mar 2026 | Mark/track mechanics, boss profiles |
| **M4: Live Dashboard** | May 2026 | Real-time file watching, live updates |
| **M5: Analysis Reports** | Jul 2026 | Between-pull summaries, trends |
| **M6: Strategy Diagrams** | Sep 2026 | Minimap annotations, Discord export |
| **M7: Polish & Testing** | Nov 2026 | Testing with current content, refinement |
| **MVP Launch** | Jan 2026 | Ready for Midnight Day 1 |

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

## Phase 3: Criteria System

**Goal:** Allow marking abilities as tracked mechanics
**Target:** March 2026

### 3A: Mechanic Types

Define categories for tracked abilities:

- **Avoidable Damage** - Damage that shouldn't happen (standing in fire)
- **Required Interrupt** - Casts that must be kicked
- **Soak Mechanic** - Damage that needs to be shared
- **Spread Mechanic** - Debuff requiring players to separate
- **Stack Mechanic** - Requires grouping up
- **Tank Mechanic** - Tank-specific handling
- **Healer Mechanic** - Requires healing response

### 3B: Criteria Builder UI

**Tasks:**
- [ ] Click ability in discovery mode to create criteria
- [ ] Select mechanic type from dropdown
- [ ] Set threshold (e.g., "more than 2 hits = failure")
- [ ] Add notes/description
- [ ] Preview what this criteria would flag in current pull

### 3C: Boss Profiles

**Tasks:**
- [ ] Save criteria as boss profile (boss name + all criteria)
- [ ] Load profile when boss detected in log
- [ ] Export/import profiles (JSON)
- [ ] Share profiles with raid team

### 3D: Failure Detection

**Tasks:**
- [ ] Match events against active criteria
- [ ] Generate failure records (who, what, when)
- [ ] Aggregate failures per player
- [ ] Prioritize by severity (death-causing vs minor)

---

## Phase 4: Live Dashboard

**Goal:** Real-time display during pulls
**Target:** May 2026

### 4A: File Watching

**Tasks:**
- [ ] Watch combat log file for changes
- [ ] Stream new lines as they're written
- [ ] Handle file rotation (WoW log file changes)
- [ ] Maintain position between reads

### 4B: Real-Time Processing

**Tasks:**
- [ ] Process events as they arrive
- [ ] Update encounter state incrementally
- [ ] Detect encounter start/end boundaries
- [ ] Minimal latency (<500ms event to display)

### 4C: Live Dashboard View

**Tasks:**
- [ ] Current encounter status (in combat, duration)
- [ ] Death feed (live list of deaths as they happen)
- [ ] Mechanic failure feed (criteria violations)
- [ ] Current raid health summary
- [ ] Glanceable design (scannable at a glance)

### 4D: Alerts

**Tasks:**
- [ ] Visual alerts for critical failures
- [ ] Configurable alert types
- [ ] Sound notifications (optional)
- [ ] Alert history (what happened last 30 seconds)

---

## Phase 5: Analysis Reports

**Goal:** Between-pull summaries and coaching reports
**Target:** July 2026

### 5A: Pull Summary Report

**Tasks:**
- [ ] Automatic generation when encounter ends
- [ ] Deaths with causes
- [ ] Mechanic failures ranked by impact
- [ ] What killed us (if wipe)
- [ ] Comparison to previous best attempt

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
1. Death analysis - Core diagnostic
2. File watching - Enables real-time
3. Criteria system - Enables meaningful tracking

### High Value (Core Features)
4. Damage taken tracking
5. Interrupt tracking
6. Live dashboard
7. Pull summaries

### Medium Value (Full Experience)
8. Debuff tracking
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
- [ ] Can watch combat log in real-time
- [ ] Deaths displayed as they happen
- [ ] Criteria system working (mark abilities to track)
- [ ] Failures shown on dashboard
- [ ] Between-pull summary generated
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
- [ ] Real-time file watching (Phase 4A)
- [ ] Death tracking with cause (Phase 1A)
- [ ] Live dashboard showing deaths/failures (Phase 4C)
- [ ] Basic criteria matching (Phase 3D, even if hardcoded)
- [ ] Between-pull summary (Phase 5A)

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
