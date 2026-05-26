# 2026-05-19: Medallion Second-Opinion Roadmap Adjustment

## Context

Reviewed `medallion-refactor-second-opiion.md` against the current app, task board, and documentation. Several critique items had already landed after the reviewed branch state, including the gold rebuild boundary, gold-keyed encounter shell, reference dimensions, rules operations UI, and recompute controls.

The useful remaining critique is not that the medallion architecture needs to be replaced. It is that the next priority should be correctness before broader source-data inference:

- silver should stay observational and avoid naming raw observations as authored opportunities,
- promoted rule snapshots must not silently mutate under existing fact rows,
- derived rows need visible version stamps so stale data can be explained,
- the product still needs a player/encounter performance fact for pull-over-pull trends,
- richer avoidable semantics need defensive/immunity/buff windows before rule coverage expands.

## Task Board Updates

Created new tasks:

- `#60 Make promoted rule snapshots version-immutable`
- `#61 Tighten missed-interrupt silver semantics`
- `#62 Stamp silver projections and gold fact builders with versions`
- `#63 Add player encounter performance fact`
- `#64 Add defensive buff window silver observations`

Updated existing tasks:

- `#36 Add DBM Bulk Source Import` is pending and blocked by `#59`, so parser quality comes before bulk DBM evidence intake.
- `#40 Cross-Reference Candidates With Observed Silver Events` now also blocks on `#61`, so interrupt evidence is not cross-referenced from overbroad missed-interrupt rows.
- `#42 Promote Accepted Candidates Into Draft Rules` now blocks on `#60`, so candidate promotion does not scale before gold criterion snapshots are version-stable.
- `#44 Define Additional Mechanic Fact Semantics` now explicitly calls out defensive buff windows before expanding avoidable semantics.
- `#54 Surface data readiness diagnostics in failures UI` now calls out known semantic limits until `#61` and `#62` land.

## Documentation Updates

Updated:

- `docs/ROADMAP.md`
- `CLAUDE.md`
- `docs/ARCHITECTURE.md`

The revised roadmap prioritizes `#60`, `#61`, `#62`, `#54`, and `#63` before broad source-data inference. DBM and WowAnalyzer remain evidence inputs, not active rule or fact writers.

## Resulting Priority

Work should now prefer:

1. stabilize fact meaning,
2. make silver/gold derivation semantics honest and inspectable,
3. explain readiness/staleness in the UI,
4. add the missing trend fact,
5. then scale DBM/WowAnalyzer candidate ingestion and review.
