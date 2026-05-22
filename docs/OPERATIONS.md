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

The Settings page says “Import” and “Current Log” because there is no filesystem auto-watch loop. WoW appends only to the newest active log. Older logs and archive logs are useful for review and force-reimport, not live append tracking.

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

## Inspect Source Annotations

Use the source-data context to inspect parsed source rows while updating raid
mechanic code:

```elixir
WeGoNext.SourceData.list_dbm_candidates(encounter_id: 3306)
WeGoNext.SourceData.list_wowanalyzer_timeline_candidates(encounter_id: 3306)
```

Supported filters include `:encounter_id`, `:spell_id`, and
`:inferred_mechanic_type`. WowAnalyzer timeline rows also support
`:timeline_type` and `:event_type`.

Rows include source file/line provenance, labels/role filters where available,
comments, and inferred mechanic hints. They are scaffolding input for
code-defined raid catalogs, not active rules.

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
