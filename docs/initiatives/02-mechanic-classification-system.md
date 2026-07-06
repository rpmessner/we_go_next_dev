# Initiative 2 — Mechanic Classification System

Status: **Next.** Linear: [WE / 2. Mechanic Classification System](https://linear.app/we-go-next/project/2-mechanic-classification-system-8c43be579b03) (WE-17…19).

## Goal

Build a **layered, data-driven classification system**: standardized mechanic
buckets with default classifications, plus a framework for bespoke per-boss
detectors, all expressed as editable `rules.mechanic_criterion` rows. Adapts
Wipefest's declarative
[`EventConfigs`](https://github.com/JoshYaxley2/Wipefest.EventConfigs) model to
our medallion.

The former avoidable-only real-data loop is folded into this work as a smoke
test, not a separate product path: one real current-tier avoidable mechanic must
prove observed -> rule -> rebuild -> fact -> UI after the classification model is
in place.

## Model (Wipefest-inspired)

- **Standardized buckets** = our `mechanic_type` taxonomy (`avoidable`, `soak`, `spread`, `stack`, `interrupt`, `targeted_cone`, tank/healer) as reusable defaults — analogous to Wipefest's shared `general/raid.json`.
- **Bespoke per-boss detectors** = richer threshold/evidence configs for unique mechanics; `targeted_cone` (Dread Breath: marker spell + impact ids + collateral roles) is the prototype to generalize. Detectors should model evidence families, not only one display spell: marker debuffs, cast spells, impact damage, follow-up debuffs, periodic ticks, and known unavoidable/background effects may all belong to one mechanic.
- **Code catalogs are *seed data*, not a rival philosophy:** `WeGoNext.GameData.Raids.*` seeds rows that the user UI (Initiative 3) later edits. Standardized defaults, bespoke detectors, and user tags are three input paths to one table.

## Tickets

- **Define current-tier raid mechanics as declarative configs / seed data** (roadmap #69) — author current-tier mechanics in `GameData.Raids.*`; treat DBM/WowAnalyzer/journal as optional scaffolding; sync curated modules into editable rules; prune standalone extraction tooling.
- **Formalize the standardized bucket taxonomy + defaults** — make the `mechanic_type` classifiers data-driven with default thresholds; document which buckets are fact-eligible today (`avoidable`, `interrupt`) vs pending semantics (Initiative 4).
- **Bespoke per-boss detector framework** — generalize the `targeted_cone` evidence pattern (marker / impact / role / collateral) so other unique mechanics can declare evidence without bespoke code per boss.
- **Actionability and noise model** — support `irrelevant` and
  `unavoidable/background` classifications alongside failure mechanics so
  encounter views can hide or de-emphasize rows like unavoidable rot while still
  retaining the observations.
- **Evidence completeness checks** — for a declared mechanic, the observed UI
  should be able to show which expected evidence was seen and which was missing.
  This is how we catch gaps such as a likely `Void Fall` hit family not appearing
  in the mechanic/failure surfaces.
- **Avoidable loop smoke test** — use one observed current-tier avoidable damage
  mechanic to verify the model can sync an editable rule, rebuild
  `gold.fact_failure`, and show real player failures in the UI without SQL/IEx.

## Acceptance

Current-tier mechanics for at least one full boss are expressible as standardized-bucket + bespoke configs that seed editable rules, and the taxonomy + per-bucket fact-eligibility is documented.

The resulting observed/mechanic views distinguish actionable player mistakes,
expected raid damage, irrelevant spell/debuff noise, and missing evidence.

At least one real imported current-tier pull shows avoidable-damage player
failures through the full classified-rule rebuild path.

## Downstream Consumers

- Initiative 5 uses this taxonomy and bespoke detector metadata to label
  mechanic sections in gold encounter detail.
- Initiative 6 mirrors those gold detail sections publicly after Initiative 5
  exposes them.

Do not put encounter-detail storage or public upload concerns in this initiative.
This initiative defines mechanic meaning and rule seed shape.

## Related

[`../ROADMAP.md`](../ROADMAP.md) · [`../MECHANIC_SOURCE_STRATEGY.md`](../MECHANIC_SOURCE_STRATEGY.md) · [Initiative 5](05-gold-encounter-detail.md) · Wipefest `EventConfigs` (reference only)
