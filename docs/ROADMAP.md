# Roadmap

This roadmap tracks the current board direction at a durable level. The task
board remains the source of truth for exact status and dependencies.

## Current Focus

The backend medallion foundation and first operator controls are in place:

- bronze combat-log provenance and live/archive reconciliation,
- silver encounter-grain projections,
- gold dimensions and `fact_failure`,
- rules schema and criterion snapshot promotion,
- source-data ingestion groundwork for DBM and WowAnalyzer,
- gold rebuild boundary via `WeGoNext.Gold.RebuildEncounter`,
- rules bootstrap/promotion and rebuild/reimport controls,
- gold-backed `/failures` and `/encounters/:id` LiveViews.

The immediate product problem is not more source-row workflow. The product needs
real current-tier mechanics from the imported logs to become editable rules, then
recomputed facts, then visible failures in the preview/detail UI.

The source strategy is documented in
[`MECHANIC_SOURCE_STRATEGY.md`](MECHANIC_SOURCE_STRATEGY.md). In short:

```text
Observed spells in current logs
  -> source annotations from journal, boss mods, guide/reminder sources
  -> code-defined raid mechanic catalogs
  -> synced editable rules for supported semantics
  -> gold rebuild
  -> real failures in encounter preview and failures views
```

## Near-Term Execution Order

1. `#69 Define Raid Mechanics As Code And Prune Extraction Tooling`
   - define current-tier raid mechanics in `WeGoNext.GameData.Raids.*`,
   - use AI-assisted research, observed logs, and source annotations to scaffold
     code entries,
   - treat DBM/WowAnalyzer/journal tooling as optional scaffolding helpers,
   - sync curated code modules into editable rules.

2. `#40 Match Source Mechanics Against Current Silver Observations`
   - rename in implementation toward observed mechanics/source annotations,
   - list spells that actually appear in imported current-tier logs,
   - attach DBM/WowAnalyzer/reference metadata as annotations,
   - show counts, affected players, damage, debuffs, casts, interrupts, and
     encounter scope.

3. `#42 Import Matched Source Mechanics Directly Into Rules`
   - sync editable rules from code-defined observed mechanics with strong source
     support,
   - dedupe by active ruleset, spell, encounter scope, difficulty scope, and
     mechanic type,
   - skip separate source-row review/override state as product workflow.

4. `#66 Import Matched Avoidable Damage Rules And Rebuild Facts`
   - ship the first complete real-data loop for avoidable damage,
   - default imported avoidable rules to `threshold.max_hits = 0`,
   - promote active rules and rebuild `gold.fact_failure`,
   - verify real player failures appear from imported logs.

5. `#67 Show Real Failure Preview On Encounter Detail`
   - display rule-backed failure facts for the selected pull,
   - include player, spell/mechanic, count, damage, and source annotations,
   - make empty states point to the exact missing step.

6. `#61 Tighten Interrupt Silver Semantics For Real Rule Imports`
   - stop presenting broad NPC cast-success observations as confirmed missed
     interrupts,
   - import interrupt rules only once the supporting observation is trustworthy,
   - keep labels honest until then.

7. `#44 Expand Fact Semantics For Source-Imported Mechanics`
   - add soak, spread, stack, tank, healer, dispel, and defensive semantics only
     after the supporting silver grain exists,
   - do not auto-create failure rules for unsupported semantics.

## Source-Data Direction

DBM, BigWigs, WowAnalyzer, Blizzard journal data, Warcraft Logs, MRT reminders,
WeakAuras, and guide sites should be treated as source annotations. They help
explain and classify spells that appear in local logs. They are not independent
truth that should silently create failure facts.

Existing DBM/WowAnalyzer source-data tables may remain as parsed source rows
while they are useful, but new user-facing work should avoid source-row review
language. Prefer:

- observed mechanics,
- source annotations,
- rule status,
- direct editable rules.

## Additional Fact Semantics

`gold.fact_failure` currently supports:

- `avoidable`: player damage taken by matching spell and threshold,
- `interrupt`: missed interrupt facts, currently limited by known silver
  semantics gaps.

Avoidable damage is the first real-data target because the local logs already
have `silver.damage_taken` and `silver.damage_taken_event`. Interrupts come next
after `#61`. Other mechanic types should remain visible as observed/annotated
rows until their fact semantics are defensible.

## Guiding Constraints

- Keep combat logs as the primary truth for what appears in the user's data.
- Prefer observed spell previews over hidden source-row queues.
- Prefer direct editable rules over durable source-row review/override workflow.
- Prefer gold rebuilds when rules or gold logic changes.
- Do not reintroduce `public.mechanic_criteria` or analyzer-cache tabs.
- Keep raw combat-log bronze separate from patch/source-data bronze.
- Keep UI labels honest about whether a row is observed data, a source
  annotation, an editable rule, or a rebuilt failure fact.
