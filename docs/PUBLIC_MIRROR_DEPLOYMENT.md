# Public Mirror Deployment

The public mirror deploys from GitHub Actions after a green push to `main`.
CI deploys the `we_go_next/` subfolder to Gigalixir, so buildpack config lives
in `we_go_next/elixir_buildpack.config`.

This document covers deployment and current upload operations only. The current
public surface is a provisional failure-fact preview; the product plan for
mirroring the full local encounter analysis page is
[`ENCOUNTER_DOCUMENTS_DESIGN.md`](ENCOUNTER_DOCUMENTS_DESIGN.md).

The current upload operations below describe the legacy Phoenix ingest path,
which will be pruned (WE-36). The active plan is to have the medallion build
write versioned per-encounter JSON documents locally, upload opted-in documents
to a private Cloudflare R2 bucket (WE-31/WE-33), and have the Gigalixir public
app read them from R2 (WE-32).

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
gigalixir config:set INGEST_TOKEN=<ingest-token>
```

`DATABASE_URL` should be provided by the Gigalixir-managed Postgres attachment.
`SECRET_KEY_BASE` must also be present in Gigalixir config.

Public report slugs are database-backed records created by ingesting into a
report URL. They are not deployment config.

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

The older provisional failure-fact mirror path still has `mirror_uploads` rows
and `WeGoNext.Mirror.Outbox`, but parser credentials are no longer stored on the
user. Prefer the document store path above for new public-sharing work.

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

Expected result before the report has been ingested: HTTP 404.
Expected result after ingesting at least once into that report slug: HTTP 200 with the public encounters page.

The current public encounters page may show zero players/damage for uploaded
encounters that have no `gold.fact_failure` rows. That is a limitation of the
current provisional failure-fact contract, not proof that the local encounter has
no analysis data. The full-detail contract is tracked in
[`ENCOUNTER_DOCUMENTS_DESIGN.md`](ENCOUNTER_DOCUMENTS_DESIGN.md).

Do not add `INGEST_TOKEN`, `DATABASE_URL`, or `SECRET_KEY_BASE` to GitHub just to automate this smoke test.
