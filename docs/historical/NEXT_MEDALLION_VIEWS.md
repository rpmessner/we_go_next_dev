# Next Medallion-Backed Views

Task #23 planning output.

## Decision

Do not rebuild the old analyzer-cache tabs one-for-one. The next views should follow the current product priority stack:

1. My play, this pull
2. My play, over time
3. Raid-wide diagnosis
4. Sharing

The medallion path has proved the cross-encounter failure dashboard. The next step is an encounter-detail surface that uses silver/gold read models and starts with the highest-signal personal diagnostics.

## Selected Sequence

### 1. Encounter Detail Shell

Purpose: restore drill-down from the encounter list without resurrecting cached analyzer JSON.

Route: `/encounters/:id` or `/encounters/:dim_encounter_id`, backed by `gold.dim_encounter.id`.

Read-model grain:

- `gold.dim_encounter` as the route and page grain
- `silver.player_info` for roster and roles
- existing gold/silver read models for tabs as they are added

Rules dependency: none.

Notes:

- This shell should be intentionally sparse: metadata, outcome, roster, and navigation slots.
- Use `gold.dim_encounter.id`, not `public.encounters.id`, in URLs unless a compatibility redirect is explicitly needed.
- The page should link back to `/` and `/failures`.

### 2. Death Recap View

Purpose: answer "what killed me/us this pull?" between pulls.

Route placement: first tab/section in the encounter detail shell.

Read-model grain:

- one row per `silver.death`
- join `silver.player_info` by `(encounter_dim_id, target_guid)` for player names/classes
- join `gold.dim_encounter` for encounter metadata
- use `silver.death.damage_recap` as the embedded last-N damage detail

Rules dependency: none.

Why next:

- Highest diagnostic value after a wipe.
- Already has a silver table at the correct grain.
- Does not require authored rules or additional gold facts.

### 3. Personal Pull Summary

Purpose: put the current player's pull-level outcome first: deaths, failures, avoidable damage, interrupts, and top damage done.

Route placement: default tab/section once a configured character can be resolved; otherwise show a player selector.

Read-model grain:

- one row per `(encounter_dim_id, player_guid)` in a new gold/read-model query module
- source from `silver.player_info`
- aggregate:
  - `gold.fact_failure` for authored mechanic failures
  - `silver.damage_taken` for avoidable/high damage taken totals
  - `silver.damage_done` for top spell/target contribution
  - `silver.interrupt_opportunity` for successful and missed interrupt context
  - `silver.death` for death count and recap links

Rules dependency: partial.

- Mechanic failures depend on active/promoted rules via `gold.fact_failure`.
- Damage/death/interrupt rollups do not depend on authored rules.

Notes:

- This is a read model first, not a new table unless query complexity or performance demands it.
- Use the user's configured character name as the default focus, but keep the query player-guid based.

### 4. Interrupt Coverage View

Purpose: show successful kicks, missed opportunities, and raid-level interrupt failures.

Route placement: encounter detail tab plus optional cross-encounter summary later.

Read-model grain:

- one row per `silver.interrupt_opportunity`
- group by `(encounter_dim_id, interrupted_spell_id)` for spell coverage
- group by `interrupter_guid` for player contribution
- join `silver.player_info` for player names/classes
- optionally join `gold.fact_failure` for rules-backed missed-kick failures

Rules dependency: optional.

- Raw interrupt coverage has no rules dependency.
- "Required interrupt failure" labeling depends on `gold.dim_mechanic_criterion`/`gold.fact_failure`.

## Deferred Slices

### Damage Taken

Useful, but should follow the personal summary/death work so it does not become another broad meter table. Likely read-model grain:

- `(encounter_dim_id, target_guid, spell_id)` for player damage taken
- `(encounter_dim_id, spell_id)` for raid-wide damage sources
- join `silver.player_info` and spell-name lookup/read-model when available

Rules dependency: optional for avoidable labels; none for raw damage.

### Damage Done

Useful for "am I hitting the right target?" but needs target naming and eventually phase/window context to be more than a meter clone. Likely read-model grain:

- `(encounter_dim_id, source_guid, target_guid, spell_id)`
- later add target metadata and time-window projection before investing in a rich UI

Rules dependency: none.

### Debuffs

Useful after deaths/player summary. Likely read-model grain:

- `silver.debuff_application`
- grouped by `(encounter_dim_id, target_guid, spell_id)` and `(encounter_dim_id, spell_id)`

Rules dependency: optional if debuffs become authored spread/stack/soak criteria.

### Pull Summary

Do not rebuild the old `PullSummary` module. A medallion pull summary should be composed from the selected read models after death recap, personal summary, failures, and interrupts exist.

Rules dependency: mixed, because recommendations combine authored failures with raw deaths/damage/interrupts.

## Implementation Tasks Created From This Plan

- #32 Encounter detail shell
- #33 Death recap read model and view
- #34 Interrupt coverage read model and view
- #35 Personal pull summary read model and view

Patch-aware rule source ingestion remains a future data task and is unblocked by this planning pass, but it should not be pulled into the next view implementation sequence.
