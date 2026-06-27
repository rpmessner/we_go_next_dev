# Architecture

## System Shape

WeGoNext is a Phoenix LiveView application backed by PostgreSQL and a Zig NIF combat-log parser. It imports WoW combat logs, projects deterministic analytics rows, and serves medallion-backed UI views.

```text
WoW combat logs
  -> Bronze operational catalog
  -> Silver encounter projections
  -> Gold dimensions/facts
  -> LiveView read models
```

The old analyzer-cache UI path has been pruned from active routing. New user-facing analytics should query silver/gold/rules read models, not resurrect cached analyzer JSON or legacy public criteria tables.

## Layers

### Bronze

Bronze owns raw operational inputs and provenance.

- Raw combat logs remain files on disk.
- `public.combat_log_files` tracks file path, size, mtime, source, head fingerprint, and `last_parsed_byte`.
- `public.encounters` is transitional import bookkeeping: encounter boundaries, byte offsets, and basic encounter metadata.
- Live logs and Warcraft Logs archive files are both supported:
  - `WoWCombatLog-*.txt`
  - `warcraftlogsarchive/Archive-WoWCombatLog-*.txt`
- Archive reconciliation preserves the logical `combat_log_files` row when the Warcraft Logs uploader moves a file.

`WeGoNext.FileWatcher` is the current-log coordinator used by the UI and import
flow. In the current runtime it also polls the tracked file and starts
supervised sync tasks for appended completed encounters. The Reactor/Oban
refactor keeps the current-log pointer and scheduling trigger, but moves sync
execution and medallion builds into durable jobs.

### Silver

Silver owns deterministic projections under the `silver` PostgreSQL schema. Most silver tables are encounter-grain aggregates or compact event-like observations, not raw combat-log storage.

Current tables:

- `silver.damage_taken`
- `silver.damage_taken_event`
- `silver.damage_done`
- `silver.death`
- `silver.interrupt_opportunity`
- `silver.debuff_application`
- `silver.player_info`

Silver rows are keyed by `encounter_dim_id`, not legacy `public.encounters.id`. Projection currently happens in Elixir from normalized events returned by `CombatLogParser.parse_events/4`; the parser owns byte scanning and event normalization.

Silver persistence is idempotent by natural key. Each insert batch is deduplicated by the same conflict target used by `Repo.insert_all/3`, then upserted.

#### Event-Grain Policy

Silver is allowed to store event-grain rows only when a named downstream workflow needs individual events. It is not a general combat-log archive.

The previous `encounter_events` design stored broad normalized combat-log events in Postgres and then read them back into analyzers. That created raw-event volume without producing clean fact/dimension read models. The current medallion shape keeps raw logs in bronze and writes only typed silver projections that serve rules, facts, review, or UI queries.

`silver.damage_taken_event` is the deliberately narrow event-grain observation table. It stores one row per player-targeted damage taken hit for these event families:

- `SPELL_DAMAGE`
- `SPELL_PERIODIC_DAMAGE`
- `SWING_DAMAGE`
- `RANGE_DAMAGE`
- `ENVIRONMENTAL_DAMAGE`

This means multiple hits from the same spell become multiple rows. The table does not store player damage done, healing, casts, resources, buffs, or generic raw event payloads. It exists for rule review, classifier evidence, and future facts that need to inspect specific hits. The aggregate `silver.damage_taken` table remains the fact input for current avoidable failure counts.

Deaths, debuff applications, and interrupt opportunities are already stored at event-like grains. They are not duplicated into a generic raw-event table.

Before adding another event-grain silver table, name the downstream workflow and confirm that aggregate silver, existing event-like tables, or reparsing bronze logs would not be sufficient. If volume becomes a problem, tighten event-grain damage storage before expanding it: likely by NPC-source filtering, tank-melee exclusion, curated rule spell scoping, partitioning, or retention.

Known semantics gap: `silver.interrupt_opportunity` currently treats every NPC `SPELL_CAST_SUCCESS` as `success = false`. That is an observed cast, not necessarily a confirmed missed interrupt opportunity. Until task `#61` lands, UI labels and gold builders should avoid presenting these rows as authoritative missed interrupts.

### Gold

Gold owns analytic dimensions and facts under the `gold` schema.

Current dimensions:

- `gold.dim_encounter` — analytics encounter grain.
- `gold.dim_player` — conformed player dimension sourced from `silver.player_info`.
- `gold.dim_mechanic_criterion` — promoted snapshot of authored rule rows.

Current fact:

- `gold.fact_failure` — mechanic failures by encounter, player/sentinel, and criterion snapshot.

`gold.fact_failure` currently supports:

- `avoidable`: sums player damage taken by matching spell and fails when hit count exceeds `threshold.max_hits`.
- `interrupt`: counts missed interrupt opportunities and attributes them to the `__RAID__` sentinel player.

The public fact API is `WeGoNext.Gold.FactFailure.rebuild_for_encounter/2`. The rebuild implementation is split into:

- `WeGoNext.Gold.FactFailure.Rebuilder`
- `WeGoNext.Gold.FactFailure.RuleSelector`
- `WeGoNext.Gold.FactFailure.Query`
- `WeGoNext.Gold.FactFailure.Builders.*`

Encounter-level gold rebuilds should go through `WeGoNext.Gold.RebuildEncounter`, not direct fact-module calls from importers or UI code.

### Rules

Rules are business configuration in the `rules` schema.

- `rules.ruleset` supports `draft`, `active`, and `archived`.
- `rules.mechanic_criterion` stores authored mechanic criteria.
- `gold.dim_mechanic_criterion` stores promoted authored criteria used by
  `gold.fact_failure`.

There is currently exactly one active ruleset globally. Backfills and tests may pass an explicit `ruleset_id`.

Threshold semantics are intentionally narrow:

- `avoidable`: `threshold["max_hits"]` non-negative integer.
- `interrupt`: optional `threshold["must_interrupt"]`, defaulting to true.
- `soak`, `spread`, `stack`, `tank_mechanic`, `healer_mechanic`: allowed only with empty thresholds until fact semantics are implemented.

Rules are allowed to be refined as the team learns. For the local coaching loop,
rebuilding gold facts from current rules is preferred over preserving historical
rule archaeology.

### Source Data and Mechanic Sources

Patch-aware source data is separate from combat-log bronze.

Current source-data groundwork:

- `source_data.source_import`
- `source_data.dbm_mechanic_candidate`
- `source_data.spell_reference`
- `source_data.encounter_reference`
- `source_data.encounter_spell_reference`
- `source_data.wowanalyzer_timeline_candidate`
- `source_data.warcraft_logs_api_fetch`
- `WeGoNext.SourceData.DBM.Parser`
- `WeGoNext.SourceData.WowAnalyzer.Parser`

DBM imports create parsed source rows with source file, line number, module metadata, warning constructor, role filters, labels, comments, confidence, and review status. The parser is a focused static Lua tokenizer/call extractor for DBM declaration forms, not Lua execution. Tree-sitter Lua was evaluated as a broader AST option, but the current narrow Elixir parser is sufficient for `DBM:NewMod`, module metadata setters, `mod:NewSpecialWarning*`, and warning `SetAlert` calls without adding a native parser dependency. These rows are source annotations, not active rules. They do not write gold facts directly.

WowAnalyzer timeline imports create parsed source rows from local raid boss timeline metadata such as `src/game/raids/vs_dr_mqd`. Rows capture encounter id/name, timeline type (`ability` or `debuff`), event type (`cast`, `begincast`, `summon`, `debuff`, or `buff`), spell id, comment-derived mechanic hints, source file/line, repository revision, and repository license. These rows are also annotations only; they do not call WowAnalyzer runtime code and do not write active rules, promoted criterion snapshots, or facts.

Warcraft Logs API imports write flat JSON bronze artifacts under the local bronze root (`var/bronze/warcraft_logs` by default) and catalog them in `source_data.warcraft_logs_api_fetch`. Rows capture report code, fight id, source URL, query metadata, request parameters, fetch timestamp, request hash, response hash, artifact path/hash/size, raw JSON payload, and provenance metadata. These rows are separate from `combat_log_files`; local WoW combat logs remain the parser input, while Warcraft Logs rows are used only for validation and investigation.

The first WCL validation read model compares local `silver.damage_done` player totals against WCL damage-done table entries for a matching report/fight. It is a sanity-check path for parser/projection math and does not mutate silver, gold, rules, or imported WCL evidence.

Warcraft Logs credentials are local user settings. The client name is stored as configuration metadata; the API key is encrypted with the Phoenix endpoint secret before persistence and is only decrypted when a fetch workflow needs it. Imported `combat_log_files` can store an associated WCL report URL, parsed report code, and optional fight id so validation workflows can start from a local log row rather than copied CLI arguments.

Spell, encounter, and encounter-spell references are conformed, build-scoped source-data dimensions used by rules, observed-mechanic previews, and gold promotion code to resolve display names and encounter scope without relying on static JSON names. Reference rows carry product, channel, build key/version, locale, source system, source priority, optional `source_import_id`, and metadata. Retail, beta, and PTR rows coexist by channel/build scope; lookups prefer lower `source_priority` values within an explicit build scope.

Reference metadata is imported from local JSON exports through `WeGoNext.SourceData.import_reference_metadata_file/2` or `mix wgn.import_reference_metadata`. The importer accepts narrow spell-id/name maps and bundles with `spells`, `encounters`, and optional `encounter_spells`; imported relationships remain source annotations and do not activate rules or write facts.

Current product direction has shifted away from source-row review as a user-facing
workflow. Source-data rows should be treated as source annotations attached to
spells observed in local combat logs. The intended path is:

```text
observed silver spell/mechanic rows
  -> source annotations from DBM, BigWigs, WowAnalyzer, journal data, guides, reminders
  -> code-defined raid mechanic catalogs
  -> synced editable rules for supported mechanic semantics
  -> gold rebuild
  -> encounter preview and failure facts
```

The source hierarchy and constraints are documented in
[`MECHANIC_SOURCE_STRATEGY.md`](MECHANIC_SOURCE_STRATEGY.md). New UI should use
language like observed mechanics, source annotations, and rule status.

## Current Import Flow

```text
ImportWorker
  -> Importer.import_log/3
  -> CombatLogParser.scan_boundaries/2
  -> public.encounters
  -> gold.dim_encounter
  -> Silver.project_and_persist/2
  -> Gold.RebuildEncounter.rebuild/2
```

Only newly inserted encounter boundaries run the medallion import path during normal import. Existing fully imported logs can be force-reimported from byte zero through the UI.

## Target Durable Orchestration

The current inline import path is being refactored toward Reactor plus Oban.
This is the target contract for tasks `#99` through `#104`; until those tasks
land, the current import flow above remains the runtime behavior.

### Responsibility Split

Oban owns durable scheduling, uniqueness, retries, queue concurrency, operator
visibility, and handoff between long-running units of work.

Reactor owns the ordered dependency graph inside one medallion build. Reactor
steps should call existing bronze, silver, gold, and rules APIs rather than
moving layer logic into workers.

The core boundary is:

```text
Oban job: discover/sync one combat log
  -> scan completed encounter boundaries
  -> insert or fetch public.encounters rows
  -> enqueue one Oban job per inserted or explicitly requested encounter

Oban job: build one encounter
  -> Reactor workflow: WeGoNext.Medallion.BuildEncounter
     -> load public encounter + combat_log_file
     -> parse events from bronze file bytes
     -> get or create gold.dim_encounter
     -> Silver.project_and_persist/2
     -> Gold.RebuildEncounter.rebuild/2
     -> emit build summary

Oban job: rebuild gold for one encounter
  -> Gold.RebuildEncounter.rebuild/2
```

### Queues

- `:log_sync` for initial imports, manual syncs, watcher-triggered syncs, and
  force reimports. Concurrency target: `1` to `2` locally. Uniqueness should
  prevent overlapping work for the same `combat_log_file_id` or unresolved file
  path.
- `:medallion_build` for per-encounter bronze-to-silver-to-gold builds.
  Concurrency target: CPU and database limited, initially `2`. These jobs parse
  bounded byte ranges and can run independently after boundary insertion.
- `:gold_rebuild` for rules-triggered or operator-triggered gold-only rebuilds.
  Concurrency target: `2` to `4`, because they avoid reparsing raw log bytes and
  read from silver.
- `:source_import` may be used by source-data import tasks later, but source
  annotations must not enqueue combat-log medallion facts directly.

### Reactor Workflows

`WeGoNext.Medallion.BuildEncounter` is the first required Reactor workflow. Its
inputs are `encounter_id`, optional `combat_log_file_id`, and build options such
as `ruleset_id` or `ruleset: :active`. It returns a compact summary:

```elixir
%{
  encounter_id: public_encounter_id,
  combat_log_file_id: combat_log_file_id,
  dim_encounter_id: dim_encounter_id,
  silver_counts: %{...},
  gold: %{fact_failure: %{deleted: count, inserted: count, skipped: term | nil}}
}
```

Steps:

1. Load `public.encounters` and its `combat_log_files` row.
2. Parse normalized events with `CombatLogParser.parse_events/4` using the
   encounter byte range and start timestamp.
3. Get or create `gold.dim_encounter` using the existing source identity rules:
   prefer `source_head_sha256` plus `start_byte`, fall back to `source_file_path`
   plus `start_byte`.
4. Persist silver through `WeGoNext.Silver.project_and_persist/2`.
5. Rebuild encounter-level gold through `WeGoNext.Gold.RebuildEncounter`.
6. Publish a completion event and return the summary.

The workflow must be safe to rerun for the same encounter. Silver upserts by
natural key, gold fact rebuilds replace rows for one encounter/ruleset, and
`gold.dim_encounter` lookup avoids duplicate dimensions.

Rules sync is a separate workflow only if it needs multi-step durability. The
preferred first pass is to keep `WeGoNext.Rules.sync_current_tier_rules/1` as
the rules boundary and enqueue gold rebuild jobs after rules have been synced
and promoted.

### Job Boundaries and Uniqueness

Log sync jobs use one of these uniqueness keys:

- Existing row: `{"log_sync", combat_log_file_id, force_reimport?}`.
- New path before row creation: `{"log_sync_path", user_id, normalized_file_path}`.

The sync worker creates or refreshes the `combat_log_files` row, reconciles live
to archive moves, scans from `last_parsed_byte`, inserts completed encounter
boundaries, advances progress only through the last completed boundary, and
enqueues medallion build jobs for inserted encounters. Existing encounters are
not rebuilt by a normal sync.

Encounter boundary insertion remains the byte-range idempotency gate. For one
logical combat log, the stable boundary identity is `combat_log_file_id` plus
`start_byte` and `end_byte`; after archive reconciliation, source identity may
also use the preserved `head_sha256` plus byte range. The sync worker should
resolve or insert `public.encounters` first, then enqueue jobs by the resulting
public encounter id.

Medallion build jobs use:

```text
{"medallion_build", public_encounter_id, build_kind}
```

`build_kind` is normally `:import`. Explicit reimport or silver rebuild flows
may use a distinct kind, but they must still be idempotent for the same
encounter byte range.

Gold rebuild jobs use:

```text
{"gold_rebuild", dim_encounter_id, ruleset_key}
```

`ruleset_key` is `active` or the explicit ruleset id. This prevents duplicate
rule-triggered rebuilds for the same encounter while allowing an explicit test
or backfill to choose another ruleset.

### Progress and Failure Events

LiveView should observe progress through PubSub events emitted by workers, not
by long-lived LiveView-owned tasks. Events should include enough IDs to refresh
read models from the database:

- `{:log_sync_started, %{combat_log_file_id: id | nil, path: path}}`
- `{:log_sync_progress, %{combat_log_file_id: id, bytes_read: n, total_bytes: n, encounters_found: n}}`
- `{:encounter_build_enqueued, %{encounter_id: id, dim_encounter_id: id | nil}}`
- `{:encounter_build_finished, %{encounter_id: id, dim_encounter_id: id, silver_counts: counts, gold: result}}`
- `{:medallion_job_failed, %{kind: kind, ids: ids, reason: reason, attempt: n}}`

Oban remains the source of truth for retry state. LiveViews should display
summaries from refreshed database rows plus recent PubSub events; they should
not depend on process-local task state.

### Retry Policy

- Log sync jobs: retry transient file, parser, and database errors with modest
  backoff. Missing files should attempt archive reconciliation first. If no
  replacement exists, record/log a skip rather than retrying forever.
- Per-encounter build jobs: retry parser and database errors. The workflow is
  idempotent, so a retry can rerun all steps.
- Gold rebuild jobs: retry database/rules lookup errors. A missing active
  ruleset should return the existing skipped rebuild result instead of being a
  failed job.
- Force reimport jobs should be explicit and operator-triggered. They may delete
  transitional `public.encounters` rows for the selected log before rescanning,
  but they must not purge unrelated logs or gold dimensions without a separate
  explicit operation.

### Migration Path

1. Add Oban/Reactor dependencies, migrations, queues, and test configuration.
2. Introduce `WeGoNext.Medallion.BuildEncounter` and prove it matches the
   current inline `Importer` medallion path.
3. Create per-encounter Oban build workers and have imports enqueue them.
4. Move `ImportWorker` and `FileWatcher.sync_now/0` execution onto Oban while
   preserving their public UI-facing APIs.
5. Route rules-triggered and operator-triggered gold rebuilds through
   `:gold_rebuild` jobs.
6. Remove `Task.Supervisor` import coordination once no production medallion
   build path depends on it.

## Rebuild Flow

Gold is rebuildable from silver. Silver is rebuildable from bronze logs.

Use the smallest necessary rebuild:

- Rules changed: promote rules, then rebuild gold.
- Gold fact logic changed: rebuild gold.
- Silver projection changed: force reimport affected logs.
- Parser or boundary logic changed: force reimport, and purge only if identity/offset assumptions changed.

## UI Surfaces

Active routes:

- `/` — encounter list and log import.
- `/encounters/:id` — medallion encounter detail shell keyed by `gold.dim_encounter.id`.
- `/failures` — gold-backed mechanic failures.
- `/settings` — logs path and current-log import convenience.

The home page still lists transitional `public.encounters` rows for import/catalog operations such as reset marking. Navigation into medallion analysis must cross the explicit `WeGoNext.Gold.EncounterIdentity` bridge and use the resulting `gold.dim_encounter.id`. New detail read models should use `WeGoNext.Gold.EncounterDetail` or similar gold/silver read models, not `public.encounters.id`.

## Legacy Analyzer Boundary

`WeGoNext.Analyzers.*` modules are reference-only tooling. They remain available for command-line diagnostics, migration reference, and silver parity checks while the medallion warehouse reaches feature parity.

Intentional references are limited to:

- `WeGoNext` — compatibility facade for CLI-style inspection helpers.
- `test/we_go_next/silver/round_trip_test.exs` — parity assertions between silver projections and legacy analyzer output.

New Phoenix routes, LiveViews, gold facts, silver/gold read models, and rules/source-data workflows must not call legacy analyzers or read cached analyzer output. They should use bronze/silver/gold/rules tables and read-model modules instead.

The next medallion work should prioritize:

- observed mechanics previews over current imported logs,
- code-defined raid mechanic catalogs synced into editable rules,
- avoidable damage rules and rebuilt real failure facts,
- tighter missed-interrupt silver semantics before interrupt auto-import,
- additional fact semantics only when supporting silver observations exist.
