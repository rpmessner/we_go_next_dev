# Initiative 5 — Gold Encounter Detail Read Models

Status: **Planned / dependency hub.** Linear: not yet split after WE-24.

## Goal

Promote the useful local encounter detail page into public-safe gold read models
and versioned JSON artifacts so frontend-visible analysis does not depend
directly on silver projections.

This is the missing layer between the existing local analysis UI and the hosted
public mirror. The goal is not to mirror raw silver. The goal is to define the
durable encounter-detail analysis contract the product actually displays and
write it as files the frontend can read.

## Why This Is Separate

Mechanic classification and Wipefest-style detector design decide *how mechanics
become rules and failure facts*. Gold encounter detail decides *what the
analysis page reads*.

Those are related but not the same initiative:

- roster, deaths, damage summaries, debuffs, and basic player summaries can be
  promoted from existing silver projections without waiting for every mechanic
  type to have fact semantics;
- mechanic/failure sections depend on Initiatives 1, 2, and 4;
- user-authored rule labels and overrides depend on Initiative 3;
- public mirror depends on this file contract, not the other way around.

## Scope

Create gold-backed read models for the sections the encounter detail page needs:

- **Encounter summary** — boss, difficulty, result, duration, start/end time.
- **Roster / player participation** — players present, class/spec where known.
- **Player encounter summary** — per-player totals used for scan/comparison.
- **Deaths** — death rows, killing blow, and compact recap summaries.
- **Damage taken** — player and spell summaries needed by the page.
- **Damage done** — only if the local detail page depends on it.
- **Debuffs** — applied debuffs currently shown in encounter detail.
- **Interrupts/casts** — only after silver semantics are tightened enough to
  make the labels honest.
- **Mechanic/failure facts** — existing `gold.fact_failure` plus future expanded
  fact semantics.

The medallion build should serialize these sections into JSON artifacts with
stable schema versions and deterministic filenames/object keys. The local
frontend should read the same artifact shape that the public frontend will read
from Cloudflare.

## UI Contract Requirements

Gold detail read models must be designed around the questions the UI should
answer, not around whichever silver table is easiest to expose.

For damage/debuff/mechanic rows, the minimum useful columns are:

- what happened: spell/debuff/cast name and IDs;
- who it affected: player list or top affected players;
- severity: hit/application count, total damage, max hit, and affected-player
  count where applicable;
- context: encounter, pull time window, difficulty, and mechanic classification;
- actionability: actionable failure, expected/unavoidable, irrelevant/noise,
  unknown/unclassified, or missing expected evidence.

Views that list damaging spells or debuffs without showing which players were
hit and who took the most damage are not acceptable product surfaces. Those
lists are debugging scaffolding until upgraded.

Default encounter detail should not be dominated by unavoidable rot or irrelevant
background effects. Those observations must remain available for audit and
classification, but the primary view should prioritize actionable mechanics,
outliers, deaths, and player-impact summaries.

## Dependency Map

| Detail section | Dependency |
|---|---|
| Encounter summary | Existing `gold.dim_encounter` |
| Roster / player summary | Existing `silver.player_info`, `gold.dim_player` |
| Deaths / death recap | Existing `silver.death` |
| Damage taken summaries | Existing `silver.damage_taken` / `silver.damage_taken_event` |
| Damage done summaries | Existing `silver.damage_done` |
| Debuffs | Existing `silver.debuff_application` |
| Irrelevant / unavoidable suppression labels | Initiative 3 |
| Evidence families and missing evidence checks | Initiative 2 |
| Interrupt/cast analysis | Initiative 4, especially interrupt silver tightening |
| Avoidable failure preview | Initiative 2 smoke test |
| Broader mechanic failure sections | Initiatives 2 and 4 |
| User-authored classifications | Initiative 3 |
| Public mirror detail page | Downstream consumer |

## Tickets To Split

- **Inventory local encounter detail contract** — enumerate every field/section
  currently rendered locally and mark it `already gold`, `derive from silver`,
  `exclude from public`, or `depends on mechanic semantics`.
- **Gold encounter summary + roster** — first read model slice; enough for local
  and public pages to look like real encounter pages instead of failure-only
  tables.
- **Gold deaths + damage summaries** — promote the highest-value existing silver
  sections.
- **Gold debuff and damage-done summaries** — promote only the sections the UI
  actually needs.
- **Gold detail facade** — a single local/public-safe read contract consumed by
  the encounter detail components.
- **Gold detail JSON writer** — serialize the facade into deterministic report,
  encounter-list, and encounter-detail JSON files with schema-version tests.
- **Switch local detail sections to gold** — replace direct silver-backed UI
  reads section by section, using the JSON-backed contract.

## Constraints

- Do not create generic raw-event gold tables.
- Do not block all gold detail work on every mechanic type having final failure
  semantics.
- Keep labels honest when a section is descriptive observation rather than a
  mechanic failure.
- Keep operator-only readiness diagnostics, rebuild controls, source-data
  authoring, and local settings out of the public-safe contract.

## Acceptance

A real local encounter detail page can render its core public-safe sections from
JSON artifacts produced from gold read models: encounter summary, roster,
deaths, damage summaries, debuffs, and any available mechanic/failure facts.
Remaining silver-only sections are explicitly marked as local/operator-only or
blocked by a named dependency.

## Related

[`../ROADMAP.md`](../ROADMAP.md) · [Absorbed avoidable-loop scope](01-real-data-failure-loop.md) · [Initiative 2](02-mechanic-classification-system.md) · [Initiative 4](04-fact-semantics-expansion.md) · [`../PUBLIC_MIRROR_GOLD_DETAIL_PLAN.md`](../PUBLIC_MIRROR_GOLD_DETAIL_PLAN.md)
