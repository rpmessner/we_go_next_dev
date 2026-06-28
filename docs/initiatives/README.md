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
| 1 | [Real-Data Failure Loop (Avoidable)](01-real-data-failure-loop.md) | next | [WE-13…16](https://linear.app/we-go-next/project/1-real-data-failure-loop-avoidable-ab93ba29c143) |
| 2 | [Mechanic Classification System](02-mechanic-classification-system.md) | planned | [WE-17…19](https://linear.app/we-go-next/project/2-mechanic-classification-system-8c43be579b03) |
| 3 | [User Mechanic Classification UI](03-user-classification-ui.md) | planned | [WE-20…22](https://linear.app/we-go-next/project/3-user-mechanic-classification-ui-df49eebbd196) |
| 4 | [Fact Semantics Expansion](04-fact-semantics-expansion.md) | planned | [WE-23…24](https://linear.app/we-go-next/project/4-fact-semantics-expansion-490c13fac081) |
| — | [Public Gold Mirror](../PUBLIC_MIRROR_DESIGN.md) | planned | [WE / Public Gold Mirror](https://linear.app/we-go-next/project/public-gold-mirror-55ce8feabbb8) |

## Completed (archived)

- [Medallion Foundation](../historical/initiative-medallion-foundation.md) — bronze/silver/gold/rules backbone, gold rebuild boundary, gold-backed `/failures` + `/encounters/:id`.
