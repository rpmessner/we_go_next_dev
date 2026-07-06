# Initiative 5 — Encounter Document Read Models

Linear project: [5. Encounter Document Read Models](https://linear.app/we-go-next/project/cc8eb6cf7437) (WE-25, WE-27…WE-30, WE-35; WE-26 canceled). Design: [`../ENCOUNTER_DOCUMENTS_DESIGN.md`](../ENCOUNTER_DOCUMENTS_DESIGN.md).

## Goal

Make per-encounter JSON documents the read-model product of the medallion build, and render the local frontend from them. The generator serializes the existing read models (`Gold.EncounterDetail`, `Gold.ObservedMechanics`) at build time — silver/gold are read freely then; the render path reads only documents.

## Scope

- **WE-25** — inventory the document contract: every rendered encounter-detail section/field, classified public vs operator-only; pick the real-encounter regression fixture.
- **WE-29** — versioned document schema (`schema_version`, `generated_at`, derivation stamp) + generator wired into `Gold.RebuildEncounter.rebuild/2`; `mix wgn.rebuild_documents` backfill; minimal FileSystem store. Documents keyed by `source_encounter_key`.
- **WE-35** — `Documents.Store` behaviour with FileSystem + R2 (S3-compatible, `req_s3`) adapters; R2 credentials via the `Accounts.SecretBox` pattern + Settings UI; env-driven config.
- **WE-30** — re-tool the local encounter detail + list frontend to render from documents; URLs move to `/encounters/:source_encounter_key`; stale/empty/missing-document states diagnosable in the UI.
- **WE-27 / WE-28** — later content enrichment (severity, actionability, classification context, affected players on debuff/spell rows), targeting the document contract.

## Rationale shift (2026-07-06)

This initiative was originally "Gold Encounter Detail Read Models" — rebuild each detail section as a gold-backed read model so the DB mirror could carry it. The document boundary makes that unnecessary; no significant warehouse schema rework is needed. WE-26 (gold summary/roster slice) is canceled as subsumed by the generator.
