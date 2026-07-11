# Roadmap

The durable, high-level index. Each workstream is an **initiative** with its own doc in [`initiatives/`](initiatives/README.md) and a Linear **project** on the **WE** board (workspace `we-go-next`). The board is the source of truth for exact status; the initiative docs hold scope/rationale.

## Direction

Turn observed current-tier mechanics from imported logs into editable rules → rebuilt facts → visible failures, then layer authoring on top. Mechanic detection is **layered** (wide inspiration from Wipefest): standardized bucket defaults + bespoke per-boss detectors + user classification, all converging on `rules.mechanic_criterion`. We use **absolute authored thresholds**, *not* Wipefest's cross-guild percentile scoring — we analyze one guild's local logs, not a population.

Source pipeline (see [`MECHANIC_SOURCE_STRATEGY.md`](MECHANIC_SOURCE_STRATEGY.md)):

```text
Observed spells in current logs
  -> source annotations (journal, boss mods, guides)
  -> standardized buckets + bespoke detectors (seed data)
  -> editable rules
  -> gold rebuild
  -> real failures in encounter preview and failures views
```

## Initiatives

Active, in suggested order:

2. [Mechanic Classification System](initiatives/02-mechanic-classification-system.md) — standardized buckets + bespoke detectors + seed data, with the avoidable real-data loop retained only as a smoke test.
3. [User Mechanic Classification UI](initiatives/03-user-classification-ui.md) — operator authoring/overrides + `unavoidable` suppression.
4. [Fact Semantics Expansion](initiatives/04-fact-semantics-expansion.md) — real facts for non-avoidable buckets.
5. [Encounter Document Read Models](initiatives/05-encounter-documents.md) — per-encounter JSON documents as the medallion's read-model product; frontend renders from documents.
6. [Public Analysis Mirror](initiatives/06-public-analysis-mirror.md) — opted-in documents uploaded to a private R2 bucket; same frontend hosted publicly behind the `/r/:slug` gate.

(Numbers match the initiative file and Linear project numbers; initiative 1 was
absorbed, see below.)

Absorbed: [Real-Data Failure Loop (Avoidable)](initiatives/01-real-data-failure-loop.md).
Its useful pieces are now acceptance constraints inside the mechanic
classification rewrite: impact-rich observations, actionability/noise labels,
evidence-completeness diagnostics, and one avoidable observed -> rule -> rebuild
-> fact -> UI smoke test.

Superseded parallel track: [Public Gold Mirror](PUBLIC_MIRROR_DESIGN.md) (DB-backed mirror, built through WE-12) — replaced by initiatives 5–6 above, see [`ENCOUNTER_DOCUMENTS_DESIGN.md`](ENCOUNTER_DOCUMENTS_DESIGN.md).

Completed: [Medallion Foundation](historical/initiative-medallion-foundation.md) (archived).

## Additional Fact Semantics

`gold.fact_failure` currently supports:

- `avoidable`: player damage taken by matching spell and threshold,
- `interrupt`: missed interrupt facts, currently limited by known silver semantics gaps.

Avoidable is the first real-data target because the local logs already have `silver.damage_taken` and `silver.damage_taken_event`. Interrupt comes next after the `#61` tightening (Initiative 4). Other mechanic types should remain visible as observed/annotated rows until their fact semantics are defensible.

## Encounter Detail Gap

The local encounter detail page currently depends on silver-derived read models
for most useful content: roster, deaths, damage, debuffs, interrupts/casts, and
other pull detail. `gold.fact_failure` alone is not the product analysis page.

Several current local views also expose low-context spell/debuff lists. A row
like "debuff X" or "damage spell Y" is not useful unless the UI shows who was
affected, hit/application counts, total damage, top damaged players, encounter
scope, and whether the row is actionable, unavoidable/background, irrelevant, or
unclassified. The encounter document contract must encode that context.

Before the public mirror can be considered product-complete, frontend-visible
encounter analysis needs the document contract from
[`ENCOUNTER_DOCUMENTS_DESIGN.md`](ENCOUNTER_DOCUMENTS_DESIGN.md). The target is:

```text
silver projections + existing gold read models
  -> versioned per-encounter JSON documents emitted by the medallion build
  -> local frontend reads documents from disk
  -> opted-in documents uploaded to a private R2 bucket
  -> Gigalixir public frontend reads the same documents from R2
```

Encounter documents are their own initiative, not buried inside public mirror
work. The generator serializes existing read models at build time — no new gold
tables are required for the base sections — while mechanic-specific sections
must depend on the relevant mechanic/fact initiatives:

| Document section | Dependency |
|---|---|
| Encounter summary, roster, deaths, damage summaries, debuffs | Existing silver/gold read models at build time |
| Avoidable failure section | Initiative 2 smoke test |
| Standardized mechanic labels and bespoke detector-backed sections | Initiative 2 |
| User-authored classifications and suppressions | Initiative 3 |
| Interrupt and other non-avoidable failure sections | Initiative 4 |
| Hosted public rendering from R2 documents | Initiative 6 |

Do not expand the public UI around failure facts alone. Build the encounter
document contract section by section, then upload those documents.

Do not promote raw observed spell lists as product UI. They are scaffolding until
they include player-impact summaries and classification controls.

## Guiding Constraints

- Keep combat logs the primary truth for what appears in the user's data.
- Prefer observed spell previews over hidden source-row queues.
- Prefer direct editable rules over durable source-row review/override workflow.
- Prefer gold rebuilds when rules or gold logic changes.
- Do not reintroduce `public.mechanic_criteria` or analyzer-cache tabs.
- Keep raw combat-log bronze separate from patch/source-data bronze.
- Keep UI labels honest about whether a row is observed data, a source annotation, an editable rule, or a rebuilt failure fact.
- Use absolute authored thresholds, not cross-guild percentile scoring (we are not Wipefest here — single-guild logs).

## Source-Data Direction

DBM, BigWigs, WowAnalyzer, Blizzard journal data, Warcraft Logs, MRT reminders, WeakAuras, and guide sites are **source annotations** — they help explain and classify spells that appear in local logs. They are **not** independent truth that should silently create failure facts. Existing DBM/WowAnalyzer source-data tables may remain as parsed evidence while useful; new user-facing work should avoid source-row review language and prefer observed mechanics, source annotations, rule status, and direct editable rules.
