# Roadmap

This roadmap tracks the current board direction at a durable level. The task board remains the source of truth for exact status and dependencies.

## Current Focus

The backend medallion foundation and first operator controls are in place:

- bronze combat-log provenance and live/archive reconciliation,
- silver encounter-grain projections,
- gold dimensions and `fact_failure`,
- rules schema and criterion snapshot promotion,
- source-data/DBM ingestion groundwork,
- gold rebuild boundary via `WeGoNext.Gold.RebuildEncounter`,
- rules bootstrap/promotion and rebuild/reimport controls,
- gold-backed `/failures` and `/encounters/:id` LiveViews.

The immediate problem is correctness and operability with real logs. Users need to understand and control rules, rebuilds, empty states, and stale derived data without dropping to IEx or SQL. Before expanding source-data inference or mechanic coverage, close the places where current derived rows can overstate meaning: mutable rule snapshots, interrupt observations labeled like confirmed missed opportunities, and invisible projection/builder versions.

## Near-Term Execution Order

1. `#60 Make promoted rule snapshots version-immutable`
   - prevent existing fact rows from silently changing meaning after re-promotion,
   - key promoted criterion snapshots by authored rule plus ruleset version,
   - bump authored versions when fact-facing rule meaning changes.

2. `#61 Tighten missed-interrupt silver semantics`
   - stop treating every NPC `SPELL_CAST_SUCCESS` as a confirmed failed interrupt opportunity,
   - keep silver as observed cast data and classify missed interrupts in the gold/rules builder,
   - update encounter-detail labels/counts so they do not imply more confidence than the data has.

3. `#62 Stamp silver projections and gold fact builders with versions`
   - make projection/fact derivation versions visible,
   - support stale-data diagnostics after silver or gold logic changes,
   - give operators a clear rebuild/reimport explanation.

4. `#54 Surface data readiness diagnostics in failures UI`
   - explain no active ruleset,
   - explain no promoted criteria,
   - explain no matching silver observations,
   - explain no/stale gold facts,
   - call out known semantic limits until #61 and #62 land.

5. `#63 Add player encounter performance fact`
   - add the missing pull-over-pull trend read model,
   - summarize player damage, deaths, mechanic failures, and duration/time-alive context,
   - support the product question "are we improving on this encounter?"

These tasks are the current correctness path. They make the frontend capable of driving and explaining the warehouse without presenting overbroad silver observations or mutable rule snapshots as stable analytic facts.

## Source-Data and Rule Inference Path

After the correctness path is underway, source-data inference should proceed as evidence intake, not rule activation:

1. `#59 Replace DBM regex parsing with structured Lua parsing` - implemented as a focused static Lua declaration parser
2. `#36 Add DBM Bulk Source Import`
3. `#37 Ingest Spell and Encounter Reference Metadata`
4. `#58 Add WowAnalyzer timeline source import` - implemented as provenance-tracked source evidence
5. `#38 Build Inferred Mechanic Candidate Read Model`
6. `#39 Persist Candidate Overrides Across Refreshes`
7. `#40 Cross-Reference Candidates With Observed Silver Events`
8. `#41 Build Mechanic Candidate Review UI`
9. `#42 Promote Accepted Candidates Into Draft Rules`
10. `#43 Add Source-Data Build Diff Review`

DBM and WowAnalyzer imports should converge on comparable provenance and review semantics. They can suggest candidates, but they must not write active rules, promoted gold criterion snapshots, or facts directly.

## Additional Fact Semantics

`#44 Define Additional Mechanic Fact Semantics` remains intentionally blocked until:

- accepted candidates can become draft rules,
- the gold rebuild orchestrator exists,
- rules/facts have patch/build validity metadata.

Avoidable and interrupt semantics are implemented today as proof-of-concept fact builders, but both should stay conservative. Do not expand avoidable semantics until defensive/immunity/buff windows from `#64 Add defensive buff window silver observations` or equivalent evidence exist. Do not expand interrupt coverage until `#61` moves missed-interrupt classification out of overbroad silver rows and into criteria-backed gold logic.

Soak, spread, stack, tank, healer, dispel, deaths, and interrupt coverage should be added only when the supporting silver grain and fact semantics are defensible.

Event-grain silver expansion should stay tied to these fact and review workflows. `silver.damage_taken_event` is allowed because rule review and classifier evidence need individual damage hits. Do not add broad player-damage, healing, cast, aura, or resource event tables without a specific fact/read-model need and a volume plan.

## Guiding Constraints

- Do not reintroduce `public.mechanic_criteria` or analyzer-cache tabs.
- Do not write active rules or gold facts directly from source-data inference.
- Keep raw combat-log bronze separate from patch/source-data bronze.
- Do not rebuild a generic raw-event warehouse under silver; event-grain silver rows require a named downstream workflow.
- Keep silver observation names and UI labels honest; classification belongs in rules/gold builders unless the silver row is truly authored intent.
- Do not mutate promoted criterion snapshots in a way that changes the meaning of existing fact rows.
- Prefer gold rebuilds over log reparse when only rules or gold logic changed.
- Prefer force reimport over ad hoc database edits when silver or parser logic changed.
