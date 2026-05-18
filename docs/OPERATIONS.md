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

## Rules Bootstrap

Current rules are backend-only. There is not yet a production UI for creating, activating, or promoting rules.

Seed bundled local rules:

```bash
mix we_go_next.seed_rules
```

The bundled seed file is `we_go_next/priv/rules/initial_mechanic_rules.json`.

To activate and promote the seeded rules in one command:

```bash
mix run -e 'alias WeGoNext.Rules; {:ok, %{ruleset: rs}} = Rules.seed_initial_rules(); {:ok, active} = Rules.activate_ruleset(rs); {:ok, _} = Rules.promote_ruleset_to_gold(active)'
```

After that, imports and gold rebuilds can produce `gold.fact_failure` rows for matching silver observations.

## Rebuild Gold

Use gold rebuild when rules or gold computation changed but silver rows are still valid:

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

## Diagnosing Empty Failures

If `/failures` is empty, check these in order:

1. Is there an active ruleset?
2. Were active rules promoted to `gold.dim_mechanic_criterion`?
3. Do the promoted criteria match spell IDs present in silver?
4. Did `mix wgn.rebuild_gold` run after rules/gold changes?
5. Did the selected log import produce silver rows?

Useful SQL:

```sql
SELECT id, name, version, status FROM rules.ruleset ORDER BY id;
SELECT count(*) FROM rules.mechanic_criterion;
SELECT count(*) FROM gold.dim_mechanic_criterion;
SELECT count(*) FROM silver.damage_taken;
SELECT count(*) FROM silver.interrupt_opportunity;
SELECT count(*) FROM gold.fact_failure;
```

Near-term tasks `#52`, `#53`, and `#54` exist to turn these checks into UI flows.

## Rebuild Policy

Treat medallion layers as derived data:

- Bronze combat logs are the source of truth.
- Silver can be regenerated from bronze.
- Gold can be regenerated from silver and rules.

When a computation intentionally changes, prefer explicit rebuilds over trying to preserve old idempotency assumptions:

| Change | Action |
| --- | --- |
| Rules only | Promote rules, rebuild gold |
| Gold fact SQL/semantics | Rebuild gold |
| Silver projection | Force reimport affected logs |
| Parser/boundary logic | Force reimport affected logs |
| Log identity/provenance bug | Purge/reconcile only with a clear reason |

This matches real medallion warehouse practice: immutable source inputs, versioned or replaceable derived partitions, and explicit backfills when transform behavior changes.
