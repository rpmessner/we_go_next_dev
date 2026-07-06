# Initiatives

Each initiative is a focused workstream with its own doc here and a Linear **project** on the **WE** board (workspace `we-go-next`). These docs hold scope/rationale; the board holds exact status.

## Background model

Mechanic detection is **layered** (wide inspiration from [Wipefest](https://www.wipefest.gg/)'s declarative [`EventConfigs`](https://github.com/JoshYaxley2/Wipefest.EventConfigs) model):

- **standardized bucket defaults** (our `mechanic_type` taxonomy, reusable across bosses — Wipefest's shared `general/raid.json` analog),
- **bespoke per-boss detectors** (richer evidence configs; `targeted_cone` is the prototype),
- **user classification** (operator tagging/overrides on top),

all converging on editable `rules.mechanic_criterion` rows → gold rebuild → `fact_failure`. We deliberately use **absolute authored thresholds**, *not* Wipefest's cross-guild percentile scoring — we analyze one guild's local logs, not a population. See [`../ROADMAP.md`](../ROADMAP.md).

## Active (suggested order)

| # | Initiative | Status | Linear |
|---|---|---|---|
| 1 | [Mechanic Classification System](02-mechanic-classification-system.md) | next | [WE-17…19](https://linear.app/we-go-next/project/2-mechanic-classification-system-8c43be579b03) |
| — | [Real-Data Failure Loop (Avoidable)](01-real-data-failure-loop.md) | absorbed into mechanic classification/user UI | [WE-13…16](https://linear.app/we-go-next/project/1-real-data-failure-loop-avoidable-ab93ba29c143) |
| 2 | [User Mechanic Classification UI](03-user-classification-ui.md) | planned | [WE-20…22](https://linear.app/we-go-next/project/3-user-mechanic-classification-ui-df49eebbd196) |
| 3 | [Fact Semantics Expansion](04-fact-semantics-expansion.md) | planned | [WE-23…24](https://linear.app/we-go-next/project/4-fact-semantics-expansion-490c13fac081) |
| 4 | [Gold Encounter Detail Read Models](05-gold-encounter-detail.md) | planned | not yet split |
| 5 | [Public Analysis Mirror](06-public-analysis-mirror.md) | plumbing built; product gated by #4 | [WE / Public Gold Mirror](https://linear.app/we-go-next/project/public-gold-mirror-55ce8feabbb8) |

## Dependency Shape

- Mechanic Classification, User Classification UI, and Fact Semantics Expansion
  define the mechanic/rule/fact pipeline.
- Initiative 5 defines the gold read models and JSON artifacts that the
  encounter detail page should consume.
- Initiative 6 publishes Initiative 5's public-safe JSON artifacts to
  Cloudflare for the hosted app to read.

Gold encounter detail can start before every mechanic type is complete, but
mechanic-specific sections must depend on the relevant fact semantics rather
than inventing frontend-only interpretations.

## Completed (archived)

- [Medallion Foundation](../historical/initiative-medallion-foundation.md) — bronze/silver/gold/rules backbone, gold rebuild boundary, gold-backed `/failures` + `/encounters/:id`.
