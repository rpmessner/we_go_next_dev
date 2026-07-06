# Encounter Documents (JSON-First Read Models) — Planning Session

Date: 2026-07-06

## What happened

Planning-only session (no code changes). The operator decided to rearchitect the public mirror away from the DB-backed design (WE-5…WE-12, built and deployed) toward **JSON-first encounter documents**. Decisions were locked through a grilling interview, the codebase was explored to ground them, and the outcome landed as a design doc plus a reworked Linear board for subsequent sessions to implement.

## Motivation

- The Gigalixir managed Postgres is a recurring cost whose only job is storing mirrored gold rows behind a hardened ingest endpoint.
- The no-silver principle made the public mirror thin — `fact_failure` counts only — while the local encounter detail view (silver+gold) is the interface the product is converging on. The operator wants "a full mirror of the encounter view rather than just the gold layer (which at this point is pretty thin)."

## Locked decisions (grilling interview)

1. **End state** — the same frontend as the local app runs on Gigalixir, fed by uploaded JSON documents rather than Postgres. Public DB shrinks to app metadata (`public_reports`).
2. **Data seam** — JSON-first everywhere: the medallion build always generates documents; local reads them from disk, public from object storage. One render path; parity is structural. ("Re-tool the entire frontend to read json files… that way we can replicate all the user-data level things the same way on both platforms.")
3. **Storage** — Cloudflare R2, private bucket, S3-generic env-driven code.
4. **View scope** — encounter list + full encounter detail. The gold `/failures` view is "implementation-detail leaky" and a dead end; failure views will be rebuilt *inside* the encounter-detail paradigm (encounter-grain "who failed this pull"; later player-grain "who fails mechanics across raids") during analysis-layer buildout.
5. **Access** — keep the `/r/:slug` shared-secret gate.
6. **Pruning** — DB-mirror ingest path pruned now; `/failures` pruned later with the analysis-layer work. `Mirror.Keys`/`source_encounter_key` and the `mirror_uploads` outbox survive as document identity and upload ledger.
7. **Publish** — local docs generated on every rebuild unconditionally; upload opt-in via per-log-file `publish_enabled` checkbox (auto) plus a per-encounter **Upload** button on the detail page (reads **Re-upload** once uploaded by either path). Originally a per-encounter opt-*out* override was considered; revised to opt-in button.
8. **Unpublish** — none in v1; toggling off stops future uploads, stale docs remain.

## Key exploration findings that shaped the design

- `Mirror.Snapshot` already produces a versioned per-encounter JSON payload — but only fact-failure data; the document contract extends to the full `Gold.EncounterDetail.get/2` + `Gold.ObservedMechanics.for_encounter/1` shape.
- The outbox is currently **inert** — nothing calls `Outbox.process_pending/1` at runtime; the drain worker is net-new required work (WE-31).
- Gigalixir's filesystem is ephemeral, which forced the durable-storage question (answer: R2).
- `Req` is the only HTTP dep (no S3 client — plan: `req_s3`); `combat_log_files` has no publish flag (net-new migration); `mirror_public_base_url`/`mirror_ingest_token` settings exist but were never surfaced in Settings UI (replaced by R2 credentials via the same SecretBox pattern).
- Board projects 5/6 as originally written planned per-section **gold read models** so the DB mirror could carry detail. The document boundary makes that unnecessary — the generator may read silver freely at build time; "no silver at render time" comes from the document, not schema rework.

## Artifacts produced

- **Design doc**: [`../ENCOUNTER_DOCUMENTS_DESIGN.md`](../ENCOUNTER_DOCUMENTS_DESIGN.md) (architecture, document contract, store seam, publish controls, pruning list, phasing, risks).
- **Initiative docs**: [`../initiatives/05-encounter-documents.md`](../initiatives/05-encounter-documents.md), [`../initiatives/06-public-analysis-mirror.md`](../initiatives/06-public-analysis-mirror.md); `initiatives/README.md` + `ROADMAP.md` + `docs/README.md` updated.
- **Superseded**: `PUBLIC_MIRROR_DESIGN.md` banner added (run-mode split, mirror keys, slug gate, deploy pipeline carry forward; ingest path does not).
- **Linear board rework** (team WE):
  - Project 5 renamed **Encounter Document Read Models**; project 6 **Public Analysis Mirror** re-scoped to documents-on-R2; **Public Gold Mirror** project marked superseded (WE-11/WE-12 deploy work remains valid).
  - Retitled/rewritten: WE-25 (inventory the document contract), WE-29 (document schema + generator), WE-30 (local frontend from documents), WE-31 (upload documents to R2 via outbox + drain worker), WE-32 (public frontend from R2), WE-33 (publish controls + diagnostics), WE-34 (e2e smoke via R2).
  - Retargeted as later enrichment: WE-27, WE-28 (document-section enrichment, off the critical path).
  - **Canceled**: WE-26 (subsumed by the generator serializing existing read models).
  - **Created**: WE-35 (document store seam: FileSystem + R2 adapters), WE-36 (prune the DB-mirror ingest path; `/failures` parser-gated).

## Implementation order (for pickup)

WE-25 → WE-29 → WE-35 → WE-30 (local proof) → WE-31 → WE-33 → WE-32 (public) → WE-36 (prune) → WE-34 (smoke). WE-27/WE-28 ride with analysis-layer work.
