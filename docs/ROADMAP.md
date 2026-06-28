# Roadmap

The durable, high-level index. Each workstream is an **initiative** with its own doc in [`initiatives/`](initiatives/README.md) and a Linear **project** on the **WE** board (workspace `we-go-next`). The board is the source of truth for exact status; the initiative docs hold scope/rationale.

## Direction

Turn observed current-tier mechanics from imported logs into editable rules → rebuilt facts → visible failures, then layer authoring on top. Mechanic detection is **layered** (wide inspiration from Wipefest): standardized bucket defaults + bespoke per-boss detectors + user classification, all converging on `rules.mechanic_criterion`. We use **absolute authored thresholds**, *not* Wipefest's cross-guild percentile scoring — we analyze one guild's local logs, not a population.

Source pipeline (see [`MECHANIC_SOURCE_STRATEGY.md`](MECHANIC_SOURCE_STRATEGY.md)):

```text
Observed spells in current logs
  -> source annotations (journal, boss mods, guides)
  -> standardized buckets + bespoke detectors (seed data)
  -> editable rules
  -> gold rebuild
  -> real failures in encounter preview and failures views
```

## Initiatives

Active, in suggested order:

1. [Real-Data Failure Loop (Avoidable)](initiatives/01-real-data-failure-loop.md) — prove the pipeline end-to-end for avoidable damage.
2. [Mechanic Classification System](initiatives/02-mechanic-classification-system.md) — standardized buckets + bespoke detectors + seed data.
3. [User Mechanic Classification UI](initiatives/03-user-classification-ui.md) — operator authoring/overrides + `unavoidable` suppression.
4. [Fact Semantics Expansion](initiatives/04-fact-semantics-expansion.md) — real facts for non-avoidable buckets.

Parallel: [Public Gold Mirror](PUBLIC_MIRROR_DESIGN.md) — hosted read-only mirror of gold facts for raid members.

Completed: [Medallion Foundation](historical/initiative-medallion-foundation.md) (archived).

## Additional Fact Semantics

`gold.fact_failure` currently supports:

- `avoidable`: player damage taken by matching spell and threshold,
- `interrupt`: missed interrupt facts, currently limited by known silver semantics gaps.

Avoidable is the first real-data target because the local logs already have `silver.damage_taken` and `silver.damage_taken_event`. Interrupt comes next after the `#61` tightening (Initiative 4). Other mechanic types should remain visible as observed/annotated rows until their fact semantics are defensible.

## Guiding Constraints

- Keep combat logs the primary truth for what appears in the user's data.
- Prefer observed spell previews over hidden source-row queues.
- Prefer direct editable rules over durable source-row review/override workflow.
- Prefer gold rebuilds when rules or gold logic changes.
- Do not reintroduce `public.mechanic_criteria` or analyzer-cache tabs.
- Keep raw combat-log bronze separate from patch/source-data bronze.
- Keep UI labels honest about whether a row is observed data, a source annotation, an editable rule, or a rebuilt failure fact.
- Use absolute authored thresholds, not cross-guild percentile scoring (we are not Wipefest here — single-guild logs).

## Source-Data Direction

DBM, BigWigs, WowAnalyzer, Blizzard journal data, Warcraft Logs, MRT reminders, WeakAuras, and guide sites are **source annotations** — they help explain and classify spells that appear in local logs. They are **not** independent truth that should silently create failure facts. Existing DBM/WowAnalyzer source-data tables may remain as parsed evidence while useful; new user-facing work should avoid source-row review language and prefer observed mechanics, source annotations, rule status, and direct editable rules.
