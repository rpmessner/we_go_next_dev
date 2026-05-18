# 2026-05-18 Gold Rebuild Task

Task #20 added a Mix task for rebuilding gold failure facts from existing silver rows.

## Implemented

- Added `mix wgn.rebuild_gold`.
- Default behavior rebuilds `gold.fact_failure` for every `gold.dim_encounter` row using the active ruleset.
- Added `--ruleset-id` / `-r` for explicit ruleset rebuilds.
- Added `--encounter-id` / `-e` for focused single-encounter rebuilds.

The task calls `Gold.FactFailure.rebuild_for_encounter/2`, so it uses the same ruleset-aware criterion snapshot selection as importer-driven fact rebuilds. It does not parse combat logs or touch the bronze import path.

## Verification

- `mix test test/mix/tasks/wgn_rebuild_gold_test.exs`
- `mix test test/we_go_next/gold/fact_failure_test.exs test/mix/tasks/wgn_rebuild_gold_test.exs`
