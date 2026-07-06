# Encounter Documents — JSON-First Read Models (Design)

Status: **approved — ready to build** (design only; not yet built). Author session: 2026-07-06 (see [`sessions/2026-07-06_encounter_documents_plan.md`](sessions/2026-07-06_encounter_documents_plan.md)). Supersedes the DB-backed mirror architecture in [`PUBLIC_MIRROR_DESIGN.md`](PUBLIC_MIRROR_DESIGN.md) — the run-mode split, mirror keys, Gigalixir release/CI, and slug-gate work from that design (WE-5…WE-12) carry forward; the **HTTP ingest → public Postgres → gold-only views** path does not.

## Goal

Make **per-encounter JSON documents the read-model product of the medallion build**, and render the same LiveView frontend from those documents everywhere:

- **Locally** (parser mode) — documents are generated on every gold rebuild and read off disk.
- **Publicly** (Gigalixir, public mode) — opted-in documents are uploaded to a private Cloudflare R2 bucket and read from there.

The database stops holding encounter-derived data for the frontend. Local/remote parity becomes structural — same documents, same renderer — instead of maintained by hand across two read paths.

## Why (what the DB mirror got wrong)

The built DB mirror (WE-5…WE-12: parser → outbox → HTTP ingest → Gigalixir Postgres → gold-only `PublicLive.*`) has two problems:

1. **Cost/complexity** — the managed public Postgres is a recurring expense whose only job is storing mirrored gold rows, plus an internet-facing write endpoint that needed hardening.
2. **Thinness** — the no-silver principle limited the public surface to `gold.fact_failure` counts. The gold layer is thin today, so the mirror shows almost nothing, while the local encounter detail view (`Gold.EncounterDetail` + `Gold.ObservedMechanics`: roster, deaths, pull review, interrupt coverage, observed mechanics, failure preview) is the interface the product is converging on.

The previous escape plan (board projects 5/6 as originally written) was to rebuild each detail section as a gold-backed read model so it could be mirrored table-by-table. The document approach makes that unnecessary: **the generator may read silver/gold freely at build time** — the "no silver at render time" property comes from the document boundary, not from moving every section into gold tables. No significant warehouse schema rework is required.

## Decisions (locked 2026-07-06)

| Fork | Decision |
|---|---|
| End state | Same frontend as the local app runs on Gigalixir, fed by uploaded JSON documents instead of Postgres. The public DB shrinks to app metadata (`public_reports` slugs); no encounter-derived data. |
| Data seam | **JSON-first everywhere.** The medallion build always generates documents; the local frontend reads them off disk, public reads them from R2. One render path, no dual DB/JSON adapters. |
| Doc storage | **Cloudflare R2** (S3-compatible), **private bucket** — only the apps read it, with credentials. Code stays S3-generic and env-driven so the provider is swappable. |
| View scope | Encounter list + **full encounter detail** (the encounter-detail paradigm is the venue for future mechanic-classification work). |
| `/failures` | Dead end — **not** part of the document surface. It stays local (parser-gated) until failure views are rebuilt *inside* the encounter-detail paradigm (encounter-grain "who failed this pull"; later a player-grain "who fails mechanics across raids") during analysis-layer buildout. |
| Access control | Keep the shared-secret **`/r/:slug`** gate (`public_reports` row, `Plugs.PublicViewer`) as the viewer boundary. Raiders never touch the bucket. |
| Publish trigger | Documents are generated locally on **every** rebuild, unconditionally. **Upload is opt-in**: a `publish_enabled` checkbox per **combat log file** (auto-upload that file's encounters on rebuild) plus an explicit **Upload** button on the encounter detail page for one-off publishes; the button reads **Re-upload** once the encounter has ever been uploaded by either path. |
| Unpublish | None in v1 — turning a flag off stops future uploads; already-uploaded documents stay (stale) in the bucket. |
| Pruning | The DB-mirror ingest path is pruned in this initiative (see *Pruned* below). `Mirror.Keys`/`source_encounter_key` and the `mirror_uploads` outbox survive — they become document identity and the upload ledger. |

## Architecture

```text
import → silver projection → Gold.RebuildEncounter.rebuild/2
                                   │
                                   ├─ FactFailure rebuild (unchanged)
                                   ├─ Documents.generate(encounter)      # ALWAYS: encounter doc + index doc → local store
                                   └─ maybe enqueue upload               # if file publish_enabled → outbox
                                                │
                                     Documents.UploadWorker (parser mode)
                                                │  puts docs → R2 (S3 API)
                                                ▼
   local frontend ── reads ──► Documents.Store.FileSystem (DOCUMENTS_ROOT)
   public frontend ─ reads ──► Documents.Store.R2 (private bucket, read creds)
```

### Document contract

Two document kinds, both versioned with `schema_version`, `generated_at`, and the failure `derivation_version` so stale documents are mechanically detectable (the existing stale-data diagnostics principle):

- **`encounters/<source_encounter_key>.json`** — the full encounter detail: everything `Gold.EncounterDetail.get/2` returns today (encounter metadata, counts, roster, deaths, pull_review, failure_preview incl. targeted-cone events, interrupt_coverage, personal summaries) **plus** `Gold.ObservedMechanics.for_encounter/1` output. The document is **character-agnostic**: it carries per-player personal summaries for *all* players; selecting "my character" is a UI concern (parser mode preselects from `Accounts`; public mode defaults to none).
- **`index.json`** — the encounter list: one entry per generated encounter (`source_encounter_key`, boss, `wow_encounter_id`, difficulty, start/end time, success, fight time, headline counts). Regenerated whenever any encounter document is written. The public index in R2 contains **only uploaded encounters** (it is maintained by the upload path, not blind-copied from the local index).

Identity is `source_encounter_key` (`Mirror.Keys.source_encounter_key/1`, already a stored, unique column on `gold.dim_encounter`). An encounter that cannot be keyed cannot be documented/published — same error rule as the mirror design. Encounter URLs use the key in **both** modes (`/encounters/:source_encounter_key` locally, `/r/:slug/encounters/:source_encounter_key` publicly) so links are portable between local and public.

Sections that are operator-only (e.g. `observed_mechanics` rule diagnostics, readiness hints) are carried in the document but **marked** so the public renderer can hide them; the exact split is settled by the WE-25 inventory.

### Document store seam

`WeGoNext.Documents.Store` behaviour — `put/2`, `fetch/1`, `exists?/1` (delete deferred; no unpublish in v1). Two adapters:

- **`Store.FileSystem`** — rooted at config `:documents_root` (env `DOCUMENTS_ROOT`; default a git-ignored `we_go_next/documents/`). Parser mode reads and writes this always.
- **`Store.R2`** — S3-compatible via `Req` (dep already present) + the `req_s3` plugin (SigV4). Config: `R2_ENDPOINT`(account URL), `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`. Parser mode uses **write** credentials for upload (stored per the `Accounts.SecretBox` encrypted-settings pattern, surfaced in Settings — replacing the never-surfaced `mirror_public_base_url`/`mirror_ingest_token` fields); public mode uses **read** credentials from Gigalixir env.

The frontend reads through a mode-selected store: parser → FileSystem, public → R2. Reads are per-mount, no ETS cache (per the caching principle — revisit only with evidence it's slow).

### Publish controls (parser mode)

- Migration: `combat_log_files.publish_enabled :boolean, default: false` — surfaced as a checkbox in the imported-logs UI, mirrored read-only on that file's encounter detail pages.
- Auto path: `Gold.RebuildEncounter.rebuild/2` enqueues an upload (existing `Outbox.enqueue_for_encounter/1`, coalescing by `source_encounter_key`) **only when** the encounter's log file has `publish_enabled`.
- Manual path: an **Upload** button on the encounter detail page enqueues regardless of the file flag; it renders **Re-upload** when the encounter's `mirror_uploads` row is `published`.
- **A worker actually drains the outbox now** — today nothing calls `Outbox.process_pending/1` at runtime (the HTTP leg was inert). `Documents.UploadWorker` is a parser-mode child processing `pending|stale|error` rows with bounded concurrency; "upload" = put the encounter document + refresh the public `index.json` in R2. Upload state/errors are inspectable in the UI (no SQL), reusing the `mirror_uploads` states.

### Public app

- Same LiveView frontend (shared encounter-detail components), mounted under `/r/:slug` behind `Plugs.PublicViewer` (unchanged). List page renders from `index.json`; detail from the encounter document; operator-marked sections hidden; no `Accounts` calls in public mode.
- `public_reports` slug rows were previously created by ingest; they're now provisioned by a small release task/console command (or env-driven boot upsert) on the public app.
- `/failures` becomes **parser-gated** (it currently sits in the un-gated `:browser` scope; after pruning, public gold tables are empty and it would render a misleading empty state).
- Gigalixir keeps its (smallest-tier or free) Postgres only for `public_reports` + migrations; env swaps `INGEST_TOKEN` for the R2 read credentials.

### Pruned (this initiative)

`Mirror.Ingest`, `IngestController` + `/api/reports/:slug/ingest`, `Plugs.IngestContentLength` + its endpoint wiring, `Mirror.Upload` (HTTP POST publish), `Mirror.Snapshot` (subsumed by the document encoder), `Gold.PublicReadModels`, `PublicLive.{Encounters,Failures,EncounterFailures}` (replaced by doc-backed views), the `mirror_public_base_url`/`mirror_ingest_token` user settings, and public-DB gold ingestion (incl. `dim_encounter.public_report_id` scoping once nothing reads it).

**Kept:** `Mirror.Keys`, `mirror_uploads` (as the document-upload ledger), `Plugs.PublicViewer`, `public_reports`, the run-mode split, the Dockerfile/Gigalixir/CI pipeline (WE-11/WE-12).

## Phasing (Linear: projects 5 & 6, team WE)

Project **5. Encounter Document Read Models** (reworked from "Gold Encounter Detail Read Models"):

1. **WE-25** — Inventory the encounter document contract (all rendered sections/fields; classify public vs operator-only; pick the real-encounter regression fixture).
2. **WE-29** — Versioned document schema + build-time generator wired into `Gold.RebuildEncounter` (+ `mix wgn.rebuild_documents` backfill); minimal FileSystem store.
3. **WE-35** — `Documents.Store` seam: FileSystem + R2 adapters, credentials via SecretBox + Settings UI, env config.
4. **WE-30** — Re-tool the local frontend (encounter detail + list) to render from documents; URLs keyed by `source_encounter_key`; stale/empty document states diagnosable in the UI.
5. **WE-27 / WE-28** — (later, unblocking nothing) enrich document sections with severity/actionability/classification context; now target the document contract instead of new gold read models. **WE-26 is canceled** (subsumed by the generator serializing existing read models).

Project **6. Public Analysis Mirror** (reworked to the document path):

6. **WE-31** — Upload documents to R2 through the outbox + a real drain worker (replaces the HTTP ingest publish leg).
7. **WE-33** — Publish controls: per-file `publish_enabled`, encounter Upload/Re-upload button, upload-state diagnostics.
8. **WE-32** — Public frontend reads documents from R2 under `/r/:slug`; slug provisioning task; Gigalixir env swap (drop `INGEST_TOKEN`, add R2 read creds).
9. **WE-36** — Prune the DB-mirror ingest path (list above); gate `/failures` parser-only.
10. **WE-34** — End-to-end smoke: rebuild a known fixture locally → document appears in R2 → public page renders expected sections (factful + zero-failure encounters).

## Verification

- Contract tests: document encoder output round-trips against the WE-25 fixture; schema_version/derivation stamps present; per-section public/operator marking.
- Store tests: FileSystem adapter unit-tested; R2 adapter tested against a stub (`Req.Test`) plus a manual real-bucket smoke.
- LiveView tests: detail + list render from fixture documents in both modes; empty/stale/missing-document states explain themselves.
- WE-34 is the end-to-end proof over real data (the prime directive: real logs → medallion → visible UI without SQL).

## Open risks

- **Document size** — a full detail doc (damage events, cone events, per-player summaries) may be large; measure on real encounters (WE-25 fixture) before deciding on compression (gzip at rest) or section splitting.
- **Index concurrency** — index regeneration is last-write-wins; fine for a single-operator parser, revisit if multiple writers ever exist.
- **R2 dependency** — new external service + credentials; code stays S3-generic so the provider is swappable.
- **Stale public docs** — with no unpublish and schema evolution, old uploads may lag `schema_version`; the renderer must degrade gracefully and say so (stale-data diagnostics).
