# Public Gold Mirror Plan Review

Date: 2026-06-27

## Blocking

### Per-encounter detail is not served by the four mirrored gold tables

Targets: bet #1, v1 view scope.

The design says the public app can serve failures summary plus per-encounter detail from only `gold.dim_encounter`, `gold.dim_player`, `gold.dim_mechanic_criterion`, and `gold.fact_failure`. That is false for the current code. `WeGoNext.Gold.EncounterDetail` aliases and queries almost every silver projection: `DamageDone`, `DamageTaken`, `DamageTakenEvent`, `Death`, `DebuffApplication`, `DefensiveBuffWindow`, `InterruptOpportunity`, and `PlayerInfo` in `we_go_next/lib/we_go_next/gold/encounter_detail.ex:15`. Its `get/2` result always includes silver-backed counts, roster, deaths, pull review, interrupt coverage, and personal summary in `we_go_next/lib/we_go_next/gold/encounter_detail.ex:62`.

The LiveView also calls `ObservedMechanics.for_encounter/1` on mount in `we_go_next/lib/we_go_next_web/live/encounter_live/show.ex:26`; that read model explicitly starts from silver rows and queries `DamageTakenEvent`, `DebuffApplication`, and `InterruptOpportunity` in `we_go_next/lib/we_go_next/gold/observed_mechanics.ex:5` and `we_go_next/lib/we_go_next/gold/observed_mechanics.ex:22`.

If public runs all migrations but only receives gold rows, this page will not be a valid public detail page. It will render many zero/empty silver-derived panels beside real fact rows, which is an incorrect public view rather than a clean gold-only experience.

Suggested change: make v1 public detail a separate gold-only read model and LiveView surface, or reduce v1 public scope to the failures summary until an intentionally mirrored detail contract exists. Do not reuse `EncounterLive.Show` in public mode unless it is split so the public path never calls silver-backed sections.

### The current public route reuse violates the "no user accounts" decision

Targets: viewer access decision, bet #1.

`EncounterLive.Show.mount/3` calls `Accounts.get_or_create_default_user/0` before loading the encounter in `we_go_next/lib/we_go_next_web/live/encounter_live/show.ex:21`. That function creates a `users` row with a default local WoW logs path if none exists in `we_go_next/lib/we_go_next/accounts.ex:27`. This is a parser-local settings model, not a public shared-link viewer model.

In public mode, reusing this LiveView would mutate the public DB on first page load and reintroduce local operator settings concerns. It also undermines the design's statement that the public viewer has no user table.

Suggested change: public LiveViews should not call `Accounts`. Pass no `character_name`, omit personal-player preference, and keep parser settings routes/components out of the public route tree.

### `source_rule_id` is not a safe criterion mirror key across reseeds or partial republishes

Targets: bet #3, natural-key contract.

The proposed public criterion key is the parser-local `rules.mechanic_criterion.id`. The current gold schema enforces uniqueness on that value in `we_go_next/priv/repo/migrations/20260517001900_add_rules_identity_to_gold_dim_mechanic_criterion.exs:11`, and the Ecto changeset mirrors that with `unique_constraint(:source_rule_id)` in `we_go_next/lib/we_go_next/gold/dim_mechanic_criterion.ex:69`.

That key is only stable while the parser DB is never reset and rules are never reseeded into different row ids. The project explicitly allows rules to be refined and rebuilt rather than preserving historical rule archaeology in `docs/ARCHITECTURE.md:122`. If the local rules table is rebuilt and a reused `source_rule_id` now means a different spell/mechanic, a public upsert by `source_rule_id` can mutate the global criterion dimension while old public facts for encounters that were not republished still point at that same public criterion row. The result is stale facts relabeled as a different criterion.

Suggested change: do not use `source_rule_id` as the public natural key. Add a stable authored criterion key to the code-defined raid catalog and promoted gold snapshot, or use a business key that excludes parser-local surrogate ids. At minimum include product/channel/build scope, boss encounter id, difficulty scope, spell id, mechanic type, and a threshold/semantics version or criterion slug. Facts should reference the public criterion resolved by that stable key.

### Encounter identity needs an opaque source encounter key, not `(source_head_sha256, wow_encounter_id, start_time)`

Targets: bet #2.

The local medallion identity bridge uses `source_head_sha256` or source file path plus `start_byte`, not start time. `EncounterIdentity` documents that identity in `we_go_next/lib/we_go_next/gold/encounter_identity.ex:7`, and queries by `start_byte` plus source fingerprint/path in `we_go_next/lib/we_go_next/gold/encounter_identity.ex:57`. The importer follows the same shape when fetching existing gold encounter rows in `we_go_next/lib/we_go_next/importer.ex:327`.

The design strips `start_byte` and replaces it with `start_time`. But `gold.dim_encounter` does not require `source_head_sha256`, `start_time`, or `start_byte`; only `wow_encounter_id` and `name` are required in `we_go_next/lib/we_go_next/gold/dim_encounter.ex:51`. A public unique key containing nullable fields will not provide reliable idempotency, and start time is a weaker discriminator than the parser's current byte-range identity.

Suggested change: publish an opaque `source_encounter_key`, for example a SHA-256 over parser-local source identity plus `start_byte`, `end_byte`, `wow_encounter_id`, and `start_time`. Store and unique-index that key in public. This preserves privacy without weakening idempotent replacement.

## Should-Fix

### The outbox should attach to `Gold.RebuildEncounter`, not only `FactFailure.Rebuilder`

Targets: bet #4, publish trigger.

The documented boundary for gold rebuilds is `WeGoNext.Gold.RebuildEncounter`; docs say importers and UI should call that instead of direct fact modules in `docs/ARCHITECTURE.md:103`, and the current wrapper calls fact rebuild in `we_go_next/lib/we_go_next/gold/rebuild_encounter.ex:29`. If auto-publish is wired directly into `FactFailure.Rebuilder`, it will be harder to keep future gold outputs and rebuild summaries coherent.

Suggested change: emit mirror publish intent from `Gold.RebuildEncounter.rebuild/2` after the full gold rebuild succeeds and returns a summary. Keep `FactFailure.Rebuilder` focused on fact table replacement.

### Public mode needs a positive boot test that parser-only processes and NIF paths stay dormant

Targets: bet #5.

Today the application always starts `ImportTaskSupervisor`, `ImportWorker`, and `FileWatcher` in `we_go_next/lib/we_go_next/application.ex:10`. The parser NIF module itself uses `use Zig` in `we_go_next/lib/we_go_next/combat_log_parser.ex:14`. The plan says these are harmless in public after mode-gating, but this needs an explicit release/boot test because the failure mode is a deploy that starts parser-only processes or loads parser-only code unexpectedly.

Suggested change: add a public-mode application test that boots supervision with `MODE=public` and asserts the parser children are absent, `/settings` is unavailable, and the public routes can load without importing `CombatLogParser` paths.

### Ingest protection should include replay and size limits in v1

Targets: bet #6, open question #4.

Bearer auth plus schema-version validation is necessary but too thin for an internet-facing write endpoint. The design already mentions oversized payload rejection in `docs/PUBLIC_MIRROR_DESIGN.md:112`; it should be a required v1 acceptance criterion, not an implementation note. Without a content-length cap and idempotency/replay metadata, a leaked token or accidental retry loop can churn the public DB.

Suggested change: require `Content-Length` cap, JSON decode limit, schema-version reject, constant-time token compare, request id or snapshot hash logging, and rate limiting at either the endpoint or reverse-proxy layer.

## Consider

### Running every migration in public creates unnecessary data surface

Open question #3.

Running all migrations is probably acceptable for v1 if public mode never exposes parser routes and the DB user has normal app privileges only. But empty `users`, `combat_log_files`, `silver.*`, `rules.*`, and source-data tables make accidental coupling easier and make security review noisier.

Suggested change: defer scoped migrations for v1 only if public-mode route and supervision tests exist. Otherwise, scope migrations or split repos before deploy.

### Wallaby should not block deploy until public-mode coverage is stable

Open question #2.

Feature tests are valuable here, but current UI reuse is exactly where the plan is risky. Start with focused LiveView/router tests for public mode in the blocking gate, then add Wallaby as a separate required job only after it is stable under CI Chrome.

## Answers

Criterion natural key: switch away from `source_rule_id`. Prefer a stable authored criterion key or a business key with build/scope/type/spell plus a semantics version/hash. Parser-local ids are not safe public identity.

Wallaby in CI: do not make Wallaby the first blocking gate. Block on unit, integration, route, and LiveView tests for public mode; add Wallaby in a separate job and promote it once stable.

Migration scoping: public can run all migrations only if public mode is strongly route/supervision gated and tested. Scoped migrations are cleaner, but not the first thing to build.

Ingest endpoint abuse: minimum v1 is bearer token with constant-time compare, HTTPS, schema-version reject, strict payload size limit, JSON decode limit, transaction timeout, request logging by snapshot hash, and basic rate limiting.

Publish granularity: per-encounter is the right unit, but mass rebuild needs bounded queue behavior. The outbox should coalesce by encounter key, mark stale on rebuild, and process with concurrency/rate limits. A batch id is useful for observability but should not be the public fact key.

## Verdict

Needs rework before build. The four-gold-table mirror can work for a failures summary, but the current per-encounter page and identity contract are not ready for public-mode implementation.
