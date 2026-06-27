# Public Gold Mirror — Design

Status: **approved — ready to build** (design only; not yet built). Author session: 2026-06-27. Incorporates the findings from [`sessions/2026-06-27_public_mirror_plan_review.md`](sessions/2026-06-27_public_mirror_plan_review.md) (round 1) and the criterion-key/schema/semantics-version follow-ups (rounds 2–3, see *Resolved by review* below). The reviewer's final guardrail — pin down where `semantics_version` lives and how it's bumped — is captured in the *Stable keys* section and phase 2 tests.

## Goal

Let raid members view a read-only, hosted mirror of our **gold analysis data** without exposing raw combat logs or the local parser. The same codebase runs in two contexts:

- **Parser context** — the existing local WSL2/Linux/Mac app. Watches and imports combat logs, runs the Zig parser, builds silver/gold, and (new) publishes gold snapshots upward.
- **Public context** — a hosted Phoenix app serving a gold-only read view at a shared-secret URL. It never sees raw logs, silver, or the filesystem.

Only **analysis data** crosses the boundary: the four `gold.*` star-schema tables. No raw combat-log lines, no silver event detail, no bronze byte offsets.

## Non-goals (v1)

- No per-user accounts or per-player private coaching views (shared-link access only).
- No mirroring of silver/bronze, so the **readiness/diagnostics panel** (silver+rules dependent) is disabled in the public context.
- No bidirectional sync — publish is one-way, parser → public.

## Decisions (locked 2026-06-27)

| Fork | Decision |
|---|---|
| Viewer access | **Shared secret link** (`/r/<slug>`), rotatable. No user table. |
| Publish trigger | **Automatic** after each `fact_failure` rebuild completes. |
| Hosting | **Gigalixir** (existing account, `we-go-next` app). Release/runtime kept env-driven so the platform stays swappable. |
| CI/CD | **GitHub Actions** (repo is `rpmessner/we_go_next_dev`), deploy to Gigalixir via `gigalixir/gigalixir-action` on green `main`. |
| v1 view scope | **Failures summary + a NEW gold-only per-encounter failure-breakdown view.** The existing silver-heavy `EncounterDetail`/`EncounterLive.Show` is **not** reused. |
| Public LiveViews | **Dedicated, gold-only, never call `Accounts`.** No reuse of parser surfaces that touch `users`/settings. |

## What gets mirrored (data contract)

Mirrored tables: `gold.dim_encounter`, `gold.dim_player`, `gold.dim_mechanic_criterion`, `gold.fact_failure` — these four star-schema tables are the entire public data surface.

What the four tables can serve:

- **Failures summary** — `Gold.FailureSummary.list_grouped_failures/1` + `group_by_player/1` (the grouped player → mechanic view) is gold-only. (Its `readiness/1` + `zero_fact_rule_diagnostics/1` panel reaches into `silver.*`/`rules.*` and is **disabled in public**.)
- **Per-encounter detail** — a **NEW** gold-only read model (a per-encounter slice of the failure facts: which players failed which criteria this pull, with counts and total damage). It is **not** `Gold.EncounterDetail` — that module reads 8 silver tables (`DamageDone`, `DamageTaken`, `DamageTakenEvent`, `Death`, `DebuffApplication`, `DefensiveBuffWindow`, `InterruptOpportunity`, `PlayerInfo`) plus `ObservedMechanics` (also silver), so reusing it on a gold-only DB would render empty silver-derived panels beside real facts. The rich detail page (deaths, roster, pull review, interrupt coverage, personal summary) is **out of scope** for the public mirror by the no-silver principle.

`rules.*` is **not** mirrored — `dim_mechanic_criterion` already snapshots spell/threshold/boss/mechanic_type/notes at promotion time, so the public view needs nothing from the rules schema.

### Upload unit: a per-encounter snapshot

Publish granularity is one encounter. The payload is a self-contained bundle so the public app can resolve identity independently of the parser's local surrogate `id`s:

```text
{
  schema_version: 1,
  encounter: {                      # gold.dim_encounter, operator-local fields stripped
    source_encounter_key,           # opaque SHA-256, the public identity (see below)
    wow_encounter_id, name, difficulty_id, difficulty_name, group_size,
    instance_id, start_time, end_time, success, fight_time_ms
    # OMITTED: source_file_path, source_head_sha256, start_byte, end_byte (operator-local; folded into the hash, never sent raw)
  },
  players:  [ {player_guid, player_name, class_id, spec_id} ],          # only those referenced by facts (+ __RAID__ sentinel)
  criteria: [ {criterion_key,        # deterministic business-identity hash, the public identity (see below)
               ruleset_id, ruleset_version, product, channel, build_version, build_key,
               spell_id, spell_name, mechanic_type,
               boss_encounter_id, boss_name, difficulty_id, threshold, notes, active} ],
  facts:    [ {player_guid, criterion_key,                              # referenced by stable keys, not surrogate ids
               ruleset_id, ruleset_version, product, channel, build_version, build_key,
               derivation_version, rebuilt_at, failure_count, total_damage} ]
}
```

### Stable keys for idempotent upsert (public side)

Surrogate `id`s differ across the two DBs **and** the parser's keys are unsafe to mirror directly (the review's blockers #3/#4). So the parser computes two opaque, deterministic keys and the public app upserts on them:

- **`source_encounter_key`** — `SHA-256(source_head_sha256 ‖ start_byte ‖ end_byte ‖ wow_encounter_id ‖ start_time)`. Why: `dim_encounter` makes `source_head_sha256`/`start_byte`/`start_time` all nullable (only `wow_encounter_id`+`name` are required), so a multi-column natural key over them is not reliably unique; and `start_time` alone is a weaker discriminator than the parser's byte-range identity (`EncounterIdentity` keys on source fingerprint + `start_byte`). Hashing the full byte-range identity preserves that strength while leaking none of it. Publishing an encounter missing the source-identity inputs is an **error**, not a null-keyed row.
- **`criterion_key`** — `SHA-256` over the **business identity** `(product, channel, build_key, boss_encounter_id, difficulty_id, spell_id, mechanic_type)` **plus a `criterion_semantics_hash`** over the canonicalized `threshold` and a per-mechanic `semantics_version` (bumped when a builder changes how failures are counted). Why semantics is in the key: a fact's count is only meaningful relative to the threshold that defined "failure," so threshold is part of fact identity — retuning `max_hits` must **fork a new public criterion row**, not mutate the existing one in place; otherwise un-republished facts get relabeled under the new definition (the same partial-republish hazard as `source_rule_id`, narrower). Cross-version grouping ("Arcane Expulsion regardless of threshold tweaks") is done **intentionally in the read model**, never by mutating the fact key dimension. Why **not** `source_rule_id`: that's the parser-local `rules.mechanic_criterion.id`, which the project explicitly allows to be reseeded/rebuilt; a reused id could relabel a *different* spell/mechanic. `notes` remains a mutable display attribute (updated on upsert, not in the key). **Open for re-review:** `active` is treated as operational state (excluded from the key — an inactive criterion produces no facts, so toggling it shouldn't fork identity); the review suggested including it.
- **player** — `player_guid` (already unique in `dim_player`).
- **fact** — `(source_encounter_key, player_guid, criterion_key)`.

Ingest is **transactional per encounter**: upsert dims by their stable keys, resolve them to the public surrogate ids, then **replace the encounter's full fact set** (so a rebuild that drops a player's failure removes the stale public row). Re-posting an unchanged snapshot is a no-op.

**Where the keys live (schema impact):** both `source_encounter_key` (on `gold.dim_encounter`) and `criterion_key` (on `gold.dim_mechanic_criterion`) are **real columns in both DBs**, computed deterministically when the gold row is written — the encounter key at gold-encounter build (from the importer's source identity), the criterion key at ruleset promotion into the dim. Public **unique-indexes** them as the upsert target; the parser stores them too so the outbox/serializer reference a stored value (and a parser-side unique index catches collisions early). These columns do **not** exist today (`dim_encounter` and `dim_mechanic_criterion` have neither), so phase 2 is an explicit schema phase: migrations add the columns + unique indexes (both DBs) and **backfill** existing rows. A `dim_encounter` row missing source-identity inputs cannot be keyed and therefore cannot be published (consistent with the publish-time error rule).

**Where `semantics_version` lives (don't let it drift):** each fact builder under `lib/we_go_next/gold/fact_failure/builders/` owns its own `@semantics_version` module attribute, exposed via `semantics_version/0`, **co-located with the counting logic it versions** — so the number sits in the same file you edit when you change how failures are counted, and a central `mechanic_type → semantics_version` resolver feeds the `criterion_semantics_hash`. Bumping is a one-line increment in the builder you just touched. This is distinct from the global `fact_failure.derivation_version` stamp (which marks *all* facts as needing rebuild): `semantics_version` is **per-mechanic-type** and feeds **criterion identity**. A guard test enumerates every supported `mechanic_type` and asserts each resolves to a `semantics_version`, so a new builder can't ship without declaring one — promoting the rule into a ratchet rather than relying on memory.

## Run-mode split

New runtime config `config :we_go_next, :mode, :parser | :public`, read via `WeGoNext.mode/0`, **defaulting to `:parser`** so local dev is unchanged.

### Supervision (`application.ex`)

```text
both modes:   Repo, {Phoenix.PubSub, ...}, Endpoint
parser only:  ImportTaskSupervisor, ImportWorker, FileWatcher   # gated behind mode == :parser
```

The Zig NIF parser is only ever invoked through `Importer`, which is only reachable from the parser-only children — so it's effectively dormant in public. This is a **failure mode worth a positive test** (review should-fix): a public-mode boot test asserts the parser children are absent, `/settings` is unavailable, and the public routes load without touching `CombatLogParser`.

### Routing / UI

One router, runtime-mode-guarded plugs (mode is runtime config, so routes can't be compiled away). **Public LiveViews are dedicated and gold-only — they do not reuse the parser's `EncounterLive.*` and never call `Accounts`** (the review found `EncounterLive.Show.mount/3` calls `Accounts.get_or_create_default_user/0`, which would create a parser-local `users` row in the public DB on first page load — violating the no-user-table decision).

- **Parser mode** — existing routes unchanged: `/`, `/encounters/:id`, `/failures`, `/settings`.
- **Public mode** — viewer surface under `/r/:slug`:
  - `:public_viewer` plug validates the slug (404 otherwise), then stores it in the session so in-app links don't repeat it.
  - **`PublicLive.Failures`** — the grouped failures summary. May reuse `FailureSummary.list_grouped_failures/1`+`group_by_player/1` (gold-only) **only after** confirming that read path and the LiveView wrapper are `Accounts`-free; otherwise a thin dedicated view. The readiness/diagnostics panel is omitted.
  - **`PublicLive.EncounterFailures`** — the NEW gold-only per-encounter failure breakdown (the `/r/:slug/encounters/:source_encounter_key` view), backed by the new gold-only read model. Not `EncounterLive.Show`.
  - **`PublicLive.Encounters`** — a gold-backed encounter list (from `dim_encounter`) to navigate into the per-encounter view. The parser's `EncounterLive.Index` (import/bronze-oriented, `Accounts`-coupled) stays parser-only.
  - `/settings` and all parser routes are unavailable in public mode (404).

## Upload mechanism (parser side)

- Add **`Req`** (no runtime HTTP client exists today; the only outbound call is a `:httpc` CLI mix task — do not reuse that pattern).
- New module `WeGoNext.Mirror`:
  - `encode_encounter_snapshot/1` — gold rows → the payload above, computing `source_encounter_key`/`criterion_key` and stripping operator-local fields.
  - `Mirror.Upload.publish(encounter_dim_id)` — POST to `<public>/api/ingest` with `Authorization: Bearer <token>`.
- **Trigger:** emit publish intent from **`Gold.RebuildEncounter.rebuild/2`** after the full gold rebuild succeeds (review should-fix — *not* directly from `FactFailure.Rebuilder`, which stays focused on fact-table replacement; `RebuildEncounter` is the documented gold-rebuild boundary). Enqueue onto a parser-only `Task.Supervisor`; publish failures must never break a rebuild.
- **Outbox** (because publish is automatic and the network is flaky): a `mirror_uploads` table keyed/**coalesced by `source_encounter_key`**, tracking `state` (`pending|published|stale|error`), `last_error`, `published_at`. Re-rebuild marks the row `stale` → re-publish. The worker processes with **bounded concurrency + rate limiting** so a mass rebuild can't storm the public endpoint. An optional `batch_id` is for observability only — never a public fact key.
- **Secrets:** store the ingest bearer token via the existing `Accounts.SecretBox` (PBKDF2 off `secret_key_base`) in a new encrypted `users` column, mirroring the `warcraft_logs_api_key_encrypted` + `*_set_at` pattern exactly. Public-app base URL stored alongside (plaintext setting).

## Public app: ingest + auth

- New `:api` scope (the pipeline already exists, unused): `POST /api/ingest`.
- **Ingest hardening — required v1 acceptance criteria** (not implementation notes; this is an internet-facing write endpoint, so a leaked token or retry loop must not churn the DB):
  - bearer token, **constant-time** compared against `INGEST_TOKEN` env; HTTPS only;
  - strict **`Content-Length` cap** + **JSON decode size/depth limit** (reject before parsing);
  - **`schema_version` reject** for anything unrecognized;
  - **transaction timeout** on the upsert;
  - **request logging by snapshot hash** (idempotency/replay visibility);
  - **rate limiting** at the endpoint or reverse-proxy layer.
- `Mirror.Ingest.upsert_snapshot/1` — the transactional stable-key upsert described above.
- **Viewer auth** — the shared-secret slug from `VIEWER_SLUG` env (rotatable on redeploy). The `:public_viewer` plug is the only gate; there is no user table.

## Deployment (Gigalixir)

Target is the existing Gigalixir account, app `we-go-next`. Today there is **no release config, no Dockerfile, and `runtime.exs` doesn't read `DATABASE_URL`** — all net-new.

- `mix.exs` — add a `releases/0`.
- `runtime.exs` (prod) — read `DATABASE_URL`, `POOL_SIZE`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT`, and the new `MODE` (→ `:mode`), `INGEST_TOKEN`, `VIEWER_SLUG`. Keep these env-driven so the platform stays swappable.
- **Build via Dockerfile, not buildpack.** Two repo facts force this: (1) the mix project lives in `we_go_next/`, not the repo root, which the stock Elixir buildpack doesn't expect; (2) the Zig NIF (`zigler`) needs the Zig toolchain at compile time, which the buildpack lacks. A Dockerfile installs Zig in the build stage and sets build context to `we_go_next/`; the runtime image carries the compiled `.so` (it loads but is never invoked in `:public`). Confirm the exact Gigalixir "enable Docker build" step at implementation time before relying on it.
- **Migrations:** use a boot-time release migrator (`WeGoNext.Release.migrate/0` run on app start), so no SSH key is needed and GitHub's secret surface stays at two credentials. (Alternative: `gigalixir-action@v0` + a `GIGALIXIR_SSH_PRIVATE_KEY` secret to run SSH migrations as an explicit CI step — rejected for the larger secret surface.)
- **DB:** Gigalixir-managed Postgres for public, injected as `DATABASE_URL` config. It runs the same migrations; only the gold tables are ever populated (empty silver/bronze tables are harmless). Optionally scope migrations later if the empty tables bother us.

## CI/CD (GitHub Actions → Gigalixir)

The pipeline gates every change and, on green `main`, deploys **only the public release** — the parser context is never deployed (it runs locally). One image; `MODE=public` selects behavior at runtime. This mirrors the `ui-o-matic` pattern (local gate mirrored by a `.github/workflows` job).

### Secret model — two tiers, kept apart

The central security decision: the app's runtime secrets **never enter GitHub.**

| Tier | Lives in | Values |
|---|---|---|
| Deploy-auth (lets CI trigger a deploy) | GitHub **Environment** (`production`) secrets | `GIGALIXIR_EMAIL`, `GIGALIXIR_API_KEY` |
| Runtime (the app's actual secrets) | **Gigalixir config** (`gigalixir config:set`) | `SECRET_KEY_BASE`, `DATABASE_URL` (auto), `INGEST_TOKEN`, `VIEWER_SLUG`, `MODE=public` |

A GitHub compromise can redeploy code but does not surrender the ingest token, viewer slug, or DB URL.

### GitHub-side hardening

- **Environment-scope the deploy secrets** to `production` (not repo-wide), with protection rules: restrict to `main`, optional required reviewer. The test job and PR runs then cannot read the API key — only the job declaring `environment: production` gets it.
- **Guard the deploy job:** `if: github.ref == 'refs/heads/main' && github.event_name == 'push'` + `needs: test`.
- **`permissions: contents: read`** at workflow top.
- **SHA-pin all actions** (`gigalixir/gigalixir-action`, `actions/checkout`, `erlef/setup-beam`, `actions/cache`) to commit SHAs — the action receives the API key as input, so pin to a commit, not a movable tag.
- **Never deploy from `pull_request`/`pull_request_target`** — keeps secrets away from fork PRs.
- **Honest limitation:** the Gigalixir API key is account-wide (no per-app token) and Gigalixir has no OIDC, so a long-lived secret is unavoidable. Mitigate with the environment gate + SHA-pinning, and rotate the key if exposed.

### Pipeline shape

- **`test` job** (PR + push): `setup-beam` → cache `deps`/`_build`/`~/.cache/zigler` → Postgres service container → `mix deps.get` → `mix zig.get` (provision Zig for the NIF) → `format --check-formatted` → `compile --warnings-as-errors` (the zero-warnings gate) → `credo` → `mix test`. Runs in `we_go_next/`.
- **`deploy` job** (push to `main`, `needs: test`, `environment: production`): `gigalixir/gigalixir-action@<sha>` with `gigalixir_email`/`gigalixir_api_key`/`app_name: we-go-next` (v1 masks the key in logs and cleans up credentials after the run).
- **Wallaby feature tests:** open question — run in the blocking `test` job, or split to a separate/nightly job (matching `ui-o-matic`'s blocking-vs-report-only split) since they need Chrome and are the usual flake source.

### Putting the key in securely (operator runs these)

```bash
gh api -X PUT repos/rpmessner/we_go_next_dev/environments/production
printf %s "$GIGELIXIR_API_KEY" | gh secret set GIGALIXIR_API_KEY --env production   # stdin keeps it out of shell history
gh secret set GIGALIXIR_EMAIL --env production --body '<account email>'
```

(Local env var is spelled `GIGELIXIR_`; the GitHub secret uses the canonical `GIGALIXIR_` the action expects.)

## Security / privacy

- Strip `source_file_path`, `source_head_sha256`, and byte offsets from every payload — they fold into `source_encounter_key` as a hash and are never sent raw (operator-local, non-analytic).
- `player_guid` is a WoW GUID for the raiders' own characters; the shared-link slug is the privacy gate. Failure counts are mildly socially sensitive — the link is the agreed boundary.
- Ingest token and viewer slug are both rotatable via env + redeploy.

## Rough phasing

Tracked on Linear: project [we_go_next — Public Gold Mirror](https://linear.app/wow-ui-o-matic/project/we-go-next-public-gold-mirror-3bbd3de9c0eb) (team WOW), issues **WOW-181 … WOW-188** (one per phase below).

1. **Run-mode foundation** — `:mode` config + `WeGoNext.mode/0`, gate the parser supervision trio, default `:parser` (zero local behavior change). `runtime.exs` gains `DATABASE_URL`/`MODE`. **Public-mode boot test**: parser children absent, `/settings` 404, public routes load without `CombatLogParser`.
2. **Mirror-key schema + serializer** — migrations adding `source_encounter_key` to `gold.dim_encounter` and `criterion_key` (incl. the `criterion_semantics_hash`) to `gold.dim_mechanic_criterion`: columns + unique indexes (both DBs) + backfill of existing rows. Deterministic key computation (encounter key at gold build, criterion key at promotion); per-builder `@semantics_version` + `mechanic_type → semantics_version` resolver. `Mirror.encode_encounter_snapshot/1` + field stripping. Unit tests: key determinism; **threshold change → new `criterion_key`**; **`semantics_version` bump → new `criterion_key` with threshold unchanged**; the **every-mechanic-has-a-`semantics_version` guard test**; payload shape.
3. **Gold-only public read models** — the NEW per-encounter failure-breakdown read model + a gold-backed encounter list; confirm the failures-summary read path is `Accounts`-free. `DataCase` tests asserting no silver/`Accounts` access.
4. **Public ingest** — `:api` scope, the full ingest-hardening acceptance criteria, `Mirror.Ingest.upsert_snapshot/1` (transactional, stable-key upsert, fact replacement, resolve keys → surrogate ids). `DataCase` + endpoint tests including replay/oversize rejection.
5. **Parser upload + outbox** — add `Req`, `Mirror.Upload`, `mirror_uploads` outbox (coalesced by `source_encounter_key`, bounded concurrency/rate limit), SecretBox token column, publish intent from `Gold.RebuildEncounter.rebuild/2`.
6. **Public viewer surface** — `/r/:slug` pipeline + `PublicLive.{Failures,Encounters,EncounterFailures}` (dedicated, gold-only, no `Accounts`). Route/LiveView tests for public mode (these are the blocking gate, not Wallaby).
7. **Release + deploy artifact** — `releases/0`, `runtime.exs` prod config, `WeGoNext.Release.migrate/0`, Dockerfile (Zig in build stage, context `we_go_next/`), Gigalixir-managed Postgres, runtime secrets set via `gigalixir config:set`.
8. **CI/CD pipeline** — `.github/workflows/ci.yml` (`test` + gated `deploy` jobs), `production` GitHub Environment with the two deploy-auth secrets, SHA-pinned actions. Wallaby as a separate non-blocking job, promoted once stable. End-to-end smoke test: rebuild locally → snapshot uploads → row appears on the Gigalixir public app.

## Open risks

- **Migration coupling** — public DB runs all migrations including silver/bronze. Acceptable for v1 **only because** public mode is route/supervision-gated and tested (phase 1/6); otherwise scope migrations or split repos before deploy.
- **Zig in the public image** inflates build time/size for a never-used artifact; revisit if it becomes painful (conditional NIF exclusion is the harder fallback).
- **Account-wide Gigalixir API key** — no per-app scoping and no OIDC; the GitHub Environment gate + SHA-pinned actions + rotation are the only mitigations.
- **Gigalixir Docker-build enablement + subdir context** — unverified exact mechanism; confirm before the deploy phase rather than assuming it works.

## Resolved by review (2026-06-27)

- ~~Per-encounter detail is gold-only~~ — **false**; `EncounterDetail` reads 8 silver tables. Replaced with a NEW gold-only failure-breakdown read model; rich detail is out of scope.
- ~~Reuse `EncounterLive.Show` in public~~ — it calls `Accounts.get_or_create_default_user/0`; public LiveViews are now dedicated and `Accounts`-free.
- ~~`source_rule_id` as criterion mirror key~~ — unsafe across rules reseeds; replaced with business-identity `criterion_key`.
- ~~`(source_head_sha256, wow_encounter_id, start_time)` encounter key~~ — nullable/weak; replaced with opaque `source_encounter_key` hash over the full byte-range identity.

### Round 2 (2026-06-27)

- ~~`criterion_key` excludes `threshold` (retune updates in place)~~ — relabels un-republished facts under the new definition; `criterion_key` now folds in a `criterion_semantics_hash` (canonicalized threshold + per-mechanic semantics version), so a retune **forks** a new public criterion row. Cross-version grouping moved to the read model. (`active` left out of the key — flagged open for re-review.)
- **Mirror-key schema made explicit** — neither key column exists today; phase 2 now specifies the migrations, unique indexes, both-DB placement, and backfill, with a publish-time error for un-keyable encounters.
- **Round-1 review brief superseded** — `PUBLIC_MIRROR_REVIEW_BRIEF.md` is marked superseded so a re-reviewer targets the reworked plan, not the original bets.
