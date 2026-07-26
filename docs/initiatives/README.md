# Initiatives

Each initiative is a focused workstream with its own doc here and an **epic bead** in the in-repo tracker (`bd`, `.beads/`). These docs hold scope/rationale; beads holds exact status. (Linear team WE is a frozen archive since 2026-07-19; `WE-###` ids live on as `we-###` beads.)

## Background model

Mechanic detection is **layered** (wide inspiration from [Wipefest](https://www.wipefest.gg/)'s declarative [`EventConfigs`](https://github.com/JoshYaxley2/Wipefest.EventConfigs) model):

- **standardized bucket defaults** (our `mechanic_type` taxonomy, reusable across bosses — Wipefest's shared `general/raid.json` analog),
- **bespoke per-boss detectors** (richer evidence configs; `targeted_cone` is the prototype),
- **user classification** (operator tagging/overrides on top),

all converging on editable `rules.mechanic_criterion` rows → gold rebuild → `fact_failure`. We deliberately use **absolute authored thresholds**, *not* Wipefest's cross-guild percentile scoring — we analyze one guild's local logs, not a population. See [`../ROADMAP.md`](../ROADMAP.md).

## Active (suggested order)

| # | Initiative | Status | Beads |
|---|---|---|---|
| 7 | [Defensives & Consumables (Raid-Lead Questions)](07-defensives-and-consumables.md) | **active — current top priority** | `we-i7` (we-37…41) |
| — | [Real-Data Failure Loop (Avoidable)](01-real-data-failure-loop.md) | absorbed into mechanic classification/user UI | `we-i1` (we-13…16) |
| 2 | [Mechanic Classification System](02-mechanic-classification-system.md) | next | `we-i2` (we-17…19) |
| 3 | [User Mechanic Classification UI](03-user-classification-ui.md) | planned | `we-i3` (we-20…22) |
| 4 | [Fact Semantics Expansion](04-fact-semantics-expansion.md) | planned | `we-i4` (we-23…24) |
| 5 | [Encounter Document Read Models](05-encounter-documents.md) | in progress — implementation complete on branch; review/merge pending | `we-i5` (we-25, we-27…30, we-35) |
| 6 | [Public Analysis Mirror](06-public-analysis-mirror.md) | in progress — implementation complete on branch; R2/deployed smoke pending | `we-i6` (we-31…34, we-36; we-11…12 carried forward) |
| — | [Public Gold Mirror](../PUBLIC_MIRROR_DESIGN.md) | **superseded** by 5–6 (built through we-12) | `we-i0` (we-5…10) |

## Dependency Shape

- Mechanic Classification, User Classification UI, and Fact Semantics Expansion
  define the mechanic/rule/fact pipeline.
- Initiative 5 defines the encounter documents the frontend renders from —
  the generator serializes existing read models at build time.
- Initiative 6 uploads opted-in documents to a private R2 bucket for the
  hosted app to read.

Encounter document work can start before every mechanic type is complete, but
mechanic-specific sections must depend on the relevant fact semantics rather
than inventing frontend-only interpretations.

## Completed (archived)

- [Medallion Foundation](../historical/initiative-medallion-foundation.md) — bronze/silver/gold/rules backbone, gold rebuild boundary, gold-backed `/failures` + `/encounters/:id`.
