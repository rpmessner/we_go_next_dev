# Rules Layer Refactor Plan

## Context

Task #12 intentionally made the bronze -> silver -> gold path independent from the legacy public domain tables and independent from the existing frontend import flow. That is the right boundary for the current failure fact work:

- Bronze/log ingestion owns raw source files and parser output.
- Silver owns normalized encounter-grain projections.
- Gold owns analytic facts and dimensions.
- The existing LiveView import flow and legacy public tables stay outside the new medallion path for now.

Mechanic criteria are different from bronze, silver, and most gold data. They are business rules: curated definitions that say which spells count as avoidable, interrupt, soak, spread, stack, tank, or healer mechanics, and how those mechanics should be evaluated for a boss/difficulty. They should not be treated as source event data, and silver should not know about mechanic types.

The current `gold.dim_mechanic_criterion` table is a good short-term bridge for Task #12 because it lets `gold.fact_failure` rebuild entirely inside the medallion schema. Longer term, the rules need their own abstraction with explicit versioning, validation, and promotion into gold snapshots.

## Recommendation

Do not block the initial failure fact on the full rules refactor. Finish the current Task #12 backend path with manually seeded or test-seeded `gold.dim_mechanic_criterion` rows, then make this rules layer its own board before wiring the new frontend analytics flow.

The rules refactor should happen before:

- exposing criteria editing in LiveView
- making the frontend depend on `gold.fact_failure`
- adding more gold facts that share mechanic classification
- replacing or retiring the old criteria screens

This keeps the first medallion fact small and proves the data path, while preventing the old public `mechanic_criteria` model from becoming a hidden dependency of the new pipeline.

## Goals

- Model mechanic definitions as first-class business rules, not silver data.
- Keep the medallion pipeline independent from legacy `public.mechanic_criteria`.
- Make fact rebuilds reproducible by recording which rule version produced each gold fact.
- Support boss-specific and difficulty-specific overrides without duplicating every generic rule.
- Preserve the current matching behavior for failure facts until a deliberate semantics change is made.
- Create a clean path for future UI rule editing without tying it to the old import page.

## Non-Goals

- No import from legacy public criteria tables as part of the medallion pipeline.
- No frontend rewrite as part of this backend rules foundation.
- No attempt to infer all mechanic rules from logs automatically.
- No silver dependency on mechanic type, threshold, or failure semantics.
- No dbt or external warehouse runtime requirement for this phase.

## Current State

The cleaned Task #12 shape is:

- `gold.dim_encounter` stores the analytics encounter grain.
- Silver tables reference `gold.dim_encounter.id` through `encounter_dim_id`.
- `gold.dim_player` is conformed from `silver.player_info`.
- `gold.dim_mechanic_criterion` stores active mechanic criteria in the gold schema.
- `gold.fact_failure` rebuilds from `gold.dim_encounter`, `gold.dim_mechanic_criterion`, `gold.dim_player`, and `silver.*`.
- `FactFailure.rebuild_for_encounter/1` receives a gold encounter dimension id.

That is clean enough for the first gold fact. The weakness is that `gold.dim_mechanic_criterion` is doing two jobs:

- it behaves like editable business configuration
- it also behaves like a dimensional snapshot used by facts

Those jobs should be separated before the rules surface grows.

## Target Architecture

```text
Bronze logs
  -> Silver encounter projections
  -> Gold dim_encounter / dim_player

Rules schema
  -> validated active rule versions
  -> Gold mechanic criterion snapshots
  -> Gold facts
```

Recommended ownership:

- `rules.*`: source of truth for authored business rules.
- `gold.dim_mechanic_criterion`: immutable or append-only analytic snapshot of the rule rows used by facts.
- `gold.fact_failure`: fact rows keyed to the encounter, player, and criterion snapshot.
- UI: eventually edits `rules.*`, not `gold.*` directly.

## Architecture Decisions

These decisions unblock the first implementation pass. They should be revisited only when the app has season/patch metadata in the analytics model or when facts need to retain multiple ruleset outputs side by side.

### Ruleset Scope

Start with exactly one active ruleset globally.

Reasoning:

- `gold.dim_encounter` does not currently store season or patch metadata.
- Boss, difficulty, and spell overrides already cover the matching behavior needed for the current failure fact.
- Backfills and tests can still select a specific ruleset explicitly by id.
- A later season/patch scope can be added without changing silver or the rule matching semantics.

Implementation implication:

- `rules.ruleset` should support `draft`, `active`, and `archived` states.
- Enforce at most one active ruleset with a partial unique index on active status.
- Do not add season or patch columns in the first rules migration.

### Fact Rule Identity

Do not store `ruleset_id` directly on `gold.fact_failure` in this phase.

The criterion snapshot foreign key is the fact's rule identity:

```text
gold.fact_failure.criterion_dim_id
  -> gold.dim_mechanic_criterion.id
  -> ruleset_id / ruleset_version / source_rule_id
```

Reasoning:

- It keeps `gold.fact_failure` normalized and avoids inconsistent `ruleset_id` and `criterion_dim_id` pairs.
- The fact primary key can remain `(encounter_dim_id, player_dim_id, criterion_dim_id)`.
- Rebuilds replace the current fact materialization for an encounter rather than storing multiple ruleset outputs for the same encounter side by side.

Add `ruleset_id` directly to fact rows only if a later reporting need proves that joining through `gold.dim_mechanic_criterion` is not enough.

### Rebuild Rule Selection

Use explicit rebuild selection, not point-in-time rule selection by encounter timestamp, for this phase.

Supported modes:

```elixir
Gold.FactFailure.rebuild_for_encounter(encounter_dim_id, ruleset: :active)
Gold.FactFailure.rebuild_for_encounter(encounter_dim_id, ruleset_id: ruleset_id)
```

Defaulting to the active ruleset is acceptable for local interactive use. Tests, backfills, and reproducibility checks should pass `ruleset_id` explicitly.

Keep `activated_at` and `archived_at` for auditability, but do not infer a ruleset from `gold.dim_encounter.start_time` yet. That behavior needs season/patch policy and should be a separate decision.

### Threshold Schemas

Validate thresholds by mechanic type, but only encode semantics that the current backend can evaluate.

Initial rules:

- `avoidable`: require `threshold["max_hits"]` as a non-negative integer. A player fails when `hit_count > max_hits`.
- `interrupt`: allow `threshold["must_interrupt"]` as an optional boolean, defaulting to `true` when omitted. Missed interrupts still aggregate to the `__RAID__` sentinel with `total_damage = 0`.
- `soak`, `spread`, `stack`, `tank_mechanic`, and `healer_mechanic`: require an empty threshold map until a fact implementation defines their semantics.

This preserves current avoidable and interrupt behavior while preventing unused mechanic types from carrying unvalidated payloads that look meaningful.

### Rule Display Names

Treat ids as matching keys and names as curated display labels.

- `spell_id` and `boss_encounter_id` are authoritative for matching.
- `spell_name` and `boss_name` should be stored on rule rows for reviewability and copied into gold snapshots.
- Seed/import helpers may derive missing names from game data or logs, but curated rule names win when there is a conflict.

### Initial Seed Path

Use static JSON seed data loaded through an idempotent Elixir seed helper or Mix task.

Recommended shape:

```text
priv/rules/initial_mechanic_rules.json
```

Do not seed mutable mechanic rules in migrations, and do not require an admin UI/import flow for the backend foundation. The seed path should call the rules context so normal validation and ruleset activation logic are exercised.

## Proposed Schema

Create a dedicated schema:

```sql
CREATE SCHEMA rules;
```

Core tables:

```text
rules.ruleset
  id
  name
  status                 -- draft | active | archived
  version
  activated_at
  archived_at
  inserted_at
  updated_at

rules.mechanic_criterion
  id
  ruleset_id
  spell_id
  spell_name
  mechanic_type
  boss_encounter_id
  boss_name
  difficulty_id
  threshold
  notes
  active
  inserted_at
  updated_at
```

Gold snapshot options:

```text
gold.dim_mechanic_criterion
  id
  source_rule_id
  ruleset_id
  ruleset_version
  spell_id
  spell_name
  mechanic_type
  boss_encounter_id
  boss_name
  difficulty_id
  threshold
  notes
  active
  inserted_at
  updated_at
```

Or, if we decide `gold.dim_mechanic_criterion` should be fully append-only:

```text
gold.dim_mechanic_criterion
  id
  rule_fingerprint
  ruleset_id
  ruleset_version
  rule_payload
  valid_from
  valid_to
```

The first option is simpler and fits the current Ecto code. The second is more warehouse-pure but adds complexity before we need it. Start with the first option and make updates append new snapshot rows only when reproducibility requires it.

## Rule Matching Semantics

Keep the current failure matching rules unless we intentionally change them:

- Only active criteria are eligible.
- Criteria may be global, boss-specific, or boss-and-difficulty-specific.
- More specific criteria override less specific criteria for the same spell.
- Difficulty inheritance remains:
  - Normal sees Normal criteria.
  - Heroic sees Normal and Heroic criteria.
  - Mythic sees Normal, Heroic, and Mythic criteria.
- Avoidable failures use `threshold["max_hits"]`.
- A player fails avoidable damage when `hit_count > max_hits`.
- Missed interrupts aggregate to the `__RAID__` sentinel with `total_damage = 0`.

This logic should move out of raw SQL strings over time. The SQL can stay as the execution engine, but the ranking and validation rules should have named Elixir helpers and tests so future facts reuse the same semantics.

## Build Flow

For a fact rebuild:

1. Resolve the selected ruleset from `ruleset: :active` or an explicit `ruleset_id`.
2. Promote rules from `rules.mechanic_criterion` into `gold.dim_mechanic_criterion` snapshots if needed.
3. Rebuild `gold.dim_player` from silver for the encounter.
4. Rebuild `gold.fact_failure` against the selected gold criterion snapshot rows.
5. Store enough rule identity on the fact or snapshot to explain which ruleset produced the result.

The rebuild API should make rule selection explicit:

```elixir
Gold.FactFailure.rebuild_for_encounter(encounter_dim_id, ruleset: :active)
Gold.FactFailure.rebuild_for_encounter(encounter_dim_id, ruleset_id: ruleset_id)
```

Defaulting to active rules is fine for local use, but explicit `ruleset_id` is better for backfills and tests.

## Refactor Tasks

1. Create the `rules` schema and rule source tables.
2. Add Ecto modules for `Rules.Ruleset` and `Rules.MechanicCriterion`.
3. Move mechanic type validation to the rules context.
4. Add rule validation for thresholds by mechanic type.
5. Add a promotion module that copies active rules into `gold.dim_mechanic_criterion`.
6. Add ruleset identity to `gold.dim_mechanic_criterion`.
7. Update `Gold.FactFailure.rebuild_for_encounter/1` to select criteria by ruleset snapshot.
8. Add tests for difficulty inheritance, specificity ranking, inactive rules, and threshold validation.
9. Add a seed path for initial mechanic rules that does not read legacy public criteria tables.
10. Decide whether the current old criteria UI is retired, left alone, or replaced by a new rules UI.

## Testing Strategy

Unit tests:

- mechanic type validation
- threshold validation per mechanic type
- ruleset state transitions
- difficulty inheritance
- specificity ranking

Integration tests:

- promote a ruleset into gold snapshots
- rebuild a failure fact for one encounter
- rebuild the same encounter with a different ruleset and observe changed facts
- verify no production medallion module reads `public.mechanic_criteria`

Database checks:

- unique active ruleset constraint, if only one active ruleset is allowed
- non-null natural keys for rule rows
- indexes on `spell_id`, `boss_encounter_id`, `difficulty_id`, `ruleset_id`

## Frontend Boundary

Keep the old import/frontend flow separate until the medallion backend has stable contracts.

When the frontend is rebuilt, it should talk to:

- a rules context for editing rule drafts
- gold read models for analytics display
- explicit rebuild/backfill actions for recomputing facts

It should not call into old `Criteria.MechanicCriteria` as a compatibility bridge for the medallion path.

## Open Questions

- When season/patch metadata exists in gold, should active rulesets become scoped by season, patch, or both?
- Do any reports need multiple ruleset rebuild outputs for the same encounter to coexist?
- Which future facts should define structured thresholds for `soak`, `spread`, `stack`, `tank_mechanic`, and `healer_mechanic`?
- Should static rule seeds be split by raid/season once there is enough curated data?

## Acceptance Criteria

- New rules source tables exist outside gold.
- `gold.dim_mechanic_criterion` is populated from rules, not legacy public tables.
- `gold.fact_failure` can rebuild with an explicit ruleset.
- Tests prove difficulty inheritance and specificity matching.
- No medallion production code reads `public.mechanic_criteria`.
- The existing frontend import flow remains untouched unless a later frontend task explicitly changes it.
