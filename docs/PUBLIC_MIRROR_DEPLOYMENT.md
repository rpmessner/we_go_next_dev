# Public Mirror Deployment

The public mirror deploys from GitHub Actions after a green push to `main`.
CI deploys the `we_go_next/` subfolder to Gigalixir, so buildpack config lives
in `we_go_next/elixir_buildpack.config`.

This document covers deployment and current upload operations only. The public
surface reads uploaded encounter documents from a private Cloudflare R2 bucket
behind the `/r/:slug` shared-link gate. The legacy Phoenix ingest path remains
in the codebase until WE-36, but it is no longer the public encounter list/detail
render path.

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

Do not set `INGEST_TOKEN` for the document-backed public surface. The ingest
controller is legacy code pending WE-36.

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

## Legacy HTTP Outbox

The older provisional failure-fact mirror path and HTTP ingest controller still
exist until WE-36. The `mirror_uploads` table remains active as the document
upload ledger, but `WeGoNext.Documents.UploadWorker` now drains it by writing
`encounters/<source_encounter_key>.json` and refreshing public `index.json` in
the configured R2 bucket.

Only drain the legacy outbox when explicitly testing the old HTTP ingest path,
and pass upload config directly from the caller:

```bash
cd we_go_next
mix run -e 'IO.inspect(WeGoNext.Mirror.Outbox.process_pending(
  limit: 50,
  config: %{
    public_base_url: "https://<public-host>",
    ingest_token: "<INGEST_TOKEN>",
    report_slug: "default"
  }
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

- `:nxdomain` in `last_error` means the supplied public base URL is misspelled.
- HTTP `401` means the supplied token does not match Gigalixir `INGEST_TOKEN`.
- HTTP `422` with `unsupported_schema_version` means local and public code are
  on incompatible snapshot versions; deploy public, then retry the outbox.

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

Do not add `DATABASE_URL`, `SECRET_KEY_BASE`, or R2 credentials to GitHub just
to automate this smoke test.
