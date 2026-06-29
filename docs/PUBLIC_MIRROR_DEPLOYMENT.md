# Public Mirror Deployment

The public mirror deploys from GitHub Actions after a green push to `main`.
CI deploys the `we_go_next/` subfolder to Gigalixir, so buildpack config lives
in `we_go_next/elixir_buildpack.config`.

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

## Smoke Test

After approving and completing a `main` deployment:

```bash
curl -i https://<public-host>/r/<report-slug>
```

Expected result before the report has been ingested: HTTP 404.
Expected result after ingesting at least once into that report slug: HTTP 200 with the public encounters page.

Do not add `INGEST_TOKEN`, `DATABASE_URL`, or `SECRET_KEY_BASE` to GitHub just to automate this smoke test.
