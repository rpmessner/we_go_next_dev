# Initiative 3 — User Mechanic Classification UI

Status: **Planned.** Linear: [WE / 3. User Mechanic Classification UI](https://linear.app/we-go-next/project/3-user-mechanic-classification-ui-df49eebbd196) (WE-20…22).

## Goal

Recover the operator capability lost in the legacy system: a UI to classify observed combat-log events (damage / debuff / cast) into mechanic buckets on **any** encounter — including never-seen bosses — writing editable `rules.mechanic_criterion` rows that rebuild into `fact_failure`. The Wipefest-style authoring surface over our rules layer. (The legacy click-to-classify UI was pruned with `public.mechanic_criteria`; this rebuilds it on the medallion backbone.)

## Scope

- **Classify-from-observation UI** — from the observed/mechanic read model
  defined by Initiative 2, let the operator tag a spell/debuff as `avoidable` /
  `soak` / `spread` / `stack` / `interrupt` / etc., creating or updating a rule
  with the bucket's default threshold.
  - Classification starts from impact-rich rows, not raw spell names. The row
    should show who was hit, hit count, total damage, top damaged players,
    encounter/pull scope, and evidence type before asking the operator to tag it.
  - The UI must support marking observed debuffs/spells as irrelevant to the
    analysis page, not only converting them into failure mechanics.
- **`unavoidable` suppression** — a distinct, **non-failure** tag (an allowlist), marking damage as expected so it is excluded from avoidable-failure surfacing. Cuts false positives on new bosses. Requires a suppression flag honored by the avoidable fact builder. **Not** a `mechanic_type` — model it separately.
- **Noise suppression in detail views** — unavoidable rot, background aura ticks,
  and irrelevant debuffs should stop dominating damage/debuff views once tagged.
  Suppression must preserve the underlying observations for audit/debugging, but
  the default encounter analysis should emphasize actionable mechanics and
  outliers.
- **Edit / override + rebuild** — edit thresholds/scope on existing rules and trigger a gold rebuild from the UI; keep labels honest (observed data vs editable rule vs rebuilt fact).

## Constraints

- Build on `rules.mechanic_criterion` + `WeGoNext.Gold.RebuildEncounter`; **never** reintroduce `public.mechanic_criteria` or analyzer-cache tabs.
- Be honest about **tag-now / facts-later**: buckets without fact semantics yet (Initiative 4) author rules but emit no failures until their semantics land. The UI must say so.

## Acceptance

On an imported pull for an unseen boss, an operator can tag one observed damage spell as `avoidable` and another as `unavoidable`, rebuild, and see the resulting failures (and the suppression) in the UI — no code change, no SQL.

The same flow must work for debuffs: an operator can mark a debuff as irrelevant,
unavoidable/background, or a specific mechanic type, and the encounter detail
view updates its default presentation accordingly.

## Related

[`../ROADMAP.md`](../ROADMAP.md) · [Initiative 2](02-mechanic-classification-system.md) · [Initiative 4](04-fact-semantics-expansion.md) · [Initiative 5](05-gold-encounter-detail.md) · [Initiative 6](06-public-analysis-mirror.md)
