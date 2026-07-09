# Operations

This document covers the local workflows needed to drive real combat logs through the medallion pipeline.

## Running the App

```bash
cd we_go_next
mix setup
mix ecto.setup
mix phx.server
```

Open `http://localhost:4000`.

## Importing Logs

1. Open `/settings`.
2. Set the WoW logs directory, for example:

   ```text
   /mnt/e/World of Warcraft/_retail_/Logs
   ```

3. Open `/`.
4. Select a combat log and click **Import**.

Imports are incremental by `combat_log_files.last_parsed_byte`. Re-importing an unchanged log should add zero encounters.

The Settings page says “Import” and “Current Log” because live append tracking
is tied to the selected current log. WoW appends only to the newest active log.
Older logs and archive logs are useful for review and force-reimport, not live
append tracking.

### Planned Durable Import Orchestration

Task `#98` defines the target import contract for the Reactor/Oban refactor.
Until tasks `#99` through `#104` land, imports still run through the current
inline path. After the refactor:

```text
/ or /settings import action
  -> Oban :log_sync job
  -> completed encounter boundary scan
  -> public.encounters rows
  -> Oban :medallion_build jobs
  -> Reactor per-encounter build
  -> silver rows and gold facts
  -> PubSub completion events for LiveView refresh
```

Operators should think of log import as durable queued work, not as a
LiveView-owned task. Refreshing or closing the browser should not cancel an
import or medallion build.

Expected queues:

- `:log_sync` for initial imports, manual current-log syncs, watcher-triggered
  syncs, and force reimports.
- `:medallion_build` for bounded per-encounter parse/project/rebuild work.
- `:gold_rebuild` for rules-triggered and operator-triggered gold-only
  rebuilds.

Normal syncs enqueue medallion builds only for newly inserted encounter
boundaries. Existing encounters are not silently rebuilt.

## Force Reimport

Use **Reimport** / **Confirm Reimport** on `/` for a fully imported log.

This resets the selected `combat_log_files` row to byte zero and deletes its transitional `public.encounters` rows. The next import reparses the whole file and reruns silver/gold for newly inserted encounter boundaries.

Use force reimport when:

- parser boundary behavior changed,
- silver projection logic changed,
- previously imported encounters need to be regenerated from raw log bytes.

Do not force reimport just because rules changed.

## Current-Tier Mechanics Bootstrap

The preferred current-tier path is to sync code-defined raid mechanics and
rebuild failure facts. Treat the checked-in raid modules as the durable mechanic
source; ruleset/promotion tables are internal plumbing for fact keys.

Sync Midnight Season 1 current-tier raid mechanics:

```bash
mix we_go_next.sync_raid_rules
```

Sync and rebuild in one command:

```bash
mix we_go_next.sync_raid_rules midnight_season_1 --rebuild
```

The curated source lives in `we_go_next/lib/we_go_next/game_data/raids/`.
DBM/WowAnalyzer/journal data and AI-assisted research can help update those
files, but the checked-in raid modules are the durable source of curated rules.

The home page starts from the same current-tier path with **Sync Mechanics &
Rebuild**. That operation syncs the catalog and rebuilds failure facts.

For compatibility, `mix we_go_next.seed_rules` with no path also uses the
current-tier catalog:

```bash
mix we_go_next.seed_rules
```

The historical bundled seed file remains at
`we_go_next/priv/rules/initial_mechanic_rules.json`, but it is legacy fixture
data, not the default operator path. To seed any static JSON file explicitly:

```bash
mix we_go_next.seed_rules priv/rules/initial_mechanic_rules.json
```

After that, imports and gold rebuilds can produce `gold.fact_failure` rows for matching silver observations.

## Rebuild Failures

Use failure rebuild when mechanic definitions or gold computation changed but silver rows are still valid:

```bash
mix wgn.rebuild_gold
```

Rebuild for one encounter:

```bash
mix wgn.rebuild_gold --encounter-id 123
```

Rebuild with an explicit ruleset:

```bash
mix wgn.rebuild_gold --ruleset-id 456
```

The task uses `WeGoNext.Gold.RebuildEncounter`, the same boundary used by the importer.

### Planned Durable Rebuild Orchestration

After the Reactor/Oban refactor, explicit rebuilds should use `:gold_rebuild`
jobs instead of a direct long-running loop in a UI process. The gold rebuild job
key is:

```text
{"gold_rebuild", dim_encounter_id, ruleset_key}
```

`ruleset_key` is `active` for the current active ruleset or the explicit
ruleset id passed by an operator/test. This prevents duplicate concurrent
rebuilds for the same encounter and ruleset while keeping explicit backfills
possible.

The smallest-rebuild rule remains unchanged:

- rules changed: sync/promote rules, then enqueue gold rebuild jobs,
- gold fact logic changed: enqueue gold rebuild jobs,
- silver projection changed: force reimport affected logs,
- parser or boundary logic changed: force reimport and purge only when identity
  or offset assumptions changed.

Gold-only rebuilds should not reparse combat logs. They read existing silver
rows and call `WeGoNext.Gold.RebuildEncounter`.

## Durable Job State

The Oban refactor should expose progress and failures through PubSub plus the
database, not process-local task state.

Expected progress events:

- `:log_sync_started`
- `:log_sync_progress`
- `:encounter_build_enqueued`
- `:encounter_build_finished`
- `:medallion_job_failed`

If an import appears stuck after the refactor, inspect Oban jobs first. Retry
state belongs to Oban. LiveView screens should refresh from database rows and
recent PubSub events rather than owning the running process.

Retry expectations:

- missing live files reconcile against Warcraft Logs archive paths before
  failing,
- unchanged or incomplete current logs should no-op cleanly,
- per-encounter medallion builds can safely rerun because silver upserts and
  gold encounter rebuilds are idempotent,
- missing active rulesets should produce the existing skipped gold rebuild
  result, not an endlessly retrying job.

## Import DBM Source Annotations

DBM import reads installed Midnight DBM Lua modules as source evidence. It statically extracts module metadata, special warning declarations, alert tokens, source file/line provenance, and tentative mechanic hints. It does not execute Lua, sync active mechanics, or rebuild gold facts.

Default local import:

```bash
mix wgn.import_dbm --build-key local
```

Explicit source root:

```bash
mix wgn.import_dbm \
  --root "/mnt/e/World of Warcraft/_retail_/Interface/AddOns/DBM-Raids-Midnight" \
  --build-key local
```

Imported rows are stored in `source_data.dbm_mechanic_candidate`. Treat them as
source annotations and scaffolding input for code-defined raid mechanics, not as
runtime rules.

## Import Reference Metadata

Source-data reference metadata resolves spell names, encounter names, build
scope, and encounter-to-spell evidence. It does not activate rules or rebuild
facts.

Import the local spell-name export:

```bash
mix wgn.import_reference_metadata --build-key 11.2.5
```

Import explicit exported metadata:

```bash
mix wgn.import_reference_metadata \
  --file /path/to/reference_bundle.json \
  --build-key 11.2.5 \
  --channel ptr
```

Supported JSON inputs are intentionally narrow:

- spell-id/name maps such as `tools/spell_names.json`,
- bundles with `spells`, `encounters`, and optional `encounter_spells` arrays.

Use source metadata imports to help update code-defined raid mechanic catalogs.
Use failure rebuilds after code-defined mechanics have been synced.

## Import WowAnalyzer Timeline Source Annotations

WowAnalyzer timeline import reads the local AGPL-licensed WowAnalyzer checkout as source evidence. It extracts encounter timeline spell IDs and comments from static TypeScript boss files, records repository revision/license provenance, and infers tentative mechanic hints for curated raid modules. It does not copy runtime code into the medallion fact path, sync active mechanics, or rebuild gold facts.

Default local import:

```bash
mix wgn.import_wowanalyzer --build-key local
```

Explicit source root:

```bash
mix wgn.import_wowanalyzer \
  --root /home/rpmessner/dev/games/wow-addons/WoWAnalyzer/src/game/raids/vs_dr_mqd \
  --repo-root /home/rpmessner/dev/games/wow-addons/WoWAnalyzer \
  --build-key local
```

Imported rows are stored in `source_data.wowanalyzer_timeline_candidate` with source file/line, comments, `repository_revision`, and `repository_license` (`AGPL-3.0-or-later` for the local checkout). Treat these rows as source annotations and scaffolding input for code-defined raid mechanics.

## Import Warcraft Logs API Evidence

Warcraft Logs API import stores flat JSON bronze artifacts and catalogs them in source-data. It does not import local combat logs, sync active mechanics, or rebuild gold facts.

Configure credentials in the web UI:

1. Open Settings.
2. Save a Warcraft Logs client name and API key.
3. The API key is encrypted before it is stored and is never rendered back to the page.

Associate a WCL report with an imported local log:

1. Open the home page.
2. Find the imported log row.
3. Paste a WCL report URL into the row's Warcraft Logs URL field.
4. Save the link.

The URL parser stores the report code and, when present, the fight id from URLs like:

```text
https://www.warcraftlogs.com/reports/abc123#fight=17&type=damage-done
```

Fetch WCL damage-done table data for a report/fight and save it as a bronze artifact:

```bash
WARCRAFT_LOGS_ACCESS_TOKEN=... mix wgn.import_warcraft_logs \
  --report-code abc123 \
  --fight-id 17 \
  --preset damage-done \
  --build-key local
```

Fetch and immediately compare the WCL damage-done table against a parsed gold encounter:

```bash
WARCRAFT_LOGS_ACCESS_TOKEN=... mix wgn.import_warcraft_logs \
  --report-code abc123 \
  --fight-id 17 \
  --preset damage-done \
  --compare-encounter-dim-id 163 \
  --build-key local
```

Import an already saved response payload:

```bash
mix wgn.import_warcraft_logs \
  --file /path/to/response.json \
  --report-code abc123 \
  --fight-id 17 \
  --query-name Events
```

Optional request provenance:

```bash
mix wgn.import_warcraft_logs \
  --file /path/to/response.json \
  --report-code abc123 \
  --fight-id 17 \
  --query-name Events \
  --query-file /path/to/query.graphql \
  --request-params-file /path/to/request_params.json \
  --build-key local
```

Imported artifacts are stored under `var/bronze/warcraft_logs/reports/<report-code>/fights/<fight-id>/` by default. Pass `--bronze-root /path/to/root` to use a different local artifact root.

Imported rows are cataloged in `source_data.warcraft_logs_api_fetch` and versioned through `source_data.source_import` by response hash. Treat them as comparison evidence for local silver/gold projections, not as rule or fact input.

Programmatic damage-done comparison:

```elixir
fetch = WeGoNext.SourceData.list_warcraft_logs_api_fetches(report_code: "abc123", fight_id: 17) |> hd()
WeGoNext.SourceData.compare_warcraft_logs_damage_done(163, fetch)
```

## Inspect Source Annotations

Use the source-data context to inspect parsed source rows while updating raid
mechanic code:

```elixir
WeGoNext.SourceData.list_dbm_candidates(encounter_id: 3306)
WeGoNext.SourceData.list_wowanalyzer_timeline_candidates(encounter_id: 3306)
WeGoNext.SourceData.list_warcraft_logs_api_fetches(report_code: "abc123", fight_id: 17)
```

Supported filters include `:encounter_id`, `:spell_id`, and
`:inferred_mechanic_type`. WowAnalyzer timeline rows also support
`:timeline_type` and `:event_type`.

Rows include source file/line provenance, labels/role filters where available,
comments, and inferred mechanic hints. They are scaffolding input for
code-defined raid catalogs, not active rules.

## Public Mirror Document Uploads

Public sharing uses generated encounter documents, not DB ingest. The local
parser writes `encounters/<source_encounter_key>.json` and `index.json` through
`WeGoNext.Documents.Store`; opted-in uploads are tracked by `mirror_uploads` and
drained by `WeGoNext.Documents.UploadWorker` in parser mode.

Enable publishing for an imported log from the imported-logs UI, or use the
Upload/Re-upload button on an encounter detail page to enqueue a single pull.
The public app reads from R2 under `/r/:slug`; `/failures` is local
parser-only.

Useful checks:

```bash
mix wgn.rebuild_documents --encounter-id <encounter_dim_id>
mix run -e 'IO.inspect(WeGoNext.Mirror.Outbox.process_pending(limit: 10, max_concurrency: 2))'
```

Gigalixir public mode needs R2 read credentials and should not have the old
ingest token configured:

```bash
gigalixir config:unset INGEST_TOKEN
gigalixir config:set DOCUMENTS_STORE=r2
gigalixir config:set R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
gigalixir config:set R2_BUCKET=<bucket>
gigalixir config:set R2_ACCESS_KEY_ID=<read-access-key-id>
gigalixir config:set R2_SECRET_ACCESS_KEY=<read-secret-access-key>
```

## Diagnosing Empty Failures

The `/failures` page has a Data Readiness panel that checks the common empty-state causes:

- current-tier mechanics have not been synced,
- synced mechanics have not been made fact-ready,
- no gold encounters in the selected date range,
- no supported silver observations matching synced mechanics,
- no gold facts for the selected range,
- fact rows that no longer match the current synced mechanics,
- fact rows that were built before the current failure logic.

`gold.fact_failure.derivation_version` is stamped during rebuilds. If fact
failure semantics change, bump `WeGoNext.Gold.FactFailure.Derivation` and
rebuild gold facts; existing rows with an older or missing derivation version
will be reported as stale.

Interrupt diagnostics use known interruptible cast windows from code-defined
encounter data. Previously imported logs may need force reimport after silver
projection changes.

Useful SQL for deeper inspection:

```sql
SELECT id, name, version, status FROM rules.ruleset ORDER BY id;
SELECT count(*) FROM rules.mechanic_criterion;
SELECT count(*) FROM gold.dim_mechanic_criterion;
SELECT count(*) FROM silver.damage_taken;
SELECT count(*) FROM silver.interrupt_opportunity;
SELECT count(*) FROM gold.fact_failure;
```

## Rebuild Policy

Treat medallion layers as derived data:

- Bronze combat logs are the source of truth.
- Silver can be regenerated from bronze.
- Gold can be regenerated from silver and code-defined mechanics.

When a computation intentionally changes, prefer explicit rebuilds over trying to preserve old idempotency assumptions:

| Change | Action |
| --- | --- |
| Mechanic definitions only | Sync mechanics, rebuild gold |
| Gold fact SQL/semantics | Rebuild gold |
| Silver projection | Force reimport affected logs |
| Parser/boundary logic | Force reimport affected logs |
| Log identity/provenance bug | Purge/reconcile only with a clear reason |

This matches real medallion warehouse practice: immutable source inputs, versioned or replaceable derived partitions, and explicit backfills when transform behavior changes.
