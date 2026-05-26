# Data Warehouse Refactor Start

## Date

2026-05-17

## Context

Started implementation of the `Data Warehouse Refactor — Silver Tier, First Iteration` plan. The repo root is the parent directory and the Phoenix app lives in `we_go_next/`.

The refactor is tracked on the Tidewave task board named "Data Warehouse Refactor".

## Planning and Board Updates

- Reviewed `docs/DATA_WAREHOUSE_REFACTOR.md` for efficacy against the current Phoenix app.
- Added a PR 1 acceptance gate task to keep LiveView/rebuild-task work blocked until the silver/gold/importer parity work is verified.
- Tightened task descriptions around:
  - non-null deterministic silver natural keys,
  - integer millisecond time keys,
  - shared bronze reconciliation,
  - gold `fact_failure` parity against `FailureAnalyzer`,
  - move-detection continuation behavior.
- Updated `docs/DATA_WAREHOUSE_REFACTOR.md` with the same refinements.

## Oban Decision

Discussed whether to introduce Oban for pipeline/dependency orchestration.

Decision: do not introduce Oban in the first iteration. The immediate dependency graph is linear:

```text
encounter inserted -> project silver -> upsert dim_player -> rebuild fact_failure
```

For now this should remain a plain orchestrator function with idempotent database writes and explicit rebuild tasks. Oban becomes attractive later if durable retries, queue concurrency, job history, UI-triggered rebuilds, or operational visibility become necessary. A true DAG would point more directly at Oban Pro Workflows, not hand-rolled dependency edges on top of Oban OSS.

## Task 1: Bronze Provenance Columns

Implemented and completed Task #1.

Changes:

- Added `combat_log_files.source`, defaulting to `live`, constrained to `live` or `warcraftlogs_archive`.
- Added nullable `combat_log_files.head_sha256`.
- Updated `WeGoNext.CombatLogFile` with:
  - `Ecto.Enum` source field,
  - source validation and DB check constraint handling,
  - `head_sha256` format validation,
  - `attrs_from_file/3` computing the first-4KB SHA-256 for new rows.
- Added `WeGoNext.Bronze.FileFingerprint.head_sha256/1`.
- Added opportunistic scan-time backfill for existing rows whose file still exists and whose `head_sha256` is null.

Verification:

- Applied migration to test and dev databases.
- Focused tests passed:

```text
mix test test/we_go_next/bronze/file_fingerprint_test.exs test/we_go_next/combat_log_file_test.exs test/we_go_next/accounts_test.exs
8 tests, 0 failures
```

- Browser reload of `/` succeeded after the migration.
- Full `mix test` had one existing feature-test failure in `test/features/encounter_list_test.exs`; it expects a visible submit button while the hard-coded `/mnt/g/World of Warcraft/_retail_/Logs` path is missing in the test environment.

Commit:

```text
7b88459 Add bronze provenance columns
```

## Task 2: Dual Source Combat Log Scanning

Implemented and completed Task #2. These changes are currently uncommitted at the time this session note was written.

Changes:

- Updated `Accounts.list_combat_logs/1` to scan both:
  - `<logs>/WoWCombatLog-*.txt` as `:live`,
  - `<logs>/warcraftlogsarchive/Archive-WoWCombatLog-*.txt` as `:warcraftlogs_archive`.
- Missing `warcraftlogsarchive` is treated as empty rather than an error.
- SettingsLive now uses the same user-aware scanner as the main page, so it no longer bypasses source-aware discovery or fingerprint backfill.
- `CombatLogFile.attrs_from_file/3` now infers `:warcraftlogs_archive` from `Archive-WoWCombatLog-*` filenames when no explicit `source` is passed.
- Added focused tests for mixed live/archive discovery and archive source inference.

Verification:

- Focused tests passed:

```text
mix test test/we_go_next/accounts_test.exs test/we_go_next/combat_log_file_test.exs test/we_go_next/bronze/file_fingerprint_test.exs
10 tests, 0 failures
```

- Browser reload of `/` showed both live and archived logs in the import dropdown.
- Browser reload of `/settings` showed both live and archived logs in the Settings watcher dropdown.
- Full `mix test` still has the same existing `EncounterListTest` page-object failure described above.

## Current Board State

- #1 Bronze Provenance Columns: completed
- #2 Dual Source Combat Log Scanning: completed
- #3 Live to Archive move detection: pending and now unblocked

## Follow-up

Next task is #3: implement live-to-archive move detection behind a shared bronze reconciliation helper. This should move the scan-time fingerprint backfill behavior out of `Accounts` and into bronze reconciliation so `Accounts` remains focused on discovery.
