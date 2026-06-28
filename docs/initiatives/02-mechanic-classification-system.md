# Initiative 2 — Mechanic Classification System

Status: **Planned.** Linear: [WE / 2. Mechanic Classification System](https://linear.app/we-go-next/project/2-mechanic-classification-system-8c43be579b03) (WE-17…19).

## Goal

Generalize from the single avoidable vertical to a **layered, data-driven classification system**: standardized mechanic buckets with default classifications, plus a framework for bespoke per-boss detectors — all expressed as editable `rules.mechanic_criterion` rows. Adapts Wipefest's declarative [`EventConfigs`](https://github.com/JoshYaxley2/Wipefest.EventConfigs) model to our medallion.

## Model (Wipefest-inspired)

- **Standardized buckets** = our `mechanic_type` taxonomy (`avoidable`, `soak`, `spread`, `stack`, `interrupt`, `targeted_cone`, tank/healer) as reusable defaults — analogous to Wipefest's shared `general/raid.json`.
- **Bespoke per-boss detectors** = richer threshold/evidence configs for unique mechanics; `targeted_cone` (Dread Breath: marker spell + impact ids + collateral roles) is the prototype to generalize.
- **Code catalogs are *seed data*, not a rival philosophy:** `WeGoNext.GameData.Raids.*` seeds rows that the user UI (Initiative 3) later edits. Standardized defaults, bespoke detectors, and user tags are three input paths to one table.

## Tickets

- **Define current-tier raid mechanics as declarative configs / seed data** (roadmap #69) — author current-tier mechanics in `GameData.Raids.*`; treat DBM/WowAnalyzer/journal as optional scaffolding; sync curated modules into editable rules; prune standalone extraction tooling.
- **Formalize the standardized bucket taxonomy + defaults** — make the `mechanic_type` classifiers data-driven with default thresholds; document which buckets are fact-eligible today (`avoidable`, `interrupt`) vs pending semantics (Initiative 4).
- **Bespoke per-boss detector framework** — generalize the `targeted_cone` evidence pattern (marker / impact / role / collateral) so other unique mechanics can declare evidence without bespoke code per boss.

## Acceptance

Current-tier mechanics for at least one full boss are expressible as standardized-bucket + bespoke configs that seed editable rules, and the taxonomy + per-bucket fact-eligibility is documented.

## Related

[`../ROADMAP.md`](../ROADMAP.md) · [`../MECHANIC_SOURCE_STRATEGY.md`](../MECHANIC_SOURCE_STRATEGY.md) · Wipefest `EventConfigs` (reference only)
