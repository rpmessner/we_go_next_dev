# Initiative 3 — User Mechanic Classification UI

Status: **Planned.** Linear: [WE / 3. User Mechanic Classification UI](https://linear.app/we-go-next/project/3-user-mechanic-classification-ui-df49eebbd196) (WE-20…22).

## Goal

Recover the operator capability lost in the legacy system: a UI to classify observed combat-log events (damage / debuff / cast) into mechanic buckets on **any** encounter — including never-seen bosses — writing editable `rules.mechanic_criterion` rows that rebuild into `fact_failure`. The Wipefest-style authoring surface over our rules layer. (The legacy click-to-classify UI was pruned with `public.mechanic_criteria`; this rebuilds it on the medallion backbone.)

## Scope

- **Classify-from-observation UI** — from the observed-events read model (Initiative 1, #40), let the operator tag a spell/debuff as `avoidable` / `soak` / `spread` / `stack` / `interrupt` / etc., creating or updating a rule with the bucket's default threshold.
- **`unavoidable` suppression** — a distinct, **non-failure** tag (an allowlist), marking damage as expected so it is excluded from avoidable-failure surfacing. Cuts false positives on new bosses. Requires a suppression flag honored by the avoidable fact builder. **Not** a `mechanic_type` — model it separately.
- **Edit / override + rebuild** — edit thresholds/scope on existing rules and trigger a gold rebuild from the UI; keep labels honest (observed data vs editable rule vs rebuilt fact).

## Constraints

- Build on `rules.mechanic_criterion` + `WeGoNext.Gold.RebuildEncounter`; **never** reintroduce `public.mechanic_criteria` or analyzer-cache tabs.
- Be honest about **tag-now / facts-later**: buckets without fact semantics yet (Initiative 4) author rules but emit no failures until their semantics land. The UI must say so.

## Acceptance

On an imported pull for an unseen boss, an operator can tag one observed damage spell as `avoidable` and another as `unavoidable`, rebuild, and see the resulting failures (and the suppression) in the UI — no code change, no SQL.

## Related

[`../ROADMAP.md`](../ROADMAP.md) · [Initiative 1](01-real-data-failure-loop.md) · [Initiative 4](04-fact-semantics-expansion.md) · [Public Gold Mirror](../PUBLIC_MIRROR_DESIGN.md) (read-only mirror consumes the resulting facts)
