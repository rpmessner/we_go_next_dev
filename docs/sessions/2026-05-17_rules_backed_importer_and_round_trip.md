# Rules-backed Importer and Silver Round-trip Verification

## Date

2026-05-17

## Context

Continued the `Data Warehouse Refactor` board after the rules foundation and silver persistence work. The goal was to finish the rules-backed gold criterion snapshot path, make failure fact rebuilds ruleset-aware, hook the medallion flow into importer inserts, and start PR1 verification tasks.

The main architectural constraint remained unchanged:

- new medallion code should not read legacy `public.mechanic_criteria`
- `rules.*` owns authored business rules
- `gold.dim_mechanic_criterion` is the fact-facing rule snapshot
- `gold.fact_failure` identifies rules through `criterion_dim_id`
- importer silver/gold work should run only for newly inserted encounters by default

## Completed Tasks

Completed during this session:

- #27 Promote Rules to Gold Criterion Snapshots
- #28 Make FactFailure Ruleset-Aware
- #14 Hook Silver and Gold into Importer
- #16 Silver Round-trip Tests

Board state after the session:

- #22 PR 1 Acceptance Gate is now blocked only by #17 and #19.
- #15, #20, #21, and #23 remain gated by #22 or downstream UI dependencies.
- #21 no longer depends on #14.

## Gold Criterion Snapshots

Task #27 added rules identity to `gold.dim_mechanic_criterion`.

New columns:

- `source_rule_id`
- `ruleset_id`
- `ruleset_version`

`WeGoNext.Gold.DimMechanicCriterion` now requires those fields. A unique index on `source_rule_id` makes promotion idempotent.

Added promotion APIs in `WeGoNext.Rules`:

```elixir
Rules.promote_ruleset_to_gold(ruleset)
Rules.promote_ruleset_to_gold(ruleset_id)
Rules.promote_active_ruleset_to_gold()
```

Promotion copies the fact matching inputs from `rules.mechanic_criterion` into the gold snapshot:

- `spell_id`
- `spell_name`
- `mechanic_type`
- `boss_encounter_id`
- `boss_name`
- `difficulty_id`
- `threshold`
- `notes`
- `active`

Runtime smoke test seeded and promoted the bundled local rules twice. The gold snapshots remained stable and included:

- `1214081` / `Arcane Expulsion`
- `1269183` / `Void Burst`

Commit:

```text
1e076a2 Promote rules to gold criterion snapshots
```

## Ruleset-aware Fact Failure

Task #28 updated `Gold.FactFailure.rebuild_for_encounter/1`.

Supported modes:

```elixir
FactFailure.rebuild_for_encounter(encounter_dim_id)
FactFailure.rebuild_for_encounter(encounter_dim_id, ruleset: :active)
FactFailure.rebuild_for_encounter(encounter_dim_id, ruleset_id: id)
```

Behavior changes:

- default rebuild resolves the active ruleset
- explicit `ruleset_id` supports backfills/tests
- selected criteria are filtered by `gold.dim_mechanic_criterion.ruleset_id`
- stale fact deletion only removes facts tied to the selected ruleset's criterion snapshots
- avoidable damage, missed interrupts, difficulty inheritance, specificity, thresholds, and the `__RAID__` sentinel semantics were preserved

Added tests for:

- active ruleset selection
- explicit ruleset rebuilds
- promoted local seed rules flowing into facts
- no dependency on legacy `public.mechanic_criteria`

Commit:

```text
54b73e4 Make fact failure rebuild ruleset-aware
```

## Importer Medallion Hook

Task #14 connected the importer to the medallion path.

Importer behavior now:

- scans encounter boundaries as before
- inserts or fetches legacy `public.encounters` rows
- collects only newly inserted encounters
- for each newly inserted encounter:
  - parses normalized events from byte offsets
  - creates or reuses `gold.dim_encounter`
  - runs `Silver.project_and_persist/2`
  - runs `FactFailure.rebuild_for_encounter/1`
- existing duplicate encounters do not create silver/gold rows by default

The legacy JSON analysis cache remains available during transition. A new `compute_legacy_analysis: false` option was added for tests and backfills that only want the medallion path.

The importer returns `medallion_results` alongside `new_encounters`, making the silver/gold hook observable in tests without depending on UI behavior.

Added importer tests proving:

- duplicate encounters do not run medallion inserts
- a new fixture import creates silver rows and a rules-backed gold failure fact
- re-importing the same log does not duplicate medallion rows

Commit:

```text
3891d28 Hook medallion import path into importer
```

## Silver Round-trip Verification

Task #16 added a dedicated round-trip test:

```text
test/we_go_next/silver/round_trip_test.exs
```

The test persists silver rows from normalized fixture events and compares those stored rows against the existing analyzer output for the same encounter.

Coverage:

- damage taken totals
- death rows and killing blow data
- interrupt opportunities
- debuff applications and durations
- tank role detection

The fixture is adjusted in-test so the legacy interrupt analyzer and silver interrupt opportunity projection have matching semantics for the missed interrupt case.

This file is currently uncommitted at the time this note was written.

## Verification

Focused checks run during this session included:

```text
mix test test/we_go_next/rules_test.exs test/we_go_next/gold/schema_test.exs
mix test test/we_go_next/rules_test.exs test/we_go_next/gold/schema_test.exs test/we_go_next/gold/fact_failure_test.exs
mix test test/we_go_next/gold/fact_failure_test.exs test/we_go_next/rules_test.exs
mix test test/we_go_next/importer_test.exs
mix test test/we_go_next/silver/round_trip_test.exs
mix test test/we_go_next/silver
mix test
```

Final full-suite status after #16:

```text
4 features, 61 tests, 0 failures, 3 skipped
```

Both test and dev databases were migrated during the #27 work so `gold.dim_mechanic_criterion` has the new rules identity columns.

## Current Uncommitted Work

At the end of this session, the working tree contains:

```text
?? test/we_go_next/silver/round_trip_test.exs
```

That file implements task #16 and has passed focused and full-suite verification.

## Next Work

Immediate PR1 blockers:

- #17 Silver Idempotency Tests
- #19 Move Detection Tests

After #17 and #19:

- #22 PR 1 Acceptance Gate

Still gated by #22:

- #15 Failures LiveView
- #20 Gold Rebuild Task
- #21 End-to-end Failures Feature Test
- #23 Plan Next Medallion-Backed Views

Future/non-blocking:

- #29 Add Patch-Aware Rule Source Ingestion
