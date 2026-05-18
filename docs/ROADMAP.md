# Roadmap

This roadmap tracks the current board direction at a durable level. The task board remains the source of truth for exact status and dependencies.

## Current Focus

The backend medallion foundation is in place:

- bronze combat-log provenance and live/archive reconciliation,
- silver encounter-grain projections,
- gold dimensions and `fact_failure`,
- rules schema and criterion snapshot promotion,
- source-data/DBM ingestion groundwork,
- gold rebuild boundary via `WeGoNext.Gold.RebuildEncounter`,
- first gold-backed `/failures` LiveView.

The immediate problem is operability with real logs. Users need to understand and control rules, rebuilds, and empty states without dropping to IEx or SQL. The roadmap is no longer launch-date driven; it is organized around making the medallion frontend useful, then expanding fact/dimension/criterion coverage from real evidence.

## Near-Term Execution Order

1. `#52 Add rules status and bootstrap UI`
   - show active ruleset status,
   - show authored and promoted criterion counts,
   - seed bundled rules,
   - activate/promote rules.

2. `#53 Add medallion rebuild and recompute controls`
   - rebuild gold facts from existing silver rows,
   - expose force-reimport guidance,
   - make recompute actions explicit and scoped.

3. `#54 Surface data readiness diagnostics in failures UI`
   - explain no active ruleset,
   - explain no promoted criteria,
   - explain no matching silver observations,
   - explain no/stale gold facts.

4. `#48 Key medallion encounter views by gold encounter identity`
   - make UI navigation use `gold.dim_encounter.id` where appropriate.

5. `#51 Fence remaining legacy analyzers behind reference-only boundaries`
   - keep legacy analyzers available for comparison/research,
   - prevent new UI from depending on analyzer cache or legacy public criteria.

6. `#32 Build medallion encounter detail shell`
   - build replacement encounter detail UI against silver/gold/rules read models.

These tasks are the current product path. They should make the frontend capable of driving the warehouse instead of merely displaying whatever the backend happened to compute.

## Source-Data and Rule Inference Path

After the real-data operator path is usable:

1. `#49 Add conformed spell and encounter reference dimensions`
2. `#50 Add patch and build validity metadata to rules and facts`
3. `#36 Add DBM Bulk Source Import`
4. `#37 Ingest Spell and Encounter Reference Metadata`
5. `#38 Build Inferred Mechanic Candidate Read Model`
6. `#39 Persist Candidate Overrides Across Refreshes`
7. `#40 Cross-Reference Candidates With Observed Silver Events`
8. `#41 Build Mechanic Candidate Review UI`
9. `#42 Promote Accepted Candidates Into Draft Rules`
10. `#43 Add Source-Data Build Diff Review`

## Additional Fact Semantics

`#44 Define Additional Mechanic Fact Semantics` remains intentionally blocked until:

- accepted candidates can become draft rules,
- the gold rebuild orchestrator exists,
- rules/facts have patch/build validity metadata.

Avoidable and interrupt semantics are implemented today. Soak, spread, stack, tank, healer, dispel, deaths, and interrupt coverage should be added only when the supporting silver grain and fact semantics are defensible.

Event-grain silver expansion should stay tied to these fact and review workflows. `silver.damage_taken_event` is allowed because rule review and classifier evidence need individual damage hits. Do not add broad player-damage, healing, cast, aura, or resource event tables without a specific fact/read-model need and a volume plan.

## Guiding Constraints

- Do not reintroduce `public.mechanic_criteria` or analyzer-cache tabs.
- Do not write active rules or gold facts directly from source-data inference.
- Keep raw combat-log bronze separate from patch/source-data bronze.
- Do not rebuild a generic raw-event warehouse under silver; event-grain silver rows require a named downstream workflow.
- Prefer gold rebuilds over log reparse when only rules or gold logic changed.
- Prefer force reimport over ad hoc database edits when silver or parser logic changed.
