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

`WeGoNext.FileWatcher` is no longer a polling watcher. It is a current-log pointer used by the UI and import flow.

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

Before adding another event-grain silver table, name the downstream workflow and confirm that aggregate silver, existing event-like tables, or reparsing bronze logs would not be sufficient. If volume becomes a problem, tighten event-grain damage storage before expanding it: likely by NPC-source filtering, tank-melee exclusion, rule/candidate spell scoping, partitioning, or retention.

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
- `gold.dim_mechanic_criterion` snapshots authored criteria for fact stability.

There is currently exactly one active ruleset globally. Backfills and tests may pass an explicit `ruleset_id`.

Threshold semantics are intentionally narrow:

- `avoidable`: `threshold["max_hits"]` non-negative integer.
- `interrupt`: optional `threshold["must_interrupt"]`, defaulting to true.
- `soak`, `spread`, `stack`, `tank_mechanic`, `healer_mechanic`: allowed only with empty thresholds until fact semantics are implemented.

### Source Data

Patch-aware source data is separate from combat-log bronze.

Current source-data groundwork:

- `source_data.source_import`
- `source_data.dbm_mechanic_candidate`
- `source_data.spell_reference`
- `source_data.encounter_reference`
- `WeGoNext.SourceData.DBM.Parser`

DBM imports create inferred mechanic candidates with source file, line number, module metadata, warning constructor, role filters, labels, comments, confidence, and review status. These are evidence, not active rules. They do not write gold facts directly.

Spell and encounter references are conformed, build-scoped source-data dimensions used by rules and gold promotion code to resolve display names and encounter scope without relying on static JSON names. Reference rows carry product, channel, build key/version, locale, source system, source priority, optional `source_import_id`, and metadata. Retail, beta, and PTR rows coexist by channel/build scope; lookups prefer lower `source_priority` values within an explicit build scope.

## Import Flow

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

The next medallion UI work should add:

- rules status/bootstrap controls,
- medallion rebuild/recompute controls,
- failures empty-state diagnostics,
- richer encounter detail sections behind the gold-keyed shell.
