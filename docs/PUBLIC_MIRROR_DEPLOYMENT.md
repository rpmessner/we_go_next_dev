# Public Mirror Deployment

The public mirror deploys from GitHub Actions after a green push to `main`.
CI deploys the `we_go_next/` subfolder to Gigalixir, so buildpack config lives
in `we_go_next/elixir_buildpack.config`.

This document covers deployment and current upload operations only. The public
surface reads uploaded encounter documents from a private Cloudflare R2 bucket
behind the `/r/:slug` shared-link gate. The legacy Phoenix ingest path has been
removed.

## GitHub Flow

1. Pull requests run the `quality` job only.
2. Merging to `main` runs `quality` again.
3. If `quality` passes, the `deploy` job targets the `production` environment.
4. While deployment is still being proven, configure `production` with a required reviewer so the job pauses for manual approval.

The deploy job uses only deploy-auth secrets:

- `GIGALIXIR_EMAIL`
- `GIGALIXIR_API_KEY`

Runtime secrets stay in Gigalixir config, not GitHub.

## Gigalixir Runtime Config

Set these on the `we-go-next` app:

```bash
gigalixir config:set WE_GO_NEXT_MODE=public
gigalixir config:set MODE=public
gigalixir config:set RUN_MIGRATIONS_ON_BOOT=true
gigalixir config:set PHX_HOST=<public-host>
gigalixir config:set DOCUMENTS_STORE=r2
gigalixir config:set R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
gigalixir config:set R2_BUCKET=<bucket>
gigalixir config:set R2_ACCESS_KEY_ID=<read-access-key-id>
gigalixir config:set R2_SECRET_ACCESS_KEY=<read-secret-access-key>
```

`DATABASE_URL` should be provided by the Gigalixir-managed Postgres attachment.
`SECRET_KEY_BASE` must also be present in Gigalixir config.

Remove any old `INGEST_TOKEN` setting from Gigalixir config. The public app no
longer exposes an ingest endpoint, and document reads use the R2 credentials
above.

```bash
gigalixir config:unset INGEST_TOKEN
```

Public report slugs are database-backed records. Provision or update them from
the deployed release console:

```bash
gigalixir run 'bin/we_go_next eval "WeGoNext.Release.upsert_public_report(\"raid-night\", \"Raid Night\")"'
```

Disable a shared link without deleting uploaded documents by setting the third
argument to `false`:

```bash
gigalixir run 'bin/we_go_next eval "WeGoNext.Release.upsert_public_report(\"raid-night\", \"Raid Night\", false)"'
```

## Local Upload Configuration

The local parser writes generated encounter documents through
`WeGoNext.Documents.Store`. The default store is filesystem-backed and rooted at
`DOCUMENTS_ROOT`. To smoke-test the R2 path, set:

```bash
DOCUMENTS_STORE=r2
R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
R2_BUCKET=<bucket>
R2_ACCESS_KEY_ID=<write-access-key-id>
R2_SECRET_ACCESS_KEY=<write-secret-access-key>
```

Parser-side R2 write credentials can also be saved from the Settings page. The
secret access key is encrypted with the same `Accounts.SecretBox` pattern used
for Warcraft Logs credentials.

Operator smoke that still needs a real bucket:

```bash
cd we_go_next
DOCUMENTS_STORE=r2 mix wgn.rebuild_documents --encounter-id <encounter_dim_id>
```

Then confirm both keys exist in the bucket:

```text
encounters/<source_encounter_key>.json
index.json
```

## Document Upload Outbox

The `mirror_uploads` table remains the upload ledger. In parser mode,
`WeGoNext.Documents.UploadWorker` drains pending, stale, and error rows by
writing `encounters/<source_encounter_key>.json` and refreshing public
`index.json` in the configured R2 bucket.

To manually drain a small batch from IEx or `mix run`:

```bash
cd we_go_next
mix run -e 'IO.inspect(WeGoNext.Mirror.Outbox.process_pending(
  limit: 50,
  max_concurrency: 2
))'
```

To inspect local outbox state:

```bash
cd we_go_next
mix run -e '
import Ecto.Query
alias WeGoNext.Repo
alias WeGoNext.Mirror.MirrorUpload
IO.inspect(Repo.all(from u in MirrorUpload, select: {u.state, count(u.id)}, group_by: u.state))
'
```

Common failure modes:

- `:r2_not_configured` means neither env R2 credentials nor parser Settings R2
  credentials are available.
- `{:missing_document, source_encounter_key}` means the local encounter document
  was not generated before upload.
- HTTP `403` from R2 usually means the access key lacks the needed read/write
  permission for the bucket.

## Smoke Test

After approving and completing a `main` deployment:

```bash
curl -i https://<public-host>/r/<report-slug>
```

Expected result before the slug is provisioned: HTTP 404.
Expected result after the slug is provisioned: HTTP 200 with the public
encounters page. If no documents have been uploaded, the page explains that the
public document index is empty.

After uploading at least one opted-in encounter, confirm the R2 bucket contains:

```text
encounters/<source_encounter_key>.json
index.json
```

Then reload `/r/<report-slug>` and open
`/r/<report-slug>/encounters/<source_encounter_key>`.

For the repeatable end-to-end smoke, run the parser-side task with the known
factful fixture and a zero-failure encounter that still has roster/detail rows:

```bash
cd we_go_next
mix wgn.public_mirror_smoke \
  --factful-encounter-id 124 \
  --zero-failure-encounter-id <zero_failure_encounter_dim_id> \
  --slug <report-slug> \
  --public-base-url https://<public-host>
```

The task rebuilds both encounter documents, drains the upload outbox to R2,
checks the uploaded `index.json` and documents, and probes the public list plus
both detail pages. Post the result block to WE-34 and copy it to WE-11 and WE-12
as the deployment verification closeout under the document architecture.

Do not add `DATABASE_URL`, `SECRET_KEY_BASE`, or R2 credentials to GitHub just
to automate this smoke test.
