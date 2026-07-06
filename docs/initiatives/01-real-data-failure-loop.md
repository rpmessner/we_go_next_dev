# Initiative 1 — Real-Data Failure Loop (Avoidable)

Status: **Absorbed into Initiative 2/3.** Linear: [WE / 1. Real-Data Failure Loop (Avoidable)](https://linear.app/we-go-next/project/1-real-data-failure-loop-avoidable-ab93ba29c143) (WE-13…16).

## Decision

Do not treat this as a standalone product initiative. A broad observed-spell
browser plus one-off avoidable import flow is too likely to become low-signal
workflow. The valuable pieces are acceptance constraints for the mechanic system
rewrite:

- observed rows must include player-impact context before classification,
- mechanics need actionability/noise labels such as actionable, irrelevant, and
  unavoidable/background,
- declared mechanics need evidence-completeness diagnostics,
- at least one avoidable mechanic must prove the full
  observed -> rule -> rebuild -> fact -> UI loop.

Those pieces now belong to Initiative 2 (mechanic classification system) and
Initiative 3 (operator classification UI). This file remains as a historical
handoff for the absorbed scope.

## Former Goal

Prove the full real-data pipeline end-to-end for one mechanic type — **avoidable damage**: a spell observed in imported logs → editable rule → gold rebuild → `fact_failure` → visible failure in the UI. The smallest vertical that proves the medallion loop works over real combat logs, with no SQL/IEx.

## Why it was considered first

The authoring surfaces (Initiatives 2–3) and extra fact types (Initiative 4) are only meaningful once one mechanic type flows cleanly from log to UI. Avoidable is the natural first target: `silver.damage_taken` / `silver.damage_taken_event` already exist, and two seed rules (Arcane Expulsion, Void Burst) are already seeded.

## Absorbed tickets

- **Match observed mechanics against current silver observations** (roadmap #40) — read model listing spells that actually appear in imported current-tier logs, with counts, affected players, damage, debuffs, casts, interrupts, and encounter scope. Rename implementation toward "observed mechanics / source annotations."
  - The UI must not be a flat spell/debuff list. Each row needs player impact:
    who was hit, hit counts, total damage, top damaged players, pull coverage,
    and whether the observation is damage, debuff, cast, interrupt, or mixed
    evidence.
  - Damage-heavy unavoidable raid rot such as `Dark Upheaval` must not dominate
    the same view as actionable avoidable/mechanic candidates without labels or
    filtering.
  - Missing expected candidate coverage is a first-class signal: if players were
    hit by a candidate such as `Void Fall` but no row appears, the read model or
    source/mechanic mapping is incomplete and should be diagnosable from the UI.
- **Import matched mechanics directly into rules** (roadmap #42) — sync editable `rules.mechanic_criterion` rows from observed mechanics with strong support; dedupe by active ruleset, spell, encounter/difficulty scope, mechanic type; no separate source-row review state.
- **Import matched avoidable rules & rebuild facts** (roadmap #66) — the first complete loop: default imported avoidable rules to `threshold.max_hits = 0`, promote the active ruleset, rebuild `gold.fact_failure`, verify real player failures appear.
- **Show real failure preview on encounter detail** (roadmap #67) — display rule-backed failure facts for the selected pull (player, spell/mechanic, count, damage, source annotations); empty states point to the exact missing step.

## Absorbed acceptance

A real imported current-tier pull shows real avoidable-damage player failures in
the UI, produced entirely through observed → rule → rebuild → fact — no SQL, no
IEx. The observed-mechanics UI also shows enough player-impact context to decide
whether a spell is actionable, irrelevant, unavoidable, or missing classification.

## Downstream Consumers

Initiative 5 consumes the absorbed acceptance through Initiative 2/3. It should
not block Initiative 5's non-mechanic sections such as roster, deaths, damage
summaries, or debuffs.

## Related

[`../ROADMAP.md`](../ROADMAP.md) · [`../MECHANIC_SOURCE_STRATEGY.md`](../MECHANIC_SOURCE_STRATEGY.md) · [`../ARCHITECTURE.md`](../ARCHITECTURE.md) · [Initiative 5](05-gold-encounter-detail.md)
