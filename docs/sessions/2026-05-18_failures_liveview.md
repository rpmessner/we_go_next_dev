# Failures LiveView

## Date

2026-05-18

## Context

Started PR2 UI work after the PR1 acceptance gate closed. Task #15 adds the first view rebuilt against the medallion tiers instead of the legacy criteria/import UI path.

The new screen must read from `gold.fact_failure` and related gold dimensions, group failures across encounters by player and mechanic criterion, and support date filtering.

## Implementation

Added `WeGoNext.Gold.FailureSummary` as the read model for the UI.

Behavior:

- joins `gold.fact_failure` to `gold.dim_player`, `gold.dim_mechanic_criterion`, and `gold.dim_encounter`
- groups by player and criterion
- sums failure counts and damage
- counts distinct encounters per player/mechanic row
- supports inclusive `start_date` and `end_date` filters against `gold.dim_encounter.start_time`
- returns grouped player sections for rendering

Added `WeGoNextWeb.FailureLive.Index` at `/failures`.

UI behavior:

- date filter form with start/end date inputs
- summary counters for failures, players, and damage
- player sections with per-mechanic rows
- empty state when no matching failures exist
- home page navigation link to the new failures view

The implementation does not call legacy `Criteria.MechanicCriteria` or the old import/frontend analysis cache. It reads from the gold fact and dimension tables only.

## Tests

Added:

- `test/we_go_next/gold/failure_summary_test.exs`
- `test/we_go_next_web/live/failure_live_test.exs`
- `test/support/conn_case.ex`

Coverage:

- read model grouping by player and criterion
- inclusive date filtering
- static LiveView route rendering
- empty state rendering for a date range without facts

## Verification

Focused checks:

```text
mix test test/we_go_next/gold/failure_summary_test.exs test/we_go_next_web/live/failure_live_test.exs
mix test test/we_go_next/gold test/we_go_next_web/live/failure_live_test.exs test/we_go_next/importer_test.exs
```

Results:

```text
4 tests, 0 failures
21 tests, 0 failures
```

Full suite:

```text
mix test
```

Result:

```text
4 features, 67 tests, 0 failures, 3 skipped
```

Browser verification:

- loaded `http://localhost:4000/failures`
- confirmed the LiveView renders the filter controls, summary counters, and empty state

## Board State

Task #15 is complete.

Task #21 is now unblocked and can add the end-to-end Failures feature test.
