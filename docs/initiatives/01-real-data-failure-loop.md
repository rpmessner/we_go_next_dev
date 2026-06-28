# Initiative 1 — Real-Data Failure Loop (Avoidable)

Status: **Active / next.** Linear: [WE / 1. Real-Data Failure Loop (Avoidable)](https://linear.app/we-go-next/project/1-real-data-failure-loop-avoidable-ab93ba29c143) (WE-13…16).

## Goal

Prove the full real-data pipeline end-to-end for one mechanic type — **avoidable damage**: a spell observed in imported logs → editable rule → gold rebuild → `fact_failure` → visible failure in the UI. The smallest vertical that proves the medallion loop works over real combat logs, with no SQL/IEx.

## Why first

The authoring surfaces (Initiatives 2–3) and extra fact types (Initiative 4) are only meaningful once one mechanic type flows cleanly from log to UI. Avoidable is the natural first target: `silver.damage_taken` / `silver.damage_taken_event` already exist, and two seed rules (Arcane Expulsion, Void Burst) are already seeded.

## Tickets

- **Match observed mechanics against current silver observations** (roadmap #40) — read model listing spells that actually appear in imported current-tier logs, with counts, affected players, damage, debuffs, casts, interrupts, and encounter scope. Rename implementation toward "observed mechanics / source annotations."
- **Import matched mechanics directly into rules** (roadmap #42) — sync editable `rules.mechanic_criterion` rows from observed mechanics with strong support; dedupe by active ruleset, spell, encounter/difficulty scope, mechanic type; no separate source-row review state.
- **Import matched avoidable rules & rebuild facts** (roadmap #66) — the first complete loop: default imported avoidable rules to `threshold.max_hits = 0`, promote the active ruleset, rebuild `gold.fact_failure`, verify real player failures appear.
- **Show real failure preview on encounter detail** (roadmap #67) — display rule-backed failure facts for the selected pull (player, spell/mechanic, count, damage, source annotations); empty states point to the exact missing step.

## Initiative-level acceptance

A real imported current-tier pull shows real avoidable-damage player failures in the UI, produced entirely through observed → rule → rebuild → fact — no SQL, no IEx.

## Related

[`../ROADMAP.md`](../ROADMAP.md) · [`../MECHANIC_SOURCE_STRATEGY.md`](../MECHANIC_SOURCE_STRATEGY.md) · [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
