# Session: Criteria System Implementation (Phase 3)
**Date:** 2025-11-27
**Focus:** Implement mechanic criteria tracking and failure detection

## Overview
Implemented Phase 3 (Criteria System) from the roadmap. The tool can now track specific mechanics as "avoidable damage", "must interrupt", etc., and automatically flag player failures.

## What Was Built

### 1. Database Schema
**File:** `priv/repo/migrations/20251127000001_create_mechanic_criteria.exs`

New `mechanic_criteria` table with:
- `spell_id` - The WoW spell/ability ID
- `spell_name` - Human-readable name
- `mechanic_type` - Classification (avoidable, interrupt, soak, spread, etc.)
- `boss_encounter_id` / `boss_name` - Optional boss-specific criteria
- `threshold` - JSON configuration for failure detection
- `notes` - Coaching notes
- `active` - Whether criteria is currently being tracked

Indexes on `spell_id` and `boss_encounter_id` for fast lookups.

### 2. Ecto Schema
**File:** `lib/we_go_next/criteria/mechanic_criteria.ex`

MechanicCriteria schema with:
- Changesets for validation
- Helper functions for type labels and colors
- `check_failure/2` for failure detection logic

### 3. Criteria Context
**File:** `lib/we_go_next/criteria.ex`

CRUD operations:
- `list_criteria/0`, `list_criteria_for_boss/1`
- `create_criteria/1`, `update_criteria/2`, `delete_criteria/1`
- `get_criteria_for_spell/2`
- `criteria_by_spell_id/1` - Returns map for quick lookup during analysis

### 4. Failure Analyzer
**File:** `lib/we_go_next/analyzers/failure_analyzer.ex`

New analyzer that:
- Loads active criteria for the boss
- Checks avoidable damage against DamageTakenAnalyzer output
- Checks missed interrupts against InterruptAnalyzer output
- Returns failures grouped by player and mechanic
- Provides summary statistics

### 5. UI Updates
**File:** `lib/we_go_next_web/live/encounter_live/show.ex`

Major UI enhancements:
- **New "Failures" tab** - First tab, highlighted in red when failures exist
- **Quick stats** - Shows failure count with visual highlighting
- **Track column** in Damage Taken table - "+Track" button for each ability
- **Modal** for selecting mechanic type when tracking
- **Criteria display** - Tracked abilities show color and type label

### UI Flow

1. **Navigate to encounter detail**
2. **Go to "Damage Taken" tab**
3. **Click "+ Track" on any ability**
4. **Select mechanic type** (Avoidable, Must Interrupt, etc.)
5. **Criteria is saved** and ability shows colored label
6. **Go to "Failures" tab** to see who failed the mechanic

## Mechanic Types

| Type | Description | Failure Condition |
|------|-------------|-------------------|
| `avoidable` | Damage to avoid (fire, cleaves) | Any hit on non-tank |
| `interrupt` | Cast that must be kicked | Cast completed |
| `soak` | Shared damage mechanic | Future: too few soakers |
| `spread` | Players must spread | Future: multiple hits |

## Technical Details

### Failure Detection

For **avoidable** damage:
1. Get damage stats from DamageTakenAnalyzer
2. For each non-tank player, check if they took damage from tracked spells
3. Compare hit count against threshold (default: max_hits = 0)
4. Create failure record if threshold exceeded

For **interrupt** mechanics:
1. Get missed casts from InterruptAnalyzer
2. Check if missed cast spell_id matches any "interrupt" criteria
3. Create failure record (assigned to "Raid" since we don't track assignments)

### Data Flow

```
Encounter → FailureAnalyzer.analyze/1
              │
              ├── Load criteria for boss (Criteria.criteria_by_spell_id)
              │
              ├── analyze_avoidable_damage/2
              │      └── DamageTakenAnalyzer.analyze/1
              │
              └── analyze_missed_interrupts/2
                     └── InterruptAnalyzer.analyze/1
              │
              └── Return %{
                    failures: [...],
                    by_player: %{...},
                    by_mechanic: %{...},
                    summary: %{total_failures: N, ...}
                  }
```

## Files Created/Modified

### New Files
- `priv/repo/migrations/20251127000001_create_mechanic_criteria.exs`
- `lib/we_go_next/criteria/mechanic_criteria.ex`
- `lib/we_go_next/criteria.ex`
- `lib/we_go_next/analyzers/failure_analyzer.ex`

### Modified Files
- `lib/we_go_next/analyzers/damage_taken_analyzer.ex` - Added player count tracking to top_abilities
- `lib/we_go_next_web/live/encounter_live/show.ex` - Major UI updates (modal, tabs, criteria display)

## Roadmap Progress

### Phase 3: Criteria System ✅ COMPLETE
- [x] Mechanic types defined (avoidable, interrupt, soak, spread)
- [x] Database schema for criteria
- [x] UI to mark abilities as tracked
- [x] Failure detection during analysis
- [x] Failures displayed prominently

### Remaining MVP Features
- [ ] Phase 5A: Between-Pull Summary - Auto-generate summary on encounter end
- [ ] Pull Comparison - Show improvement/regression trends

## Usage Example

1. **Start server:** `mix phx.server`
2. **Import a combat log** from http://localhost:4000
3. **Click an encounter** to view details
4. **Go to "Damage Taken" tab**
5. **Click "+ Track"** on a damaging ability (e.g., "Fire Zone")
6. **Select "Avoidable Damage"** in the modal
7. **Go to "Failures" tab** - see who got hit

## What's Next

### Immediate Priorities
1. **Between-Pull Summary** (Phase 5A) - Auto-generate report with:
   - Deaths with causes
   - Mechanic failures from criteria
   - Comparison to previous attempt

2. **Interrupt Criteria Enhancement** - Track which player was assigned to interrupt (requires additional UI)

### Future Enhancements
- Soak/spread mechanic detection (requires position or debuff data)
- Boss profile export/import (JSON)
- Criteria presets for known bosses
- Threshold configuration UI (currently hardcoded)
