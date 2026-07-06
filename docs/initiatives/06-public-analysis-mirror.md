# Initiative 6 — Public Analysis Mirror (Documents on R2)

Linear project: [6. Public Analysis Mirror](https://linear.app/we-go-next/project/c8d8c68a7bbe) (WE-31…WE-34, WE-36). Design: [`../ENCOUNTER_DOCUMENTS_DESIGN.md`](../ENCOUNTER_DOCUMENTS_DESIGN.md). Depends on initiative 5.

## Goal

Host the same frontend publicly (Gigalixir, `MODE=public`), fed by encounter documents in a **private Cloudflare R2 bucket** instead of a mirrored Postgres. Upload is opt-in per log file (checkbox) plus a per-encounter Upload/Re-upload button. The DB-mirror ingest path is pruned; the public DB shrinks to `public_reports` slugs.

## Scope

- **WE-31** — upload documents to R2 through the `mirror_uploads` outbox plus a real drain worker (`Documents.UploadWorker`, parser-mode child; today nothing drains the outbox). Upload = put encounter doc + refresh the public `index.json`.
- **WE-33** — publish controls: `combat_log_files.publish_enabled` checkbox (auto-enqueue on rebuild), encounter-detail Upload/Re-upload button, upload-state diagnostics without SQL.
- **WE-32** — public frontend reads documents from R2 under `/r/:slug` (slug gate unchanged); slug provisioning release task; Gigalixir env swap (drop `INGEST_TOKEN`, add R2 read credentials).
- **WE-36** — prune the ingest path: `Mirror.Ingest`, `IngestController` + `/api` route, `IngestContentLength`, `Mirror.Upload`/`Mirror.Snapshot`, `Gold.PublicReadModels`, `PublicLive.*` thin views, mirror upload user settings, public-DB gold ingestion; gate `/failures` parser-only.
- **WE-34** — end-to-end smoke: rebuild fixture locally → doc lands in R2 → public page renders expected sections (factful + zero-failure encounters).

## Non-goals (v1)

- No unpublish/retraction — toggling off only stops future uploads; stale docs remain in the bucket.
- No per-user accounts; the shared-secret `/r/:slug` link stays the privacy boundary.
- No document deletion, compression, or caching until measured need.
