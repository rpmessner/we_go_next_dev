# 2026-05-18: Gold Rebuild Boundary and Real-Data Workflow Friction

## Context

This session continued the medallion warehouse/rules refactor after PR1 backend and failures-view work. The user was exercising real log import and failures UI flows and hit several workflow gaps around rules activation, recomputation, and stale “watching” terminology.

## Task Board Updates

- Marked `#29 Add Patch-Aware Rule Source Ingestion` complete after confirming the source-data DBM ingestion groundwork had already been implemented in a prior session.
- Completed `#45 Refactor FactFailure into a mechanic fact builder boundary`.
- Completed `#46 Add a gold encounter rebuild orchestrator`.
- Removed completed `#45` from stale blocker lists on `#46` and `#44`.
- Confirmed `#46` should not be blocked by silver-level future tasks because it preserves the current silver contract and creates the gold plug-in boundary those later tasks need.
- Added near-term real-data workflow tasks:
  - `#52 Add rules status and bootstrap UI`
  - `#53 Add medallion rebuild and recompute controls`
  - `#54 Surface data readiness diagnostics in failures UI`, blocked by `#52` and `#53`

## Code Changes

### Fact Failure Builder Boundary

Commit: `f0149e2 Refactor fact failure rebuild boundary`

- Kept `WeGoNext.Gold.FactFailure` as the schema and public API.
- Moved rebuild orchestration to `WeGoNext.Gold.FactFailure.Rebuilder`.
- Split effective criterion selection into `WeGoNext.Gold.FactFailure.RuleSelector`.
- Split SQL assembly into `WeGoNext.Gold.FactFailure.Query`.
- Added mechanic-specific builder modules:
  - `WeGoNext.Gold.FactFailure.Builders.AvoidableDamage`
  - `WeGoNext.Gold.FactFailure.Builders.MissedInterrupt`
- Preserved current avoidable and missed-interrupt semantics.

### Silver Duplicate Batch Fix and Settings Copy

Commit: `b93724a Clarify log import flow and dedupe silver rows`

- Fixed a real import failure:
  - Postgres raised `ON CONFLICT DO UPDATE command cannot affect row a second time`.
  - Cause: a single silver insert batch could contain duplicate natural keys.
  - Fix: `WeGoNext.Silver.insert_rows/5` now deduplicates rows by the same conflict target before `Repo.insert_all/3`.
- Added regression coverage for duplicate death and interrupt natural keys in one import batch.
- Updated Settings page wording because auto filesystem watching is no longer active:
  - “Import Logs”
  - “Import Most Recent Log”
  - “Import Selected Log”
  - “Current Log”
- Confirmed `WeGoNext.FileWatcher` is now a current-log pointer, not a live file polling watcher.

### Gold Encounter Rebuild Orchestrator

Commit: `eb823f0 Add gold encounter rebuild orchestrator`

- Added `WeGoNext.Gold.RebuildEncounter` as the encounter-grain gold rebuild boundary.
- Updated `WeGoNext.Importer` to call `RebuildEncounter.rebuild/2` instead of `Gold.FactFailure` directly.
- Updated `mix wgn.rebuild_gold` to use the same orchestrator.
- Centralized missing-active-ruleset skip behavior in the gold boundary.
- Added tests for:
  - Active ruleset fact rebuild.
  - Explicit `ruleset_id` pass-through.
  - Missing active ruleset skip behavior.
  - Importer delegation through the gold boundary.

## Rules and Rebuild Findings

- There is no frontend for rules definition or activation yet.
- Current local DB state during the session had:
  - `rules.ruleset`: 1
  - `rules.mechanic_criterion`: 2
  - `gold.dim_mechanic_criterion`: 2
  - `gold.fact_failure`: 0
- The existing ruleset was `draft`, so imports skipped fact generation under the default active-ruleset path.
- Current protocol:
  - Rules changed only: seed/activate/promote rules, then `mix wgn.rebuild_gold`.
  - Gold computation changed: `mix wgn.rebuild_gold`.
  - Silver projection or parser changed: force reimport affected logs.
- The home page already has a `Reimport` / `Confirm Reimport` flow for fully imported logs, wired to `force_reimport: true`.

## Verification

Focused and full test runs passed during the session:

```bash
mix test test/we_go_next/gold/fact_failure_test.exs
mix test test/we_go_next/importer_test.exs test/mix/tasks/wgn_rebuild_gold_test.exs test/we_go_next/gold/failure_summary_test.exs test/we_go_next_web/live/failure_live_test.exs test/features/failures_test.exs
mix test test/we_go_next/silver/persistence_test.exs
mix test test/we_go_next/importer_test.exs test/features/import_status_test.exs test/features/minimal_flow_test.exs test/features/live_sync_test.exs
mix test test/we_go_next/gold/rebuild_encounter_test.exs test/we_go_next/importer_test.exs test/mix/tasks/wgn_rebuild_gold_test.exs
mix test
```

Final full-suite result after `#46`: `5 features, 78 tests, 0 failures, 3 skipped`.

## Next Recommended Work

The board is still architecturally sound, but the near-term priority should shift toward real-data operability:

1. `#52 Add rules status and bootstrap UI`
2. `#53 Add medallion rebuild and recompute controls`
3. `#54 Surface data readiness diagnostics in failures UI`
4. Continue medallion encounter detail prerequisites: `#48`, `#51`, then `#32`

This keeps the medallion path intact while reducing the friction found when driving the app through real log data.
