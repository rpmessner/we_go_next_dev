# Tool read paths over bronze, silver and gold

Research for `we-c5q.3`: *How can Tools read bronze, silver and gold fast enough over 1GB+ logs?*
Date: 2026-10-29. Branch: `research/tool-read-paths` (from `main` @ `937befe`).

Tools are read-only, deterministic Elixir functions called by an LLM agent during an
interactive chat between pulls. "Interactive" here means one Tool call should usually come
back well under a second, and never block the BEAM.

All numbers below were measured on this machine (WSL2, 8 vCPU, 7 GB RAM) unless marked
**estimate**. Benchmark scripts are in [`docs/research/scripts/`](scripts/).

## Short answer

| Question family | Recommended read path | Measured latency |
|---|---|---|
| Who died, when, killing blow, death recap | `silver.death` (has `damage_recap` + `window_events`) | 0.06-0.08 ms warm, 3 ms cold |
| Hits on a player / from a spell / in a window | `silver.damage_taken_event` | 0.6-1.0 ms per pull |
| Damage done leaderboard | `silver.damage_done` (no pet attribution on `main`, see below) | 1.7 ms warm, 43 ms cold |
| Debuffs by spell / target | `silver.debuff_application` | 0.45 ms |
| Interrupts / enemy casts | `silver.interrupt_opportunity` (semantics caveat, task #61) | 0.03 ms |
| Mechanic failures | `gold.fact_failure` + dims | 0.06 ms per pull, 0.3 ms per player across all pulls |
| "Summarize this pull" | Encounter document JSON on disk | 8-18 ms read + decode (1 MB) |
| Same spell across all pulls of a boss | `silver.damage_taken_event` + `gold.dim_encounter` | 18-20 ms warm (26 pulls) |
| One player across every pull | `silver.damage_taken_event` (seq scan) | 63-66 ms warm, 115 ms cold |
| Anything silver does not store (heals, buffs, casts, resources, player damage-done events, positions) | Bronze re-parse of one pull's byte range | 1.0-1.3 s full parse, **0.14-0.21 s with an in-NIF prefilter** (local disk, ReleaseSafe); add ~0.5 s from `/mnt/e` |

Silver and gold already answer the common families in milliseconds. Bronze is the only path
for raw slices, and it is usable at interactive speed only if three things change: build the
NIF in a release mode, run it on a dirty scheduler, and filter lines inside the NIF before
building Erlang terms. The encounter → byte-range index already exists.

## Bronze

### What exists

- There is no `LogReader` module on `main`. AGENTS.md's directory listing (`log_reader.ex`) is
  stale. Byte scanning and event normalization live in the Zig NIF
  [`we_go_next/priv/native/combat_log_parser.zig`](../../we_go_next/priv/native/combat_log_parser.zig),
  wrapped by `WeGoNext.CombatLogParser` (`we_go_next/lib/we_go_next/combat_log_parser.ex`).
  - `scan_boundaries(path, start_byte)` streams the file in 64 KB reads and returns
    `ENCOUNTER_START`/`ENCOUNTER_END` and `CHALLENGE_MODE_*` boundaries with `start_byte`,
    `end_byte`, timestamps and metadata, plus the last line-aligned byte.
  - `parse_events(path, start_byte, end_byte, start_ts)` seeks, reads the whole range into one
    buffer (`page_allocator.alloc(byte_count)`), and turns every line into an Erlang map.
    There are no filter arguments. It already re-parses one encounter on demand: that is how
    the importer builds silver (`Importer.parse_events_for_encounter/2`).
- `public.combat_log_files` tracks `file_path`, `file_size`, `last_parsed_byte`, `head_sha256`
  (`we_go_next/lib/we_go_next/combat_log_file.ex`). The importer only advances
  `last_parsed_byte` through the last *completed* encounter (`Importer.completed_boundary_end_byte/2`).
- **The encounter → byte-range index exists**, twice:
  - `public.encounters`: `combat_log_file_id`, `start_byte`, `end_byte`, `start_time`
    (unique on `combat_log_file_id, start_time`).
  - `gold.dim_encounter`: `source_file_path`, `source_head_sha256`, `start_byte`, `end_byte`,
    indexed on `(source_head_sha256, start_byte)`.
  - Resolving a `dim_encounter.id` to `{file_path, start_byte, end_byte, start_time}` took
    **0.05-0.07 ms** (`silver_gold_bench.sql` Q11).
- There is no index for trash between pulls. Trash is the gap between one pull's `end_byte`
  and the next pull's `start_byte`; `WeGoNext.TrashPull` only segments trash inside M+ runs.

### Gaps in the bronze path

1. **Dev builds the NIF in Zig `Debug` mode.** zigler defaults to `:debug` when
   `Mix.env()` is `dev`/`test` and `:safe` (ReleaseSafe) otherwise
   (`deps/zigler/lib/zig/_module.ex`, `default_optimize/0`). The local operator runs dev, so
   every number the operator sees is the slow one. Debug is 2.2-3.9x slower (table below).
2. **The NIF is synchronous.** `use Zig` sets no `concurrency`, so zigler uses its default
   `:synchronous`. A 1-4 s call holds a normal BEAM scheduler for that long. For an
   interactive LiveView this needs `concurrency: :dirty_cpu` (or `:dirty_io`) on
   `parse_events` and `scan_boundaries`.
3. **Stale bronze paths.** 10 of the 29 `combat_log_files` rows point at
   `Logs/WoWCombatLog-*.txt` files that the Warcraft Logs uploader has since moved to
   `Logs/warcraftlogsarchive/Archive-*.txt`. `CombatLogReconciler.reconcile_missing_file/1`
   fixes this, but it updates the row, so a read-only Tool needs a pure resolver (by file
   name or `head_sha256`) or must ask the operator to reconcile first.
4. **The Sept 6 log is not imported.** `Archive-WoWCombatLog-090626_103607.txt` (1,168,915,469
   bytes) has no `combat_log_files` row, so its pulls have no silver/gold. The newest imported
   log is Aug 19. Bronze numbers below use the Sept 6 file directly; silver/gold numbers use the
   heaviest imported pull.

### Measurements: Sept 6 log

Log: `Archive-WoWCombatLog-090626_103607.txt`, 1,168,915,469 bytes, 18 encounter pulls (all
Mythic), 1,033 MB of the file inside pull ranges. Pull sizes: min 0.1 MB, median 65.9 MB,
max 106.7 MB.

Script: [`scripts/bronze_bench.exs`](scripts/bronze_bench.exs). Each parse ran 3 times; all
three timings are shown. "Local" is a copy on WSL ext4. `/mnt/e` is the Windows drive over 9p
(`cache=0x5`, so Linux does not page-cache it).

| Step | Debug (dev today), local | ReleaseSafe, local | ReleaseSafe, `/mnt/e` |
|---|---|---|---|
| `scan_boundaries` full file | 6,972-7,857 ms | 1,831-2,088 ms | 9,911 ms |
| `parse_events` largest pull (Twin Fangs, 445 s, 106.7 MB, 368,632 events) | 2,214-3,930 ms | 1,039-1,342 ms | 1,405-1,746 ms |
| `parse_events` median pull (Sszorak, 411 s, 65.9 MB, 231,163 events) | 1,298-1,756 ms | 540-669 ms | 834-975 ms |
| `parse_events` 0.1 MB reset pull (60 events) | 1.5-1.7 ms | 0.3-0.4 ms | 4.3-4.6 ms |

Memory for the largest pull: the event list is **202 MB** of BEAM heap (`:erts_debug.flat_size`
× 8); `:erlang.memory(:total)` grew 313-351 MB across one parse. The NIF also allocates a
107 MB read buffer for the range. Peak RSS of the whole bench process was 1.40-1.59 GB. The
median pull's list is 127 MB.

Event mix in the largest pull (top 8): `SPELL_DAMAGE` 74,570, `SPELL_HEAL` 41,126,
`SPELL_PERIODIC_DAMAGE` 32,652, `SPELL_PERIODIC_HEAL` 32,453, `SPELL_AURA_REFRESH` 29,988,
`SPELL_AURA_APPLIED` 29,288, `SPELL_AURA_REMOVED` 26,044, `SPELL_AURA_APPLIED_DOSE` 17,531.

Filtering after a full parse is cheap: one player + one spell + 30 s window over the 368,632
events took 15.8-17.5 ms and returned 16 events. The cost is the parse, not the filter.

Running the full in-memory silver projection (`Silver.Projector.project/3`, no DB) over the
largest pull took 3,714-4,787 ms. Recomputing silver at Tool time is not an option.

### Raw I/O

Script: [`scripts/io_bench.sh`](scripts/io_bench.sh), 107 MiB sequential read.

| Source | Time |
|---|---|
| `/mnt/e`, file not read this session, first read | 1.00 s (112 MB/s) |
| `/mnt/e`, repeat reads | 0.48 s (231-237 MB/s) |
| Local ext4 copy | 0.012-0.036 s |

Copying the whole 1.17 GB log from `/mnt/e` to local disk took 12.1 s. So `/mnt/e` adds about
0.4-1.0 s to every pull-sized read, every time; local disk makes I/O negligible.

### Prototype: filter inside the NIF

Script: [`scripts/bronze_filter_bench.exs`](scripts/bronze_filter_bench.exs). It copies the Zig
source to a scratch dir, adds a `needle` argument to `parse_events`, and skips lines that do
not contain the needle before any term is built. ReleaseSafe, local disk, largest pull:

| Filter | Time (3 runs) | Events returned | Term size |
|---|---|---|---|
| none | 1,043-1,342 ms | 368,632 | 202 MB |
| player GUID | 159-211 ms | 15,847 | 8.8 MB |
| NPC spell id (`,1290480,`) | 187-190 ms | 13,607 | 7.3 MB |
| `UNIT_DIED` | 137-141 ms | 29 | ~0 MB |

The floor (about 140 ms) is reading 107 MB plus a substring scan per line. Term building is
about 85% of the unfiltered cost. A substring needle is a prefilter: a GUID matches both source
and target, so a Tool still applies an exact field filter afterwards (about 1 ms on 15k events,
**estimate** scaled from the 368k-event filter above).

## Silver and gold

Dev DB `we_go_next_dev` (read with `default_transaction_read_only=on`): 29 log files, 454
`public.encounters`, 434 `gold.dim_encounter`, 4,027 `gold.fact_failure`. Silver row counts and
total sizes:

| Table | Rows | Size | Grain (natural key) | Indexes beyond PK/natural key |
|---|---|---|---|---|
| `damage_taken_event` | 1,557,931 | 687 MB | one row per player-targeted damage hit: `(encounter_dim_id, combat_log_event_index)` | `(enc)`, `(enc, spell_id)`, `(enc, target_guid)` |
| `damage_done` | 710,391 | 275 MB | aggregate `(enc, source_guid, target_guid, spell_id)` | `(enc)` |
| `debuff_application` | 120,246 | 45 MB | `(enc, target, source, spell, applied_at_ms)` | `(enc)` |
| `damage_taken` | 90,553 | 36 MB | aggregate `(enc, target, source, spell)` | `(enc)` |
| `interrupt_opportunity` | 128,173 | 34 MB | `(enc, npc_guid, spell, at_ms)` | `(enc)` |
| `death` | 6,297 | 24 MB | `(enc, target_guid, died_at_ms)`, with `damage_recap` and `window_events` jsonb arrays | `(enc)` |
| `defensive_buff_window` | 31,158 | 11 MB | `(enc, target, source, spell, started_at_ms)` | `(enc)`, `(enc, target)` |
| `survival_action` | 23,625 | 9 MB | `(enc, caster, target, spell, used_at_ms)` | `(enc)`, `(enc, target)` |
| `player_info` | 8,273 | 9 MB | `(enc, player_guid)` | `(enc)` |

`gold.fact_failure` is keyed `(encounter_dim_id, player_dim_id, criterion_dim_id)` with
indexes on `player_dim_id` and `criterion_dim_id`. `gold.dim_player` is unique on
`player_guid`; `gold.dim_encounter` is indexed on `wow_encounter_id`.

Encounter documents (`we_go_next/documents/encounters/*.json`, 435 files, up to 1.0 MB) already
bundle roster, deaths, damage done, damage-taken spells, debuffs (boss/player), survival usage,
interrupt coverage, failure preview, personal pull summaries and observed mechanics per pull.

### Query timings

Script: [`scripts/silver_gold_bench.sql`](scripts/silver_gold_bench.sql), `EXPLAIN (ANALYZE,
BUFFERS)` on the heaviest imported pull: `dim_encounter.id = 268`, Vaelgor & Ezzorak Mythic,
474 s, 14,670 `damage_taken_event` rows. Cold = first run of the session; warm = second run.

| # | Query | Cold | Warm | Plan |
|---|---|---|---|---|
| Q1 | deaths in one pull, with recap arrays (15 rows) | 2.99 ms | 0.06-0.08 ms | index on natural key |
| Q2 | one player × one spell × time window | 3.42 ms | 0.54-0.58 ms | bitmap on `(enc, spell_id)` |
| Q3 | one spell in one pull, per player (3,559 hits) | 0.78 ms | 0.78-0.99 ms | bitmap on `(enc, spell_id)` |
| Q4 | damage done leaderboard (9,854 rows aggregated) | 43.3 ms | 1.7 ms | bitmap on `(enc)` |
| Q5 | debuffs by spell | 7.0 ms | 0.45 ms | |
| Q6 | interrupt opportunities by spell | 0.51 ms | 0.03 ms | |
| Q7 | failures in one pull with dims | n/a | 0.06 ms | |
| Q8 | one spell across all 26 pulls of that boss + difficulty | 127.8 ms | 18.0-20.4 ms | 26 bitmap scans on `(enc, spell_id)` |
| Q9 | one player across every pull | 114.6 ms | 62.8-66.2 ms | **parallel seq scan** (no `target_guid`-leading index) |
| Q10 | one player's failures across every pull | n/a | 0.3 ms | |
| Q11 | `dim_encounter` → file path + byte range | 1.5 ms | 0.05-0.07 ms | |

Encounter document read + `Jason.decode!` for a 1.0 MB file: 8.4-18.4 ms.

### What the tables do not cover

- **Pet and guardian damage on `main`.** `Silver.Projector.project_damage_done/2` only counts
  rows whose source GUID is a `Player-`. AGENTS.md describes `pet_owner_map/1` and an
  `owner_guid` NIF field, but that work (`d7b2a7c`, we-yv9) is only on the unmerged branch
  `rpmessner/pet-damage-attribution`. Until it merges, pet-heavy specs are under-counted in
  `silver.damage_done`.
- **Interrupts.** `silver.interrupt_opportunity` still marks every NPC `SPELL_CAST_SUCCESS` as
  `success = false` (ARCHITECTURE.md, task #61). A Tool should present these as observed
  casts, not missed kicks.
- **No event grain** for healing, buffs (other than defensive windows and survival actions),
  casts, resources, player damage-done hits, or positions. Death windows hold 10 s of
  damage/heal/usage per death, capped at 100 events.
- **No trash index** outside M+ runs.

## Gaps and options

What a Tool needs that no layer provides: raw event slices filtered by unit, spell, event type
and time window, for event families silver does not store (for example "what healed X in the
5 s before they died, beyond the recap", "when did the boss cast Y", "who had buff Z up during
phase 2"). AGENTS.md forbids turning silver into a raw-event warehouse, so the options are
bronze-side:

1. **Use the existing byte-range index; add nothing to the schema.** `dim_encounter` /
   `public.encounters` already give `{path, start_byte, end_byte, start_time}` in 0.05 ms.
   The Tool needs a read-only path resolver for archive moves (gap 3).
2. **Build the NIF in ReleaseSafe for dev and run it dirty.** Set `optimize: :safe` (or
   `{:env, :safe}`) and `concurrency: :dirty_cpu` on both NIFs in `use Zig`. Measured gain:
   largest pull 2.2-3.9 s → 1.0-1.3 s; full scan 7-8 s → 1.8-2.1 s. This also speeds up
   imports. Smallest change with the largest effect.
3. **Filter inside the NIF.** Add a filtered entry point (`parse_events_filtered/5`) that takes
   a needle or, better, typed filters (event types, GUIDs, spell ids, time window) and skips
   lines before building terms. Measured with a substring needle: 1.04-1.34 s → 0.14-0.21 s and
   202 MB → 7-9 MB. Typed filters would check fields the parser already splits, so the cost
   should stay close to the needle numbers (**estimate**). Keep the existing `parse_events/4`
   unchanged for the import path.
4. **Keep bronze off `/mnt/e` for Tool reads.** Every pull-sized read from `/mnt/e` costs
   0.48 s warm and about 1.0 s cold, and Linux does not cache it. Options: copy the current
   night's log to local disk once (12 s for 1.17 GB), or copy each pull's byte range to a local
   per-encounter file at import time (about 1 GB per raid night). With local bytes and option
   3, a filtered slice of the largest pull is about 0.15-0.2 s.
5. **Do not cache whole parsed encounters in the BEAM.** One pull is 127-202 MB of heap; a
   night of 18 pulls would be about 2.3 GB (**estimate**, 18 × median 127 MB) on a 7 GB machine.
   Cache filtered slice results instead (KB-MB each), keyed by `(dim_encounter_id, filter)`,
   if repeat queries show up in session records. Per the repo's caching rule, try options 2-4
   first.
6. **Add one silver index only if cross-pull player questions are common.** Q9 (one player
   across every pull) is the only query that seq-scans; 63-66 ms warm is acceptable today. A
   `(target_guid, encounter_dim_id)` index on `damage_taken_event` would fix it if it becomes a
   hot Tool. This is an index, not a new event table, so it does not widen silver.

Recommended read order for a Tool: encounter document or gold first (summaries, failures),
then silver tables (deaths, hits, debuffs, damage done), then a filtered bronze re-parse for
anything else. Bronze re-parse should always be scoped to one pull and filtered.

## Not measured

- Typed (field-level) NIF filters; only a substring prefilter was prototyped.
- `dirty_cpu` scheduling under concurrent LiveView load, and the effect of a synchronous 1-4 s
  NIF on other processes. The concern comes from zigler's default and BEAM rules, not from a
  measurement.
- Truly cold `/mnt/e` reads: the Windows host cache cannot be dropped from WSL, so "cold" is
  "first read this session".
- Silver/gold for the Sept 6 log itself, which is not imported. Silver timings use pull 268
  from Jul 12.
- `ReleaseFast`; only `Debug` (dev default) and `ReleaseSafe` (prod default) were measured.

## Sources

- `we_go_next/priv/native/combat_log_parser.zig` (`scan_boundaries`, `parse_events`)
- `we_go_next/lib/we_go_next/combat_log_parser.ex` (`use Zig` options)
- `we_go_next/lib/we_go_next/importer.ex` (byte progress, `parse_events_for_encounter/2`, dim identity)
- `we_go_next/lib/we_go_next/silver/projector.ex` (`project/3`, `project_damage_done/2`)
- `we_go_next/lib/we_go_next/bronze/combat_log_reconciler.ex`
- `we_go_next/lib/we_go_next/documents.ex`, `documents/encounter_document.ex`
- `we_go_next/deps/zigler/lib/zig.ex`, `deps/zigler/lib/zig/_module.ex` (zigler 0.15.2 optimize and concurrency defaults)
- `docs/ARCHITECTURE.md` (event-grain policy, interrupt semantics gap)
- Dev DB `we_go_next_dev`: `pg_indexes`, `pg_stat_user_tables`, `EXPLAIN ANALYZE`
- Commit `d7b2a7c` on `rpmessner/pet-damage-attribution` (not on `main`)
