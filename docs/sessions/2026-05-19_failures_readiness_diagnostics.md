# 2026-05-19: Failures Readiness Diagnostics

## Context

Worked task `#54 Surface data readiness diagnostics in failures UI`.

The failures page previously rendered grouped `gold.fact_failure` rows and showed a generic empty state when no rows matched the current date range. That left common medallion roadblocks invisible unless the operator queried SQL manually.

## Changes

Added `WeGoNext.Gold.FailureSummary.readiness/1`, which reports:

- active ruleset presence,
- active authored rule count,
- active promoted gold criterion snapshot count,
- gold encounters in the selected date range,
- gold fact rows in the selected date range,
- active-rule fact rows in the selected date range,
- silver observations matching active promoted avoidable/interrupt criteria,
- fact rows that do not match the active ruleset version or current criterion snapshot.

Updated `/failures` to render a Data Readiness panel with diagnostics for:

- no active ruleset,
- no promoted criteria,
- no gold encounters in scope,
- no matching silver observations,
- no gold failure facts,
- stale or mismatched facts.

The panel also surfaces current known limits:

- interrupt evidence is provisional until task `#61`,
- builder/projection code-version staleness cannot be detected until task `#62`.

## Tests

Added coverage for readiness calculations and LiveView empty-state diagnostics.

Verification:

```bash
mix test test/we_go_next/gold/failure_summary_test.exs test/we_go_next_web/live/failure_live_test.exs
mix test
```

Result:

```text
5 features, 109 tests, 0 failures, 3 skipped
```

Browser verification loaded `/failures` and confirmed the Data Readiness panel rendered the current local state with no active ruleset, 48 gold encounters, zero silver matches, and zero facts.
