# Legacy Analysis Pruning

## Date

2026-05-18

## Context

Task #30 moved ahead of additional PR2 UI work so old analysis pages do not compete with the new medallion-backed direction.

The key decision is that any analysis surface still worth keeping must be rebuilt against silver/gold/rules read models. The old analyzer-cache UI was useful for the MVP prototype, but it now reads from the wrong layer and creates pressure to keep `public.mechanic_criteria` alive.

## Pruned Active UI

Removed active routing and navigation for the legacy encounter detail analysis page:

- removed `/encounters/:id` from the router
- removed encounter-card links from the home page encounter list
- removed legacy analysis status/death-count display from encounter cards
- deleted `EncounterLive.Show`
- deleted the legacy tab components:
  - summary
  - failures
  - deaths
  - damage taken
  - damage done
  - interrupts
  - debuffs
- deleted the legacy encounter detail page object and updated feature tests to cover import/list behavior only

The active UI now keeps:

- `/` for transitional combat-log import and encounter listing
- `/failures` for the first gold-backed analysis view
- `/settings` for operational path/watch settings

## Quarantined Legacy Backend

The analyzer modules and `AnalysisCache` remain in the codebase for now as transitional backend code and historical reference. They are no longer an active UI route.

Importer behavior changed so legacy JSON analysis cache computation is opt-in:

```elixir
Importer.import_log(path, user_id, compute_legacy_analysis: true)
```

By default, importer analytics run through the medallion path: parse events, persist silver rows, and rebuild gold failure facts for newly inserted encounters.

## Remaining Transitional Surfaces

These remain intentionally transitional:

- `public.encounters`: still used for import bookkeeping and as the current encounter-list source
- `analysis` column on public encounters: still present for compatibility, but not used by active UI
- legacy analyzers: retained until each useful analysis perspective has a gold/silver-backed replacement or is explicitly discarded
- `public.mechanic_criteria`: retained only for legacy tests proving gold fact rebuilds ignore it

New UI work should not add reads from those legacy surfaces.

## Verification

Focused checks:

```text
mix test test/we_go_next/importer_test.exs test/we_go_next/gold test/we_go_next_web/live/failure_live_test.exs
```

Result:

```text
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

- load `/`
- import/list workflow remains available
- load `/failures`
- gold-backed failures view remains available

## Board State

Task #30 is complete.

This unblocks:

- #20 Gold Rebuild Task
- #21 End-to-end Failures Feature Test
- #23 Plan Next Medallion-Backed Views
