# Initiative 4 — Fact Semantics Expansion

Status: **Planned (ongoing).** Linear: [WE / 4. Fact Semantics Expansion](https://linear.app/we-go-next/project/4-fact-semantics-expansion-490c13fac081) (WE-23…24).

## Goal

Give the non-avoidable buckets real `fact_failure` semantics, one type at a time, **only where the supporting silver grain is defensible**. This unblocks meaningful user tagging (Initiative 3) and broader coaching, without manufacturing failure facts the data can't support.

## Tickets

- **Tighten interrupt silver semantics for real rule imports** (roadmap #61) — stop presenting broad NPC cast-success observations as confirmed missed interrupts; import interrupt rules only once the supporting observation is trustworthy; keep labels honest until then. (`silver.interrupt_opportunity` is currently overbroad — task to tighten/reframe it.)
- **Expand fact semantics for source-imported mechanics** (roadmap #44) — add `soak`, `spread`, `stack`, `tank`, `healer`, `dispel`, `defensive` semantics only after the supporting silver grain exists; do not auto-create failure rules for unsupported semantics.

## Sequencing

Interrupt (#61) is next after the avoidable loop. The rest (#44) are gated per-type on silver grain and should split into per-type tickets when each becomes active — do not pre-create failing rules for types without semantics.

Initiative 5 can build non-mechanic gold encounter detail sections before all of
these fact types exist. It should depend on this initiative only for
mechanic-specific failure sections.

## Acceptance (per type)

A mechanic type emits correct `fact_failure` rows from a real pull, with a documented silver grain backing it, **before** it is offered as a user-taggable failing bucket.

## Related

[`../ROADMAP.md`](../ROADMAP.md) · [`../ARCHITECTURE.md`](../ARCHITECTURE.md) (silver grain) · [Initiative 3](03-user-classification-ui.md) · [Initiative 5](05-gold-encounter-detail.md)
