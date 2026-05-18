# 2026-05-18 Next Medallion Views Plan

Task #23 planned the next medallion-backed app views after `/failures`.

## Outcome

Created `docs/NEXT_MEDALLION_VIEWS.md`.

The selected sequence is:

1. Encounter detail shell keyed by `gold.dim_encounter.id`
2. Death recap view from `silver.death`
3. Personal pull summary read model and view
4. Interrupt coverage read model and view

Damage taken, damage done, debuffs, and pull summary are deferred until the first per-encounter medallion views prove the pattern.

## Rationale

The product vision prioritizes "my play, this pull" before broad raid-wide reporting. Death recap and personal pull summary serve that priority better than recreating every old analyzer tab.

## Board Updates

Implementation tasks were added for the selected slices. Patch-aware rule source ingestion remains future work and no longer needs to be blocked by the planning task.
