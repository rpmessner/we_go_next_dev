# 2026-05-18 Failures Feature Test

Task #21 added end-to-end Wallaby coverage for the gold-backed `/failures` page.

## Implemented

- Added `FailuresPage` page object.
- Added feature coverage that prepares data through the medallion path:
  - seed bundled mechanic rules
  - activate the seeded ruleset
  - promote authored rules into `gold.dim_mechanic_criterion`
  - insert silver player and damage rows
  - rebuild `gold.fact_failure`
- Verified the rendered player group, summary stats, and one table row against expected failure data.

The test does not seed legacy `public.mechanic_criteria`.

## Verification

- `mix test test/features/failures_test.exs`
