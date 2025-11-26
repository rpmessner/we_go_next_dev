# Session: Raid Diagnostic Tool Pivot

**Date:** 2025-11-24
**Focus:** Project direction pivot from personal DPS analysis to raid-wide diagnostic and coaching tool

---

## Summary

Major pivot in project direction. The tool is no longer about "how am I doing" personal DPS analysis. Instead, it's becoming a **raid leadership diagnostic and coaching tool** focused on:

1. **Real-time dashboard during pulls** - Glanceable status of mechanic failures, deaths, and danger indicators
2. **Between-pull analysis reports** - What went wrong, who needs to adjust, are we improving
3. **Iterative boss criteria building** - Learn what to track as progression reveals problem areas
4. **Strategy diagram generation** - Annotated minimap images for Discord coordination

---

## Key Decisions

### Shift from Personal to Raid-Wide Focus

| Old Direction | New Direction |
|--------------|---------------|
| Personal DPS analysis | Raid-wide diagnostics |
| "How am I doing?" | "How are we doing?" |
| Performance metrics | Mechanic failures |
| Historical analysis | Real-time + between-pull |
| Post-raid reports | Live dashboard |

### Three Output Modes

1. **During Pull (Live Dashboard)**
   - Who's dead and why
   - Mechanic failures as they happen
   - Current danger indicators (low healers, debuff stacks)
   - Glanceable - usable while raid leading

2. **Between Pulls (Analysis Report)**
   - What killed us / why we wiped
   - Per-player mechanic failures with timestamps
   - Comparison to previous attempts
   - Actionable items for next pull

3. **Strategy Communication (Discord)**
   - Annotated minimap diagrams showing positions/movements
   - Shareable images for async coordination
   - Can be informed by actual combat data (where deaths occurred)

### Iterative Criteria Building

Since you can't predict what mechanics will cause problems during progression:

1. Start with zero boss-specific config
2. Surface "interesting events" - deaths, big damage, frequent debuffs
3. Notice patterns ("people keep dying to X ability")
4. Mark abilities as "track this" with a type (avoidable, interrupt, soak)
5. Next pull, dashboard highlights that specific mechanic
6. Build up boss profile as you learn the fight
7. Save/export profiles for future raid nights

### Private Coaching Focus

Goal is to help players improve without public callouts:
- Generate individual reports to share privately
- "Here's what you specifically need to work on"
- Training tool, not a blame tool

---

## Combat Log Events to Track

The combat log contains all the data needed for this diagnostic approach:

- **SPELL_DAMAGE** - Avoidable damage (standing in bad)
- **SPELL_INTERRUPT** - Interrupt assignments (and missed interrupts)
- **SPELL_AURA_APPLIED** - Debuffs that shouldn't happen
- **UNIT_DIED** - Deaths with cause analysis
- **Target selection patterns** - Wrong target focus

---

## Technical Implications

### What Changes

- **Primary focus:** Mechanic failures over DPS numbers
- **Output:** Real-time dashboard + between-pull reports + strategy diagrams
- **Boss configuration:** Dynamic, built up during progression
- **User interaction:** Criteria builder for flagging important mechanics

### What Stays the Same

- **Parser foundation:** Elixir combat log parser still core
- **Phoenix LiveView:** Still the right choice for real-time dashboard
- **Event processing:** Normalizer pipeline still valuable
- **Tech stack:** Elixir/Phoenix/OTP remains ideal

### New Components Needed

1. **Criteria Builder** - UI to mark abilities as trackable
2. **Boss Profile System** - Save/load mechanic definitions per boss
3. **Failure Detection** - Match events against criteria
4. **Report Generator** - Between-pull analysis summaries
5. **Diagram Builder** - Annotate minimap backgrounds
6. **Discord Export** - Generate shareable images

---

## Strategy Diagrams

- Use actual arena minimap backgrounds (datamined from game)
- Similar to Method Dungeon Tools and guide makers
- Annotate with positions, movements, assignments
- Can overlay actual combat data (death locations, etc.)
- Export as PNG for Discord sharing

---

## Next Steps

See `docs/HANDOFF.md` for detailed implementation plan.

Priority order:
1. Update project documentation to reflect new direction
2. Refocus Phase 1 on mechanic/failure detection (not pet DPS)
3. Add boss profile/criteria system to roadmap
4. Design discovery mode for surfacing notable events
5. Plan strategy diagram system

---

## WoW Addon Integration

Future addon location: `~/dev/wow-addons/`

### Report Tiers (To Design)
1. **Raid Leader Report** - Full details, private
2. **Raid Report** - Aggregate stats safe to share
3. **Personalized Reports** - Individual player feedback (future)

Per-boss configuration will determine what's exposed at each tier.

### Communication Methods to Explore
1. **File-based + UI reload** - Simple, write to SavedVariables, `/reload` to read
2. **SavedVariables polling** - Addon checks file periodically
3. **WeakAuras custom text** - Encode data, WA displays it
4. **External HTTP** - Like TSM uses, requires library
5. **Addon channel messages** - Native but size-limited

Start simple (file-based), optimize later if latency matters.

---

## Questions Deferred

- Exact dashboard layout (will emerge from usage)
- How much automation vs manual criteria building
- Integration with existing WoW addons (DBM timers, etc.)
- Multi-raid support (different raids progressing different bosses)
- Addon communication method (file vs HTTP vs channel)

---

## Session Artifacts

- Updated `CLAUDE.md` with new project direction
- New `docs/ROADMAP.md` reflecting raid diagnostic focus
- Updated `docs/TECHNICAL_ARCHITECTURE.md` with new components
- Created `docs/HANDOFF.md` with next steps for implementation
