# Public Gold Mirror — Review Brief

> ⚠️ **SUPERSEDED (2026-06-27).** This brief described the *original* plan. It has been reviewed twice and the design was reworked in response — see [`sessions/2026-06-27_public_mirror_plan_review.md`](sessions/2026-06-27_public_mirror_plan_review.md) and the *Resolved by review* section of [`PUBLIC_MIRROR_DESIGN.md`](PUBLIC_MIRROR_DESIGN.md). **Do not review the bets below as current** — several (the "four gold tables serve detail" claim, `source_rule_id`, the encounter natural key) are already resolved.
>
> **For a re-review, target the reworked design's still-open points instead:**
> 1. `criterion_key` semantics — is folding `criterion_semantics_hash` (threshold + per-mechanic `semantics_version`) into the key correct, and should `active` be in the key or stay operational state?
> 2. The mirror-key migrations/backfill (phase 2) — column placement in both DBs, unique indexes, and the publish-time error for un-keyable encounters.
> 3. The new gold-only per-encounter read model + dedicated `Accounts`-free public LiveViews — verify they touch no `silver.*`/`Accounts`.

Status: **superseded** (round-1 review complete; plan reworked). Companion to [`PUBLIC_MIRROR_DESIGN.md`](PUBLIC_MIRROR_DESIGN.md) (read that first — it is the full design). This document exists so a reviewing agent can critique the plan **before implementation begins**.

## How to use this document

You are reviewing a *design*, not code — nothing here is built yet. Your job is to find where the plan is wrong, under-specified, or risky, not to rubber-stamp it. Read `PUBLIC_MIRROR_DESIGN.md` in full, verify the claims below against the actual code where you can, and respond against the [review rubric](#review-rubric). Prefer concrete, falsifiable findings ("X will break because Y, here's the file") over vibes.

Ground rules:

- **Locked decisions** (next section) are settled product calls. Don't relitigate them unless you've found a *fatal* problem — and if so, say explicitly why it's fatal.
- **Technical bets** are where scrutiny is most wanted. Each states what we believe and what would falsify it. Try to falsify them.
- Verify against code, don't trust this summary. Key paths are cited so you can check.

## What is being built (one paragraph)

One Phoenix codebase runs in two modes selected by `config :we_go_next, :mode, :parser | :public`. The **parser** mode is the existing local app (watches/imports combat logs, builds silver/gold). The **public** mode is a hosted, read-only mirror on Gigalixir that serves only the four `gold.*` analysis tables to raid members behind a shared-secret URL. After each `fact_failure` rebuild, the parser auto-publishes a per-encounter snapshot (gold rows only, operator-local fields stripped) over HTTP to a public ingest endpoint, which upserts by natural key. No raw logs, silver, or bronze ever leave the local machine.

## Locked decisions (do not relitigate without a fatal finding)

| Decision | Choice |
|---|---|
| Two run contexts in one codebase | `:mode` config, default `:parser` |
| Viewer access | Shared-secret link `/r/<slug>`, no user accounts |
| Publish trigger | Automatic after each `fact_failure` rebuild |
| Mirrored data | Four `gold.*` tables only; `rules.*` not mirrored |
| Hosting | Gigalixir (`we-go-next` app), Dockerfile build |
| CI/CD | GitHub Actions, deploy on green `main` |
| v1 view scope | Failures summary + per-encounter detail |

## Technical bets that need scrutiny

Each bet = the claim, why we believe it, and what would falsify it. **Attack the falsifiers.**

1. **The public view is fully served by four gold tables.** — ❌ **RESOLVED/STALE:** review found `Gold.EncounterDetail` reads 8 silver tables; v1 detail is now a NEW gold-only read model, not `EncounterDetail`. Bet no longer current.
   - Believe: `Gold.FailureSummary.list_grouped_failures/1` + `group_by_player/1` (the `/failures` view) and `Gold.EncounterDetail` (the per-encounter view) read only `gold.dim_encounter`, `gold.dim_player`, `gold.dim_mechanic_criterion`, `gold.fact_failure` plus code-defined `GameData` catalogs.
   - Falsify: find any read path reachable in `:public` mode that touches `silver.*`, `rules.*`, or `public.*`. The readiness/diagnostics panel (`FailureSummary.readiness/1`, `zero_fact_rule_diagnostics/1`) *does* hit silver+rules and is explicitly disabled in public — confirm nothing else does, and that disabling it is clean (no crash, sensible empty UI).

2. **Per-encounter snapshots can be upserted idempotently by natural key.** — ⚠️ **PARTIALLY STALE:** the specific keys below were replaced with opaque `source_encounter_key`/`criterion_key` hashes; the *idempotency/concurrency/orphan* falsifiers remain worth checking against the new contract.
   - Believe: surrogate `id`s differ across the two DBs, so we key on `(source_head_sha256, wow_encounter_id, start_time)` for encounter, `player_guid` for player, `source_rule_id` for criterion, and the composite for facts. Ingest replaces the encounter's full fact set so rebuilds that *drop* a failure clean up the mirror.
   - Falsify: a case where this natural key collides or fails to identify a unique pull; a rebuild sequence where fact replacement leaves orphaned dim rows or stale facts; concurrency between two uploads for the same encounter.

3. **`source_rule_id` is an adequate criterion natural key.** — ❌ **RESOLVED/STALE:** replaced with business-identity `criterion_key` (+ semantics hash). See open re-review point #1 in the banner.
   - Believe: it's the parser-local `rules.mechanic_criterion.id`, stable because one operator owns both DBs.
   - Falsify: any scenario (re-seeded rules, ruleset re-promotion, a second operator) where the same `source_rule_id` means different criteria across a publish boundary. Is the business key `(ruleset_id, spell_id, boss_encounter_id, difficulty_id)` strictly safer at acceptable cost?

4. **Auto-publish + an outbox is the right reliability model.**
   - Believe: a `mirror_uploads` table tracking per-encounter `pending|published|stale|error` + retry handles network flakiness without coupling publish to rebuild success.
   - Falsify: simpler sufficient alternative; or a failure mode the outbox misses (e.g. partial snapshot upload, public app ahead of/behind parser, retry storms).

5. **The Zig NIF is harmless dead weight in the public image.**
   - Believe: `:public` never reaches `Importer`/`CombatLogParser`; the NIF `.so` compiles in the Docker build stage and loads but is never invoked.
   - Falsify: the NIF loading at module-load time crashes or blocks boot in public; or the build can't produce the `.so` without the parser-only deps.

6. **The two-tier secret model is sound.**
   - Believe: GitHub holds only `GIGALIXIR_EMAIL` + `GIGALIXIR_API_KEY` (in a `production` Environment); all runtime secrets live in `gigalixir config:set`; SHA-pinned actions + environment gate mitigate the account-wide key.
   - Falsify: a path where a runtime secret leaks into GitHub or logs; a CI trigger that exposes the deploy secret to a PR/fork; a weakness in the shared-slug viewer gate (e.g. slug in referer/logs, no rate-limit on ingest bearer check).

## Open questions we explicitly want a recommendation on

1. **Criterion natural key** — keep `source_rule_id`, or switch to the business key? (bet #3)
2. **Wallaby in CI** — run feature tests in the blocking gate, or split to a separate/nightly job?
3. **Migration scoping** — let the public DB run all migrations (empty silver/bronze tables) or scope them? Worth doing in v1 or deferring?
4. **Ingest endpoint abuse** — what's the minimum viable protection beyond the bearer token (rate limit, payload size cap, schema-version reject)? Are we missing anything?
5. **Publish granularity** — per-encounter is the proposed unit. Is per-rebuild-batch ever needed (e.g. a full re-derivation of all encounters at once)? How does the outbox behave under a mass rebuild?

## Code surfaces to verify claims against

- Gold schemas: `lib/we_go_next/gold/{dim_encounter,dim_player,dim_mechanic_criterion,fact_failure}.ex`
- Read models: `lib/we_go_next/gold/failure_summary.ex`, `lib/we_go_next/gold/encounter_detail.ex`
- Read view: `lib/we_go_next_web/live/failure_live/index.ex`, `lib/we_go_next_web/live/encounter_live/show.ex`
- Supervision: `lib/we_go_next/application.ex` (parser trio: `ImportTaskSupervisor`, `ImportWorker`, `FileWatcher`)
- Rebuild trigger point: `lib/we_go_next/gold/fact_failure/` (rebuilder + builders)
- Secrets pattern to reuse: `lib/we_go_next/accounts/secret_box.ex`, `accounts/user.ex` (`warcraft_logs_api_key_encrypted`)
- Config/runtime: `config/runtime.exs` (currently no `DATABASE_URL`), `mix.exs` (no `releases/0`; `zigler` dep)

## Review rubric

Respond with findings grouped by severity. For each finding give: the claim/bet it targets, why it's wrong or risky, the evidence (file/line or scenario), and a concrete suggested change.

- **Blocking** — would cause data loss, a security leak, a failed deploy, or an incorrect public view. Must be resolved before building.
- **Should-fix** — a real weakness with a cheaper/safer alternative; not fatal but wrong to ignore.
- **Consider** — judgment calls, future-proofing, style. Take or leave.
- **Answers** — a direct recommendation on each of the [open questions](#open-questions-we-explicitly-want-a-recommendation-on).

End with a one-line verdict: **ready to build / build after blocking fixes / needs rework**.

## Where to put feedback

Write the review to `docs/sessions/<date>_public_mirror_plan_review.md` (a new session log — do not edit this brief or the design doc). Link it back here when done.
