# Session: Criteria System Implementation (Phase 3)
**Date:** 2025-11-27
**Focus:** Implement mechanic criteria tracking and failure detection

## Overview

Implemented Phase 3 (Criteria System) from the roadmap. The tool can now track specific mechanics as "avoidable damage", "must interrupt", etc., and automatically flag player failures. This is a critical MVP feature that transforms raw event data into actionable coaching feedback.

## What Was Built

### 1. Database Schema
**File:** `priv/repo/migrations/20251127000001_create_mechanic_criteria.exs`

New `mechanic_criteria` table with:
- `spell_id` - The WoW spell/ability ID (integer, required)
- `spell_name` - Human-readable name (string, required)
- `mechanic_type` - Classification (string, required)
- `boss_encounter_id` / `boss_name` - Optional boss-specific criteria
- `threshold` - JSON map for failure detection config (e.g., `{"max_hits": 0}`)
- `notes` - Coaching notes (text)
- `active` - Whether criteria is currently being tracked (boolean, default true)

**Indexes:**
- `spell_id` - Fast lookup by ability
- `boss_encounter_id` - Fast lookup by boss
- Unique constraint on `(spell_id, boss_encounter_id)` - Prevents duplicates

### 2. Ecto Schema
**File:** `lib/we_go_next/criteria/mechanic_criteria.ex`

MechanicCriteria schema with:
- Changeset validation for required fields
- Mechanic type validation against allowed types
- Unique constraint handling
- Helper functions:
  - `mechanic_types/0` - Returns list of valid types
  - `type_label/1` - Human-readable label (e.g., "Avoidable Damage")
  - `type_color/1` - CSS color class for UI
  - `check_failure/2` - Failure detection logic

**Supported Mechanic Types:**
- `avoidable` - Damage that players should avoid
- `interrupt` - Casts that must be kicked
- `soak` - Damage that needs to be shared
- `spread` - Debuffs requiring players to spread
- `stack` - Mechanics requiring grouping
- `tank_mechanic` - Tank-specific mechanics
- `healer_mechanic` - Healer-specific mechanics

### 3. Criteria Context
**File:** `lib/we_go_next/criteria.ex`

CRUD operations:
- `list_criteria/0` - All active criteria
- `list_all_criteria/0` - All criteria including inactive
- `list_criteria_for_boss/1` - Boss-specific + global criteria
- `get_criteria_for_spell/2` - Lookup by spell ID
- `create_criteria/1` - Create new criteria
- `update_criteria/2` - Update existing
- `delete_criteria/1` - Remove criteria
- `toggle_criteria/1` - Enable/disable
- `criteria_by_spell_id/1` - Returns `%{spell_id => [criteria]}` map for fast lookup

### 4. Failure Analyzer
**File:** `lib/we_go_next/analyzers/failure_analyzer.ex`

New analyzer that applies tracked criteria to encounters:

**Main Function:** `analyze/1`
- Loads active criteria for the boss encounter
- Runs avoidable damage analysis
- Runs missed interrupt analysis
- Returns structured results

**Returns:**
```elixir
%{
  failures: [%Failure{}, ...],
  by_player: %{player_name => [%Failure{}, ...]},
  by_mechanic: %{spell_name => [%Failure{}, ...]},
  summary: %{
    total_failures: integer,
    players_with_failures: integer,
    mechanics_failed: integer
  }
}
```

**Failure Struct:**
```elixir
%Failure{
  player_name: "Mittwoch",
  player_guid: "Player-...",
  spell_id: 12345,
  spell_name: "Fire Zone",
  mechanic_type: "avoidable",
  hit_count: 3,
  total_damage: 450000,
  reason: "took 3 hit(s) (max: 0)",
  criteria_id: 1
}
```

### 5. Damage Analyzer Enhancement
**File:** `lib/we_go_next/analyzers/damage_taken_analyzer.ex`

Updated `top_abilities/2` to track unique player count per ability:
- Now returns `{name, %{total: N, hits: N, ability_id: id, players: N}}`
- Uses MapSet internally to count unique players
- Enables UI to show "5 players hit" alongside total hits

### 6. UI Updates
**File:** `lib/we_go_next_web/live/encounter_live/show.ex`

Major additions (~360 lines):

**New Failures Tab:**
- First tab in navigation
- Highlighted in red when failures > 0
- Shows summary box with total failures
- "By Mechanic" section with failure counts per spell
- "By Player" table showing who failed what

**Criteria Tracking in Damage Tab:**
- New "Track" column in abilities table
- "+ Track" button for untracked abilities
- "✕" button to remove tracking
- Tracked abilities show colored label with type

**Criteria Selection Modal:**
- Opens when clicking "+ Track"
- Four options: Avoidable, Must Interrupt, Soak, Spread
- Each option has description text
- Cancel button to close

**Quick Stats Updates:**
- Added "Failures" stat with red highlighting when > 0
- Added "Tracked" stat showing criteria count
- Grid expanded to 5 columns

**Event Handlers:**
- `open_track_modal` - Opens modal with spell info
- `close_modal` - Closes modal
- `create_criteria` - Creates criteria from modal selection
- `remove_criteria` - Deletes criteria for a spell

**Helper Functions:**
- `get_criteria/2` - Get first criteria for spell
- `criteria_color/2` - Get CSS color for tracked spell
- `sorted_by_mechanic/1` - Sort failures by mechanic
- `sorted_by_player/1` - Sort failures by player
- `failure_type_color/1` - Get color for failure type

## Data Flow

```
User clicks encounter
        ↓
EncounterLive.Show.mount/3
        ↓
load_analysis/1
        ├── DeathAnalyzer.analyze/1
        ├── DamageTakenAnalyzer.analyze/1
        ├── InterruptAnalyzer.analyze/1
        ├── DebuffAnalyzer.analyze/1
        ├── FailureAnalyzer.analyze/1  ← NEW
        └── Criteria.criteria_by_spell_id/1
        ↓
Assigns populated, UI renders
        ↓
User clicks "+ Track" on ability
        ↓
open_track_modal event → modal shown
        ↓
User selects mechanic type
        ↓
create_criteria event
        ├── Criteria.create_criteria/1
        └── Reload criteria_by_spell
        ↓
UI updates with tracked ability colored
        ↓
FailureAnalyzer re-runs on next encounter view
```

## Commits Created

8 granular commits in logical order:

| Commit | Description |
|--------|-------------|
| `5d91d7e` | Add mechanic_criteria database migration |
| `81c1e84` | Add MechanicCriteria Ecto schema |
| `37ae38c` | Add Criteria context for CRUD operations |
| `38eb63d` | Track unique player count in top_abilities |
| `d7fddc1` | Add FailureAnalyzer for mechanic failure detection |
| `ec82505` | Add criteria tracking UI and failures tab |
| `772ad87` | Update roadmap: mark Phase 3 complete |
| `987eaac` | Add session log for criteria system implementation |

## Files Summary

### New Files (6)
- `priv/repo/migrations/20251127000001_create_mechanic_criteria.exs` - Migration
- `lib/we_go_next/criteria/mechanic_criteria.ex` - Ecto schema
- `lib/we_go_next/criteria.ex` - Context module
- `lib/we_go_next/analyzers/failure_analyzer.ex` - New analyzer
- `docs/sessions/2025-11-27_criteria_system_implementation.md` - This file

### Modified Files (2)
- `lib/we_go_next/analyzers/damage_taken_analyzer.ex` - Added player count
- `lib/we_go_next_web/live/encounter_live/show.ex` - Major UI additions
- `docs/ROADMAP.md` - Marked Phase 3 complete

## Usage Instructions

1. **Start server:** `mix phx.server`
2. **Import a combat log** from http://localhost:4000
3. **Click an encounter** to view details
4. **Go to "Damage Taken" tab**
5. **Click "+ Track"** on any ability with an ability_id
6. **Select mechanic type** in the modal (e.g., "Avoidable Damage")
7. **Criteria is saved** - ability now shows colored label
8. **Go to "Failures" tab** to see who failed the mechanic
9. **Remove tracking** by clicking "✕" next to tracked abilities

## Roadmap Progress

### Phase 3: Criteria System ✅ COMPLETE

**Completed:**
- [x] Mechanic types defined and implemented
- [x] Database schema for criteria
- [x] UI to mark abilities as tracked
- [x] Failure detection during analysis
- [x] Failures displayed prominently in UI

**Deferred to future:**
- [ ] Threshold configuration UI (currently uses defaults)
- [ ] Notes/description editing
- [ ] Boss profile export/import (JSON)
- [ ] Profile sharing

### MVP Status

**Non-Negotiable Items:**
- [x] Death tracking with cause (Phase 1A)
- [x] File watching with encounter detection (Phase 4A)
- [x] Dashboard showing deaths/failures after pull ends (Phase 4C)
- [x] Basic criteria matching (Phase 3D)
- [ ] Between-pull summary (Phase 5A) - **Next priority**

## Technical Notes

### Why JSON for Threshold?

Using a JSON/map field for threshold configuration allows flexibility:
```elixir
# Avoidable damage
%{"max_hits" => 0}  # Any hit is failure
%{"max_hits" => 2}  # More than 2 hits is failure

# Interrupt (future)
%{"must_interrupt" => true}

# Soak (future)
%{"min_soakers" => 3}
```

This avoids schema migrations when adding new threshold types.

### Criteria Scoping

Criteria can be:
1. **Global** - `boss_encounter_id: nil` - Applies to all encounters
2. **Boss-specific** - `boss_encounter_id: "2887"` - Only for that boss

When loading criteria for an encounter, both are fetched:
```elixir
where([c], is_nil(c.boss_encounter_id) or c.boss_encounter_id == ^boss_id)
```

### Failure Detection Logic

**Avoidable Damage:**
1. Get damage stats for non-tanks only (DPS/healers)
2. For each player, check if they have damage from tracked spells
3. Compare hit count to `max_hits` threshold (default: 0)
4. Create failure if `hits > max_hits`

**Missed Interrupts:**
1. Get missed casts from InterruptAnalyzer
2. Check if missed cast spell_id matches any "interrupt" criteria
3. Create failure assigned to "Raid" (no individual assignment tracking yet)

## What's Next

### Immediate Priority: Phase 5A (Between-Pull Summary)

Auto-generate summary when encounter ends:
- Deaths with causes
- Mechanic failures from criteria
- Comparison to previous attempt
- "What killed us" analysis for wipes

### Future Enhancements

1. **Interrupt assignments** - Track who should kick, flag specific player on miss
2. **Soak detection** - Use debuff data to count soakers
3. **Spread detection** - Detect when debuff hits multiple nearby players
4. **Threshold UI** - Allow customizing max_hits in UI
5. **Boss presets** - Pre-configured criteria for known bosses
