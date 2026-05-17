# Data Warehouse Refactor: Bronze, Silver, and Gold Foundation

## Date

2026-05-17

## Context

Continued the `Data Warehouse Refactor` task board from Task #3 through Task #8. The Phoenix app lives in `we_go_next/`; repo-level docs live in `docs/`.

This session established the bronze move-detection behavior, the initial silver/gold database shape, and Ecto schema modules for the new silver and gold tiers.

## Task Board Notes

The Tidewave task board stores dependency metadata explicitly. Completing a task does not automatically clear that task from downstream `blockedBy` lists, so downstream tasks were manually unblocked as prerequisites completed.

Completed in this session:

- #3 Live to Archive move detection
- #4 Filewatcher and importer reconciliation
- #5 Silver Table Migrations
- #6 Gold Schema and Table Migrations
- #7 Silver Ecto Schemas
- #8 Gold Ecto Schemas

Current remaining work:

- #9 Zig Silver Projection NIF
- #10 Silver Persistence API, blocked by #9
- #11 Gold DimPlayer Upsert, blocked by #10
- #12 Gold FactFailure Builder, blocked by #10 and #11
- #13 Refactor Importer Encounter Insert
- #14 Hook Silver and Gold into Importer, blocked by #10, #11, #12, #13
- #16/#17/#18/#19 verification tasks
- #22 PR 1 Acceptance Gate

## Bronze Move Detection

Implemented Task #3.

Added `WeGoNext.Bronze.CombatLogReconciler` to recognize when Warcraft Logs moves a live file into `warcraftlogsarchive`.

Matching rules:

- same `user_id`
- archive basename `Archive-WoWCombatLog-<suffix>.txt` matches live basename `WoWCombatLog-<suffix>.txt`
- archive file size is at least the recorded live size
- `head_sha256` matches when present
- if the existing row has no `head_sha256`, accept the move on weak basename/size evidence and log a warning

On match, the existing `combat_log_files` row is updated with the archive path and `source = :warcraftlogs_archive`; `last_parsed_byte` is preserved.

Accounts discovery and importer row creation both call the shared reconciler.

Verification:

```text
mix test test/we_go_next/bronze/combat_log_reconciler_test.exs test/we_go_next/accounts_test.exs test/we_go_next/combat_log_file_test.exs
14 tests, 0 failures
```

Commit:

```text
2845cb4 Add live to archive move detection
```

## FileWatcher and Missing-File Reconciliation

Implemented Task #4.

Changes:

- Added `FileWatcher.refresh_if_tracking/1`, which refreshes the cached watcher struct only when it is tracking the exact reconciled `combat_log_files` row.
- Accounts discovery refreshes FileWatcher after archive reconciliation only for that exact row.
- Importer now checks whether the current file path exists before parsing.
- If a live path is missing, Importer asks the shared bronze reconciler to find the archived replacement.
- If no replacement exists, Importer logs and skips with `0` new encounters for this iteration.

Verification:

```text
mix test test/we_go_next/bronze/combat_log_reconciler_test.exs test/we_go_next/accounts_test.exs test/we_go_next/combat_log_file_test.exs
18 tests, 0 failures
```

Commit:

```text
2f6ceda Add importer reconciliation and silver tables
```

## Silver Tables

Implemented Task #5.

Initially added six public `silver_*` tables, then corrected the architecture to use a dedicated `silver` schema before silver persistence was implemented.

Current physical tables:

- `silver.damage_taken`
- `silver.damage_done`
- `silver.death`
- `silver.interrupt_opportunity`
- `silver.debuff_application`
- `silver.player_info`

Design details:

- all silver tables keep surrogate `id` columns
- all have `encounter_id` FKs
- all have `inserted_at` only, no `updated_at`
- all have `encounter_id` indexes
- all have non-null natural-key unique constraints for idempotent reruns
- time key columns use integer milliseconds
- migration comments document sentinel expectations for nil-like natural-key values

The dedicated `silver` schema is now the canonical tier boundary. `DATA_WAREHOUSE_REFACTOR.md` was updated to use names such as `silver.damage_taken` instead of `public.silver_damage_taken`.

Verification:

```text
MIX_ENV=test mix ecto.migrate
mix ecto.migrate
```

Runtime schema check showed:

```text
silver.damage_done
silver.damage_taken
silver.death
silver.debuff_application
silver.interrupt_opportunity
silver.player_info
```

Commits:

```text
2f6ceda Add importer reconciliation and silver tables
09c496d Add silver schema modules
```

## Gold Tables

Implemented Task #6.

Added ordered migrations for:

- `gold` schema
- `gold.dim_player`
- `__RAID__` sentinel row in `gold.dim_player`
- `gold.fact_failure`

`gold.fact_failure` uses composite primary key:

```text
(encounter_id, player_dim_id, criterion_id)
```

It references:

- `public.encounters`
- `gold.dim_player`
- `public.mechanic_criteria`

Verification:

```text
MIX_ENV=test mix ecto.migrate
```

Commit:

```text
354f032 Add gold schema migrations
```

## Silver Ecto Schemas

Implemented Task #7.

Added six schema modules under `lib/we_go_next/silver/`:

- `WeGoNext.Silver.DamageTaken`
- `WeGoNext.Silver.DamageDone`
- `WeGoNext.Silver.Death`
- `WeGoNext.Silver.InterruptOpportunity`
- `WeGoNext.Silver.DebuffApplication`
- `WeGoNext.Silver.PlayerInfo`

Each schema uses:

```elixir
@schema_prefix "silver"
```

Each schema maps to the clean table name, for example `schema "damage_taken"` rather than `schema "silver_damage_taken"`.

Added `test/we_go_next/silver/schema_test.exs` to verify:

- schema prefix and table source
- basic changeset validity
- `silver.death.damage_recap` list-of-maps typing
- `silver.player_info.detected_role` validation

Verification:

```text
mix test test/we_go_next/silver/schema_test.exs test/we_go_next/accounts_test.exs test/we_go_next/combat_log_file_test.exs
11 tests, 0 failures
```

Commit:

```text
09c496d Add silver schema modules
```

## Gold Ecto Schemas

Implemented Task #8.

Added:

- `WeGoNext.Gold.DimPlayer`
- `WeGoNext.Gold.FactFailure`

Both use:

```elixir
@schema_prefix "gold"
```

`FactFailure` models the composite primary key through `belongs_to` fields:

- `encounter_id`
- `player_dim_id`
- `criterion_id`

Associations:

- `belongs_to :encounter, WeGoNext.Encounters.Encounter`
- `belongs_to :player, WeGoNext.Gold.DimPlayer`
- `belongs_to :criterion, WeGoNext.Criteria.MechanicCriteria`

Added `test/we_go_next/gold/schema_test.exs` for prefix/source, associations, composite primary key, and changeset coverage.

Verification:

```text
mix test test/we_go_next/gold/schema_test.exs test/we_go_next/silver/schema_test.exs
6 tests, 0 failures
```

Commit:

```text
ac6f418 Add gold Ecto schemas
```

## Architecture Decisions

### Silver Schema Boundary

Decision: move silver into a dedicated Postgres schema now.

Reasoning:

- Gold already had a dedicated schema.
- Dedicated `silver.*` tables make the medallion boundary concrete.
- It keeps `public` from becoming a mixture of operational app tables and analytical projections.
- The cost was low because silver persistence and gold builders had not been implemented yet.

Bronze was not moved into a dedicated schema in this session. Existing `combat_log_files` and `encounters` are still core app tables in `public`. Future external raw inputs such as Raider.IO, Warcraft Logs API, or Wowhead can use separate bronze ingestion tables/schemas when added.

### External Source Expansion

Conclusion: the current shape does not meaningfully paint us into a corner if tier boundaries stay disciplined.

Guidelines captured during discussion:

- Do not overload `combat_log_files.source` for non-file/API sources.
- Use separate bronze ingestion paths for Raider.IO, Warcraft Logs API, Wowhead, etc.
- Every future silver table should clearly answer: derived from what bronze input, at what grain, with what deterministic natural key?
- Keep source system and source record identifiers explicit for external-source natural keys.
- Phase grain can be added later, likely as `encounter_phases` plus phase-aware silver/gold projections, but raw WoW combat logs do not expose generic phase boundary events.

### Phase Grain

Phase grain is feasible later but not a free field addition.

Current parser recognizes encounter and challenge-mode boundaries, not generic boss phase boundaries. Raw WoW combat logs do not appear to provide a universal `PHASE_START`/`PHASE_END` event. Warcraft Logs has phase concepts in its API/UI, but local live-mode phase detection would require encounter-specific inference rules such as boss health thresholds, auras, casts, add spawns, or intermission markers.

Recommended future shape:

```text
encounter_phases(encounter_id, phase_index, phase_name, start_ms_into_fight, end_ms_into_fight, detection_source, metadata)
```

## Commits Created

```text
7b88459 Add bronze provenance columns
d6dc7f8 Add dual source combat log scanning
2845cb4 Add live to archive move detection
2f6ceda Add importer reconciliation and silver tables
354f032 Add gold schema migrations
09c496d Add silver schema modules
ac6f418 Add gold Ecto schemas
```

## Follow-up

Next task on the board is #9: implement the Zig `project_silver(file_path, start_byte, end_byte)` NIF.

Important dependencies after #9:

- #10 `WeGoNext.Silver.project_and_persist/1`
- #11 `Gold.DimPlayer.upsert_from_silver/1`
- #12 `Gold.FactFailure.rebuild_for_encounter/1`
- #13 importer insert refactor
- #14 importer hook for silver/gold

Acceptance-gate work remains open: silver round-trip tests, silver idempotency tests, gold fact parity tests, move detection tests, and PR 1 gate.
