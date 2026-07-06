# Public Mirror Gold Detail Plan

Status: **current direction** as of 2026-06-29. Work is factored into
[Initiative 5 — Gold Encounter Detail Read Models](initiatives/05-gold-encounter-detail.md)
and [Initiative 6 — Public Analysis Mirror](initiatives/06-public-analysis-mirror.md).

## Problem

The deployed public mirror proves the parser/public plumbing, but it does not
yet mirror the useful local encounter analysis page.

The local encounter detail experience is rich because it reads a mix of silver
projections and gold facts. The public mirror currently receives only:

- `gold.dim_encounter`
- `gold.dim_player`
- `gold.dim_mechanic_criterion`
- `gold.fact_failure`

That makes the public site a failure-fact preview, not a mirror of the analysis
page. This is especially weak because `gold.fact_failure` is still a narrow
proof-of-concept: many real encounters have roster, damage, death, debuff, and
interrupt data locally while having zero mirrored failure facts publicly.

## Corrected Product Target

The public mirror should put the real encounter analysis page online. It should
render the same public-safe analysis contract as the local app, without exposing
raw combat logs, parser filesystem state, operator settings, or rules/source
internals.

Frontend-visible encounter analysis should be backed by gold read models. If a
section is part of the product UI, it should not require the public app to query
silver directly.

The current public-gold line of work is now file-oriented: the medallion build
produces versioned JSON files for the public-safe gold encounter detail
contract. The local frontend reads those files as its encounter-analysis
contract, and the publish path uploads the same JSON artifacts to Cloudflare
object storage for the Gigalixir public app to read. The public app should not
need a write-side ingest endpoint or a public copy of the medallion database for
this contract.

## What We Keep

The current WE-5 through WE-12 work remains useful as infrastructure:

- parser/public runtime mode split,
- Gigalixir deploy path,
- report slugs,
- legacy ingest endpoint and bearer-token auth for the provisional preview,
- stable encounter/criterion mirror keys,
- per-encounter upload and replacement semantics,
- parser-side upload outbox.

Treat this as plumbing, not the finished public product.

## New Gold Contract

Define a gold-backed encounter detail contract that can power both local and
public detail pages.

Required sections:

- encounter metadata: boss, difficulty, result, duration, start/end time;
- roster: players present, class/spec where known;
- player encounter summary: per-player totals needed by the detail page;
- deaths: death rows, killing blow, and compact recap data;
- damage taken: summary rows and notable damage families;
- damage done: summary rows if the current local view depends on them;
- debuffs: applied debuffs currently shown in encounter detail;
- interrupts/casts: current interrupt/cast summary where silver semantics are
  defensible;
- mechanic/failure facts: existing `gold.fact_failure` plus future expanded
  fact semantics.

Each public section must inherit the same player-impact and actionability context
as the local gold detail contract. Public should not publish a flat list of
encounter spells or debuffs with no affected-player summary.

Excluded from public:

- raw combat-log lines or raw event payloads;
- bronze file paths, byte offsets, source hashes, and local filesystem state;
- parser settings and user account settings;
- medallion readiness/operator diagnostics that depend on silver/rules internals;
- source-data authoring queues or rules promotion internals.
- raw low-context spell/debuff lists that do not answer who was affected or why
  the row matters.

## Architecture Direction

Build explicit gold read models from existing silver/gold sources, serialize the
public-safe contract to deterministic JSON files, then make the UI consume those
files.

Likely gold read-model tables or materialized contract modules:

- `gold.encounter_summary`
- `gold.player_encounter_summary`
- `gold.encounter_death_summary`
- `gold.encounter_damage_taken_summary`
- `gold.encounter_damage_done_summary`
- `gold.encounter_debuff_summary`
- `gold.encounter_interrupt_summary`
- existing `gold.fact_failure`, expanded as fact semantics mature

The exact table split should follow the current local page sections and test
fixtures. Do not create generic raw-event gold tables.

The JSON artifact layout should be stable enough for both runtimes:

- one report manifest per public report/slug;
- one encounter summary/index artifact for list views;
- one encounter detail artifact per `source_encounter_key`;
- a schema/version field in every artifact;
- deterministic filenames or object keys derived from the report slug and
  stable encounter keys;
- no bronze paths, byte offsets, raw events, parser settings, rules internals, or
  source-data authoring state.

Cloudflare is the publication boundary for these artifacts. The local parser
writes them as part of the medallion build, the local frontend reads them from
disk, and the uploader syncs the same files to Cloudflare. Gigalixir remains the
hosted Phoenix viewer, but it reads the Cloudflare JSON contract instead of
being the primary write target for encounter snapshots.

## Initiative Boundaries

- Initiatives 1-4 own mechanic/rule/fact semantics.
- Initiative 5 owns the gold encounter detail read models and local UI contract.
- Initiative 6 owns hosted public upload/rendering of that contract.

Public mirror should not drive mechanic design. It should consume the public-safe
gold contract once the relevant sections exist.

## Migration Plan

1. **Freeze current public mirror as plumbing**
   - Keep deploy, ingest, report slugs, and outbox.
   - Label current public UI as provisional if it remains visible.
   - Add an operator command or UI control to drain the upload outbox.

2. **Inventory the local encounter detail page**
   - List every field and section rendered locally.
   - Mark each field as `already gold`, `derive from silver`, `exclude from
     public`, or `needs new semantics`.
   - Capture one real encounter fixture as the acceptance target.

3. **Define the gold encounter detail contract**
   - Write the contract as a documented map/struct or Ecto read model.
   - Define the JSON schema, filenames/object keys, and versioning rules.
   - Add tests for the real fixture shape before replacing the UI path.

4. **Build JSON-producing gold read models section by section**
   - Start with roster, deaths, and damage summaries because they make the public
     page recognizable as the local analysis page.
   - Keep `fact_failure` as one section, not the whole product.
   - Make the medallion build emit the corresponding JSON artifact files.

5. **Switch local detail UI to the JSON-backed gold contract**
   - Shared display components should consume the JSON artifact contract.
   - Local-only operator panels stay separate.

6. **Replace the public upload target**
   - Upload the full encounter detail JSON artifact set to Cloudflare.
   - Replace per-encounter objects atomically enough that readers never see a
     mixed schema for one encounter.
   - Preserve schema-version rejection/read safety and retryable outbox behavior.

7. **Render the same detail contract publicly**
   - Public detail pages should match the local analysis content for all
     public-safe sections.
   - Public reads the Cloudflare JSON artifacts and must not call `Accounts`,
     parser modules, silver queries, rules internals, source-data internals, or a
     public medallion database for encounter-detail content.

## Acceptance Criteria

The corrected public mirror is not complete until:

- a real local encounter detail page can be rendered from gold-only public-safe
  JSON artifacts produced by the medallion build;
- uploading that encounter publishes roster, deaths, damage summaries, debuffs,
  interrupts/casts where supported, and failure facts to Cloudflare;
- the public detail page renders the same meaningful analysis sections as local;
- zero-fact encounters are not presented as broken analysis pages;
- version mismatches fail safely and remain retryable through the outbox.
