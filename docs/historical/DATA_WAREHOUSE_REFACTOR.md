# Data Warehouse Refactor — Silver Tier, First Iteration

## Context

The earlier version of this doc was a learning roadmap that surveyed medallion + Kimball + the dbt/DuckDB ecosystem and laid out optional paths. This version is the actual plan we're committing to for the first iteration. The roadmap framing is preserved in git history if it's useful for reference.

Re-derived from first principles:

- **What earns its place:** medallion's reproducibility/immutability/conformance guarantees, and a fact/dim layer the frontend can query.
- **What's forbidden:** event-grain in Postgres (rejected in April 2026 — `encounter_events` was dropped in migration `20260409175732`).
- **What's available:** a 1145-line Zig parser that already does the expensive work in-process. Its output today is consumed by six analyzers in parallel and then discarded.

This iteration introduced silver as **a projection step that writes coarse-grain rows into Postgres**, plus gold dimensions/facts to prove the end-to-end pattern. The old `encounters.analysis` JSON cache has been retired from active code; active analysis/read-model work should target silver/gold/rules.

Out of scope (deliberately): dbt-postgres, retiring `parse_events`, SCD2 history on dimensions, and broad dimension modeling beyond the current encounter/player/mechanic criterion dimensions.

**Bronze is dual-source from day one.** Two folders under WoW's Logs directory both produce identical-format combat logs:

1. `WoWCombatLog-*.txt` — live logs being written by the game client.
2. `warcraftlogsarchive/Archive-WoWCombatLog-*.txt` — files moved here by the Warcraft Logs desktop uploader after upload.

Inspection confirmed these are byte-for-byte the same combat log format: `ADVANCED_LOG_ENABLED,1`, full COMBATANT_INFO with gear/talent payloads, 42-field SPELL_DAMAGE events with advanced parameters, paired ENCOUNTER_START/END markers. The Warcraft Logs uploader does not strip anything — it just moves the file with an `Archive-` prefix.

This resolves what looked like an either/or dilemma: running Warcraft Logs uploader **and** using `we_go_next` works because archived files remain fully analyzable. The only Phoenix-side work is watching the second directory and recording the source provenance on the `combat_log_files` row.

---

## Architecture

```
Bronze:  Logs/WoWCombatLog-*.txt                                (live)
         Logs/warcraftlogsarchive/Archive-WoWCombatLog-*.txt    (post-upload, same format)
         combat_log_files (Postgres catalog — gains a `source` column)
                │
                │ Zig: project_silver/3 (new NIF — one pass over events)
                ▼
Silver:  silver.damage_taken
         silver.damage_done
         silver.death
         silver.interrupt_opportunity
         silver.debuff_application
         silver.player_info
                │
                │ SQL transform (Elixir, this iteration — dbt later)
                ▼
Gold:    gold.dim_encounter
         gold.dim_player
         gold.dim_mechanic_criterion
         gold.fact_failure
```

Silver is populated from bronze encounter boundaries and normalized combat-log events. Gold's `fact_failure` is rebuilt from silver plus rules-backed criterion snapshots after each import.

---

## Why Silver Is Postgres (Not Parquet / Not Event-Grain)

The previous version of this doc presented three silver options: event-grain Postgres (rejected), pre-aggregated Postgres (Option 2), event-grain Parquet (Option 3). The chosen shape doesn't match any of them — it's a fourth:

> **Zig pre-projects events into coarse-grain rows; Postgres stores them.**

The reasoning:

- **The April rejection was about *event-grain*, not Postgres.** Millions of rows per raid night was the problem. Tens of thousands of pre-projected rows is not.
- **Zig already does the heavy work.** Adding one more pass for projection is cheap and re-uses the existing line parser.
- **Postgres is already in the stack.** No new tooling on the hot path — no Parquet writer ecosystem fight, no DuckDB binary dependency, no Python sidecar.
- **The frontend wants SQL.** A fact/dim layer queried via Ecto is the path of least resistance for LiveView pages.
- **Medallion guarantees still hold.** Silver is rebuildable from bronze (re-run `project_silver` over stored byte offsets). Gold is rebuildable from silver (re-run the SQL transform). Layer independence is preserved.

The doc's Option 3 (Parquet silver, DuckDB queries) is still an interesting follow-on if cross-encounter analytics at scale ever outgrow Postgres. It does not need to be the first step.

---

## Silver Schemas

Each table has `encounter_id` FK to `encounters`, an `inserted_at`, and a unique constraint on its natural key (for idempotent `ON CONFLICT DO UPDATE` re-runs).

**Natural-key rule:** every conflict-target column must be non-null and deterministic. PostgreSQL allows multiple `NULL` values in unique indexes, so a nullable `spell_id` or timestamp-derived key would silently break idempotency. Where analyzer semantics can produce `nil` (for example melee damage), normalize to an explicit sentinel value or a separate non-null key field before insert. Store time-into-fight key columns as integer milliseconds, not floats, so reruns produce byte-identical keys.

| Table | Natural key | Measures / payload |
| --- | --- | --- |
| `silver.damage_taken` | (encounter_id, target_guid, source_guid, spell_id) | total_amount, hit_count, max_hit, overkill_total, source_is_npc (bool — populated in Zig from source_flags) |
| `silver.damage_done` | (encounter_id, source_guid, target_guid, spell_id) | total_amount, hit_count, max_hit |
| `silver.death` | (encounter_id, target_guid, died_at_ms_into_fight) | killing_blow_spell_id, killing_blow_source_guid, damage_recap (jsonb — last 10 events) |
| `silver.interrupt_opportunity` | (encounter_id, target_npc_guid, interrupted_spell_id, opportunity_ms_into_fight) | success (bool), interrupter_guid (nullable — null when success=false), interrupting_spell_id (nullable) |
| `silver.debuff_application` | (encounter_id, target_guid, source_guid, spell_id, applied_at_ms_into_fight) | duration_ms (nullable — null if not removed before encounter end), stack_count |
| `silver.player_info` | (encounter_id, player_guid) | player_name, class_id, spec_id, item_level, detected_role (enum: `tank`/`healer`/`dps`/`unknown`) |

**`silver.interrupt_opportunity` semantics** (renamed from `silver.interrupt` after review):

- One row per interrupt *opportunity* — either a successful interrupt of an enemy cast OR an enemy cast of an interruptible spell that completed unkicked.
- `target_npc_guid` is the source of the enemy cast (the thing being interrupted, or the thing that finished casting).
- `opportunity_ms_into_fight` is the time of the interrupt event (when `success=true`) or the time of `SPELL_CAST_SUCCESS` (when `success=false`), stored as integer milliseconds.
- `interrupter_guid` is the player who landed the kick (null for missed casts).
- Natural key excludes `interrupter_guid` so missed casts (no interrupter) still have a unique key.
- This matches `InterruptAnalyzer.missed_casts` (`interrupt_analyzer.ex:226-243`), which only treats an NPC `SPELL_CAST_SUCCESS` as "missed" if that spell was successfully interrupted at least once in the SAME encounter. Implication for the Zig projection: maintain TWO accumulators during the single pass — (a) all successful `SPELL_INTERRUPT` events, (b) all NPC `SPELL_CAST_SUCCESS` events buffered with their spell_id. At end-of-encounter, build a set of interrupted spell_ids from (a), then filter (b) down to casts whose spell appears in that set — only those become `success=false` rows in `silver.interrupt_opportunity`. Casts of spells that nobody ever kicked are dropped (they're not considered "interruptible" by the analyzer's heuristic).

**`silver.player_info.detected_role`** is populated in Zig during the same pass that builds `silver.damage_taken`, reproducing the tank heuristic in `damage_taken_analyzer.ex:43` ("top 2 players receiving NPC melee damage are tanks"). Computed by tracking per-player NPC-source melee damage in an accumulator alongside the damage-taken accumulator; finalized at end-of-encounter when emitting `silver.player_info` rows. Healer detection is left for a follow-on (today's analyzer doesn't distinguish healer from dps in role assignment).

**`silver.damage_taken.source_is_npc`** is denormalized into the row (cheap to compute from `source_flags` during the same Zig pass) specifically so the gold-tier SQL transform can filter avoidable-damage facts to NPC-source damage without re-deriving NPC-ness from flags in SQL.

**Expected per-encounter row counts:** ~500–3000 damage rows, 5–25 deaths, 20–100 interrupt opportunities, 100–500 debuff applications. A heavy raid night = ~80k rows across silver. Negligible vs. the event-grain volume April rejected.

---

## Gold Schema (this iteration: one fact + a real dimensional layer)

```sql
CREATE SCHEMA gold;

CREATE TABLE gold.dim_player (
  id           bigserial PRIMARY KEY,
  player_guid  text NOT NULL UNIQUE,
  player_name  text NOT NULL,
  class_id     int,
  spec_id      int,
  inserted_at  timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE gold.fact_failure (
  encounter_dim_id  bigint NOT NULL REFERENCES gold.dim_encounter(id) ON DELETE CASCADE,
  player_dim_id     bigint NOT NULL REFERENCES gold.dim_player(id),
  criterion_dim_id  bigint NOT NULL REFERENCES gold.dim_mechanic_criterion(id),
  failure_count     int NOT NULL,
  total_damage      bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (encounter_dim_id, player_dim_id, criterion_dim_id)
);
```

`gold.dim_encounter` is the analytics encounter grain, `gold.dim_player` is conformed from `silver.player_info`, and `gold.dim_mechanic_criterion` snapshots authored `rules.mechanic_criterion` rows. `public.encounters` remains only as transitional import bookkeeping and is not a fact grain.

**Raid-level failures (sentinel pattern).** Missed interrupts are currently raid-level facts because no specific player is assigned. To keep `fact_failure.player_dim_id` NOT NULL while preserving this semantic, `dim_player` is seeded with a sentinel row at migration time:

```sql
INSERT INTO gold.dim_player (player_guid, player_name, class_id, spec_id)
VALUES ('__RAID__', 'Raid', NULL, NULL);
```

The fact builder maps `player_guid IS NULL` (from `silver.interrupt_opportunity`) to the sentinel row's `id` during the join. All raid-level failures for the same `(encounter, criterion)` collapse to one fact row whose `failure_count` is the count of missed casts — which is what the per-encounter Failures tab already shows. The sentinel is a well-known Kimball pattern; the alternative (nullable `player_dim_id`, or separate `fact_raid_failure`) was rejected because it forces a special case into every consumer.

**Type 1 SCD behavior:** `dim_player` upserts on `player_guid` — class/spec changes overwrite the existing row. Historical fact rows then implicitly point at the player's *current* class/spec, not the class/spec at the time of the encounter. SCD2 (preserving point-in-time accuracy via `valid_from`/`valid_to`) is the documented follow-on.

**Build order per import:**
1. `Silver.project_and_persist(encounter)` writes the six silver tables.
2. `Gold.DimPlayer.upsert_from_silver(encounter_id)` upserts `dim_player` rows from `silver.player_info` for this encounter (the sentinel `__RAID__` row is seeded once at migration time, not per import).
3. `Gold.FactFailure.rebuild_for_encounter(encounter_dim_id)` joins `silver.damage_taken` (filtered `silver.player_info.detected_role <> 'tank'`) + `silver.interrupt_opportunity` (where `success = false`, mapped to the `__RAID__` sentinel) + `gold.dim_mechanic_criterion` + `gold.dim_player`, writes `fact_failure` rows with surrogate keys throughout.

**Why `source_is_npc` is NOT filtered in `fact_failure`** — even though `silver.damage_taken` carries the column, current failure semantics check non-tank player damage by spell against rules thresholds. Adding `source_is_npc = true` would be a behavior change. The column stays in silver for future facts.

Why this is the right minimum:

- **Real dim discipline from day one.** Future facts (`fact_death`, `fact_interrupt`, `fact_damage_taken`) join the same `dim_player` — conformance for free.
- **No retrofit cost.** If `fact_failure` shipped with `player_guid` inline, every subsequent fact would force a migration of `fact_failure` to surrogate keys. Doing it once upfront is strictly cheaper.
- **The frontend gets surrogate-key joins.** Standard Ecto associations work cleanly; queries don't pivot on string GUIDs.
- **`silver.player_info` earns its keep.** It exists specifically to be the source for `dim_player`. Without `dim_player`, that silver table is just data sitting there.

---

## Critical Files

**Migrations** (`we_go_next/priv/repo/migrations/`, listed in the order they must be generated/run):

1. `<ts>_add_source_and_head_sha256_to_combat_log_files.exs` — adds `source` column (default `"live"`, allowed values `"live"` | `"warcraftlogs_archive"`) and `head_sha256` (text, nullable). Enforce `source` with both a database check constraint and Ecto changeset validation. New rows compute `head_sha256` at creation time (`CombatLogFile.attrs_from_file/2`) by reading the first 4 KB of the file through one shared digest helper. Existing rows are backfilled opportunistically: on each scan, if a row's `file_path` still exists on disk and `head_sha256` is null, compute and persist it. Rows whose file is already gone before the backfill runs simply stay null (see fallback below).
2. `<ts>_create_silver_tables.exs` — the six `silver.*` tables above with indexes on `encounter_id` and unique constraints on natural keys. Natural-key columns must be non-null. If a silver table uses a surrogate `id`, document that and use it consistently in Ecto; if it does not, the persistence layer must not rely on `:id` in `replace_all_except`.
3. `<ts>_create_gold_schema.exs` — `execute "CREATE SCHEMA gold"` + downgrade.
4. `<ts>_create_gold_dim_player.exs` — `gold.dim_player` with unique index on `player_guid`.
5. `<ts>_seed_raid_sentinel_dim_player.exs` — INSERTs the `__RAID__` sentinel into `gold.dim_player`. Must run after #4 (table exists) and before #6 (the FK target).
6. `<ts>_create_gold_fact_failure.exs` — `gold.fact_failure` with surrogate-key FKs to `gold.dim_encounter`, `gold.dim_player`, and `gold.dim_mechanic_criterion`.

**Zig** (`we_go_next/priv/native/combat_log_parser.zig`):
- Add a `project_silver(file_path, start_byte, end_byte) -> {damage_taken, damage_done, deaths, interrupts, debuff_applications, player_info}` NIF.
- Re-uses the existing line parser. Maintains six accumulators in a single pass. Returns six typed row lists.
- Death damage-recap window (last 10 damaging events per player) accumulates in a ring buffer keyed by `target_guid`, flushed into the death row on `UNIT_DIED`.
- Interrupt correlation (`SPELL_CAST_START` → `SPELL_INTERRUPT`/`SPELL_CAST_SUCCESS`) uses a pending-casts hashmap keyed by `(source_guid, spell_id)`.
- Debuff pairing (`SPELL_AURA_APPLIED` → `SPELL_AURA_REMOVED`) uses a hashmap keyed by `(target_guid, source_guid, spell_id)`.

**Silver Elixir module** (`we_go_next/lib/we_go_next/silver/`):
- `silver.ex` — public API: `Silver.project_and_persist(encounter)`. Calls the NIF, bulk-inserts each row list inside a transaction with the natural-key `conflict_target`. If the silver tables have surrogate `id` columns, use `on_conflict: {:replace_all_except, [:id, :inserted_at]}`. If they are key-only tables, replace only the mutable payload columns and leave the natural-key columns unchanged.
- One Ecto schema per silver table using `@schema_prefix "silver"`: `damage_taken.ex`, `damage_done.ex`, `death.ex`, `interrupt.ex`, `debuff_application.ex`, `player_info.ex`.

**Gold Elixir module** (`we_go_next/lib/we_go_next/gold/`):
- `dim_player.ex` — Ecto schema (`@schema_prefix "gold"`) + `upsert_from_silver(encounter_id)` that reads `silver.player_info` rows for the encounter and `INSERT … ON CONFLICT (player_guid) DO UPDATE` into `gold.dim_player`.
- `fact_failure.ex` — Ecto schema (`@schema_prefix "gold"`, `@primary_key false`) with `belongs_to` to `gold.dim_encounter`, `gold.dim_player`, and `gold.dim_mechanic_criterion`.
- `fact_failure.ex` — `rebuild_for_encounter(encounter_dim_id)`. One SQL `INSERT … ON CONFLICT DO UPDATE` that reads `silver.damage_taken` + `silver.player_info` (for `detected_role` filter) + `silver.interrupt_opportunity` + `gold.dim_mechanic_criterion` + `gold.dim_player`, grouped by `(encounter_dim_id, player_dim_id, criterion_dim_id)`. Ruleset-aware criteria matching is resolved through the promoted gold criterion snapshots.

**Importer hook** (`we_go_next/lib/we_go_next/importer.ex`):
- `insert_encounter_from_boundary/2` currently calls `Repo.insert_all(..., on_conflict: :nothing)` at line 310 and returns nothing useful. Refactor to `insert_or_fetch_encounter_from_boundary/2` returning `{:inserted, %Encounter{}}` | `{:existing, %Encounter{}}`. Implementation: `INSERT ... ON CONFLICT (combat_log_file_id, start_time) DO UPDATE SET updated_at = EXCLUDED.updated_at RETURNING id, xmax = 0 AS inserted` — the `xmax = 0` trick distinguishes a real insert from a no-op update. Falls back to a `Repo.get_by` if RETURNING isn't viable.
- After `:inserted`: run `Silver.project_and_persist(dim_encounter)` → `Gold.FactFailure.rebuild_for_encounter(dim_encounter.id)`. Legacy JSON-cache analysis is removed; medallion tables are the active read-model path.
- After `:existing`: do nothing by default. A future explicit rebuild flow (`mix wgn.rebuild_silver --encounter ID` or a Settings-page "rebuild" button) re-runs the silver/gold pipeline against the existing row without re-importing.
- This makes the trigger condition for silver/gold rebuild explicit and prevents duplicate imports from silently re-enqueuing potentially expensive rebuilds.

**Dual-source bronze ingestion**:
- `we_go_next/lib/we_go_next/combat_log_file.ex` — add `source` field (`:live` or `:warcraftlogs_archive`).
- `we_go_next/lib/we_go_next/accounts.ex` — `list_combat_logs_in_path/1` becomes `list_combat_logs/1` and scans BOTH `<wow_logs_path>/WoWCombatLog-*.txt` AND `<wow_logs_path>/warcraftlogsarchive/Archive-WoWCombatLog-*.txt`. Each result carries its `source` tag. No settings-UI change required — the archive folder is auto-discovered as a known sibling of the configured logs path. Update every existing caller of `list_combat_logs_in_path/1` (including SettingsLive) to go through the source-aware discovery path.
- `we_go_next/lib/we_go_next/bronze/reconciliation.ex` — shared helper for source tagging, live/archive suffix matching, head-fingerprint comparison, existing-row backfill, and moved-file row updates. `Accounts` and `Importer` both call this helper; UI modules do not duplicate move-detection logic.

- **Move detection** (`we_go_next/lib/we_go_next/bronze/reconciliation.ex`, called from `Accounts` and `Importer`): on a new file path, before insert, look for an existing `combat_log_files` row that could be the same logical file. A match requires ALL of:
  1. Same `user_id`.
  2. Basename pair match: the new file is `Archive-WoWCombatLog-<suffix>.txt` AND there exists a row whose basename is `WoWCombatLog-<suffix>.txt` (the suffix `<MMDDYY>_<HHMMSS>` is identical between the two). The inverse direction (`WoWCombatLog-*` appearing where an `Archive-WoWCombatLog-*` row exists) is not expected and is treated as a new file with a warning.
  3. Archive file's `file_size` is `>= existing row's recorded file_size`. If archive is smaller, treat as a new file (something is wrong — log loudly).
  4. Cheap content fingerprint match: SHA-256 of the first 4 KB of the archive file equals the existing row's recorded `head_sha256`. 4 KB is enough to cover the `COMBAT_LOG_VERSION` line plus several event lines — collisions are vanishingly unlikely between two distinct WoW logs.

  **Fallback when `head_sha256` is null on the existing row** (i.e. the live file was moved before the backfill ran): drop to (1) + (2) + (3) only — same user, basename-suffix pair match, archive size ≥ recorded live size — AND log a warning that we accepted the move on weak evidence. Operator-tunable; the conservative alternative is to refuse the move and treat as a new file (which means re-parsing it; not the end of the world, just slower).
- On match: UPDATE the existing row's `file_path` and `source = :warcraftlogs_archive`; do NOT bump `last_parsed_byte`. If archive `file_size > last_parsed_byte`, the very next import pass will continue parsing from `last_parsed_byte` against the new path and produce any encounters that finished after the last live-mode scan. The move detection does not skip that sync — it just avoids re-parsing what we already parsed.

- **FileWatcher reconciliation** (`we_go_next/lib/we_go_next/file_watcher.ex`): the watcher is a pure state holder — it caches the `%CombatLogFile{}` at `watch/1` time and exposes `current_file/0` and `watched_directory/0` (lines 65–105). It does NOT poll or stat files; auto-polling was deliberately removed (line 5). So `:enoent` is never observed by the watcher itself — file existence is checked by `Importer.do_import/1` and by the file-listing path in `Accounts.list_combat_logs/1`.

  Reconciliation therefore lives in those two call sites:

  - **`Accounts.list_combat_logs/1`** calls the shared bronze reconciliation helper while discovering files. When it updates a `combat_log_files` row's `file_path`, it casts the new struct to the FileWatcher only if the watcher is currently tracking that exact row:

    ```elixir
    case FileWatcher.current_file() do
      %CombatLogFile{id: id} when id == updated_clf.id -> FileWatcher.watch(updated_clf)
      _ -> :ok  # nothing tracked, or tracking a different file — no-op
    end
    ```

    The watcher's cached struct is replaced; `watched_directory/0` returns the new directory on the next call.
  - **`Importer.do_import/1`** does `File.stat!(path)` (or equivalent) on each `combat_log_files` row before parsing. If it hits `:enoent`, it calls the shared bronze reconciliation helper (using `head_sha256` against other candidate paths in the same logs directory + archive folder) and updates the row before retrying. If no match is found, log and skip for this iteration; do not add a new availability column.

  No `:tick` handler, no GenServer protocol additions. The watcher remains a passive cache that the importer and accounts module update when a move is detected.

**LiveView page** (`we_go_next/lib/we_go_next_web/live/failures_live/`):
- `index.ex` — "Mechanic failures across raid nights." Groups `gold.fact_failure` by player + criterion, displays a per-player rollup with date filters. Uses the page-object pattern for its feature test (per `CLAUDE.md` testing conventions).

**Tests**:
- `we_go_next/test/we_go_next/silver/round_trip_test.exs` — for a fixture encounter, assert `SUM(silver.damage_taken.total_amount)` per `(target_guid, spell_id)` equals the corresponding `DamageTakenAnalyzer.analyze/1` output. Repeat for deaths (count + killing-blow match), interrupt opportunities (success + missed counts match), debuffs (count match), and tank roles (`silver.player_info` rows with `detected_role = 'tank'` match the `tanks` list from `DamageTakenAnalyzer.analyze/1`).
- `we_go_next/test/we_go_next/silver/idempotency_test.exs` — running `Silver.project_and_persist/1` twice on the same encounter produces identical row counts and values (proves the `ON CONFLICT` keys are correct).
- `we_go_next/test/we_go_next/gold/fact_failure_test.exs` — for a fixture with a known mechanic failure, `fact_failure` contains the expected `(player, criterion, count)` row.
- `we_go_next/test/we_go_next/importer_move_test.exs` — import a live `WoWCombatLog-foo.txt`, then call list/import with the same content at `warcraftlogsarchive/Archive-WoWCombatLog-foo.txt`. Assert the row count in `combat_log_files` is still 1, `file_path` updated, `source` flipped to `:warcraftlogs_archive`, and no re-parse happened (last_parsed_byte unchanged).
- `we_go_next/test/features/failures_live_test.exs` — Wallaby test using a new `FailuresPage` page object under `test/support/pages/`.

---

## Verification

1. **Failure fact contract.** `gold.fact_failure` must be deterministic from silver rows plus `gold.dim_mechanic_criterion` snapshots. Fixture coverage should include avoidable damage (non-tank players hit by tracked mechanics), missed interrupts (raid-level failures via sentinel), and the "no criteria configured" trivial case. The test asserts that for every fixture encounter:

   ```sql
   SELECT dp.player_guid, ff.criterion_dim_id, ff.failure_count, ff.total_damage
   FROM gold.fact_failure ff
   JOIN gold.dim_player dp ON dp.id = ff.player_dim_id
   WHERE ff.encounter_dim_id = $1
   ORDER BY dp.player_guid, ff.criterion_dim_id
   ```

   …matches the expected aggregate rows:

   - `player_guid: nil` / `player_name: "Raid"` → `player_guid = '__RAID__'` (sentinel)
   - Group by `(player_guid, criterion_dim_id)` and aggregate:
     - `failure_count = SUM(hit_count)` for avoidable hits and missed casts
     - `total_damage = SUM(total_damage)` for avoidable damage; missed interrupts contribute 0

   This is the contract that proves failure facts preserve the intended rules semantics. If it fails, fix the silver projection, criterion snapshot selection, or SQL transform.

2. **Round-trip equality (silver-only).** For a fixture encounter, assert `SUM(silver.damage_taken.total_amount)` per `(target_guid, spell_id)` equals the corresponding `DamageTakenAnalyzer.analyze/1` output. Repeat for deaths (count + killing-blow match), interrupt opportunities (success + missed counts match), debuffs (count match). And: `silver.player_info` rows where `detected_role = 'tank'` exactly equal the set of `player_guid`s in `DamageTakenAnalyzer.analyze(encounter).tanks` (comparing against the public analyzer output, not the private `detect_tanks/1`).
3. **Idempotency.** Re-import the same combat log file → silver row counts identical, no duplicate-key errors. Re-running the importer with `:existing` tag does NOT rebuild silver. The `ON CONFLICT` keys are doing what they should.
4. **Move detection.** Import a fixture as `WoWCombatLog-foo.txt`; copy the same content to `warcraftlogsarchive/Archive-WoWCombatLog-foo.txt`; rescan. Assert `combat_log_files` still has 1 row, `file_path` updated, `source = :warcraftlogs_archive`, `last_parsed_byte` unchanged, no silver/gold rebuild fired. Then append additional content to the archive file (simulating WCL flushing post-last-scan events) and rescan — assert the importer parses from `last_parsed_byte` onward against the new path.
5. **End-to-end manual.** `mix phx.server`, import a fixture log via the existing UI, navigate to `/failures`, confirm the page renders rows for the encounters in the fixture. Cross-check one entry against the per-encounter Failures tab (which still uses the JSON cache).
6. **Layer independence smoke test.** `TRUNCATE gold.fact_failure`, then run a small `mix wgn.rebuild_gold` task (write it as part of this work) — gold gets rebuilt from silver without re-parsing any log. Proves the medallion guarantee actually holds.

7. **PR 1 acceptance gate.** Before PR 2 work starts, the first four gates above must pass together: gold parity, silver round-trip equality, idempotency, and move detection. This is a coordination gate, not a separate feature. It prevents the LiveView and rebuild-task work from masking unresolved projection or importer semantics.

---

## Implementation Sequencing — Suggested PR Split

The implementation risk is no longer architectural; it's parity. Recommend splitting the work into two PRs so the parity contract gates the first one cleanly:

**PR 1 — Silver projection + `fact_failure` parity (no UI).**

- Migrations: silver tables, gold schema, `dim_player` (+ sentinel seed), `fact_failure`, `combat_log_files.source`/`head_sha256`.
- Zig `project_silver/3` NIF.
- `Silver.project_and_persist/1`, `Gold.DimPlayer`, `Gold.FactFailure.rebuild_for_encounter/1`.
- `insert_or_fetch_encounter_from_boundary/2` refactor.
- Dual-source bronze: `list_combat_logs/1` + move detection + FileWatcher reconciliation in the call sites that actually stat files.
- All four verification gates 1–4 (parity, round-trip, idempotency, move detection) passing.
- No LiveView, no Mix rebuild task, no end-to-end manual UI verification.

**PR 2 — LiveView page + rebuild Mix task.**

Blocked until the PR 1 acceptance gate is complete.

- `failures_live/index.ex` and its `FailuresPage` page object + Wallaby test.
- `mix wgn.rebuild_gold` Mix task.
- Verification gates 5 (end-to-end manual) and 6 (layer independence) become exercisable.

Rationale: PR 1 is the dangerous one — if the parity contract doesn't hold, the silver schema or the SQL transform is wrong and needs revision. Shipping a LiveView page in the same PR adds review surface that's irrelevant to the question being tested. PR 2 is short and mostly mechanical once PR 1 is green.

---

## What This Does Not Do

- No dbt-postgres. One fact table doesn't earn dbt's overhead yet; revisit when fact count ≥ 3.
- No `parse_events` retirement. Kept for diagnostic use and projection rebuilds.
- No resurrection of `encounters.analysis`. The legacy JSON cache is no longer an active read-model path; new per-encounter analysis should be rebuilt against silver/gold/rules.
- No `dim_spell` mirror. Spell IDs in facts are integers from WoW; descriptive lookups (spell name, school) can fetch from `silver_*` rows or the existing spell-name tooling. Promote to a real `dim_spell` when a fact needs to filter/group by spell attributes.
- No dependency on `public.mechanic_criteria`. Mechanic business configuration lives under `rules`, and `gold.dim_mechanic_criterion` stores immutable snapshots for facts.
- No SCD2 on `dim_player`. Class/spec changes overwrite. Historical facts implicitly join the player's current attributes, not their attributes at encounter time. Real SCD2 (`valid_from`/`valid_to`/`is_current`) is the documented next step.

Each of these is a logical follow-on iteration. They get cheaper to add once silver exists.
