# PR1 Acceptance Gate

## Date

2026-05-18

## Context

Closed the PR1 acceptance gate for the `Data Warehouse Refactor` board after the remaining verification tasks completed:

- #17 Silver Idempotency Tests
- #19 Move Detection Tests

This gate verifies that the backend medallion path is ready before PR2 UI/view work starts.

## Acceptance Result

Task #22 is accepted.

Verified coverage includes:

- canonical silver projection grains
- silver persistence and round-trip behavior
- silver idempotency, including normalized sentinel key values for unknown GUIDs and melee/unknown spell IDs
- gold `fact_failure` derivation for avoidable damage
- raid-level missed interrupt facts using the raid sentinel
- criterion difficulty inheritance and specificity
- `threshold["max_hits"]` behavior
- rules-backed criterion snapshots promoted from `rules.mechanic_criterion` into `gold.dim_mechanic_criterion`
- ruleset-aware `gold.fact_failure` rebuilds
- importer medallion hook for newly inserted encounters only
- dual-source bronze ingestion for live and Warcraft Logs archive files
- live-to-archive move detection with preserved `last_parsed_byte`
- archive continuation parsing from the preserved byte offset

The legacy JSON analysis cache remains available during transition, but new view work should target the silver/gold/rules read path.

## Verification

Focused acceptance suite:

```text
mix test test/we_go_next/silver test/we_go_next/gold test/we_go_next/rules_test.exs test/we_go_next/importer_test.exs test/we_go_next/bronze test/we_go_next/accounts_test.exs test/we_go_next/combat_log_file_test.exs
```

Result:

```text
57 tests, 0 failures
```

Full suite:

```text
mix test
```

Result:

```text
4 features, 63 tests, 0 failures, 3 skipped
```

## Board State

With #22 complete, the following tasks are unblocked for PR2/planning work:

- #15 Failures LiveView
- #20 Gold Rebuild Task
- #23 Plan Next Medallion-Backed Views

Task #21 remains blocked by #15 because the end-to-end feature test depends on the Failures LiveView.

Future/non-blocking:

- #29 Add Patch-Aware Rule Source Ingestion
