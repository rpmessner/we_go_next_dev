# DBM Source Data Ingestion

## Context

Task #29 was refined around patch-aware source data for inferred mechanic rules. The key product decision is that users should not manually tag every condition. Source data should infer likely rules where possible, with user review/overrides for incorrect or ambiguous cases.

Local DBM is installed under:

```text
/mnt/e/World of Warcraft/_retail_/Interface/AddOns/
```

Relevant installed modules include:

- `DBM-Raids-Midnight`
- `DBM-Party-Midnight`
- `DBM-Midnight`
- `DBM-Delves-Midnight`
- `DBM-Core`

## Implementation

Added a dedicated `source_data` schema rather than overloading combat-log bronze tables or active rules.

Created:

- `source_data.source_import`
- `source_data.dbm_mechanic_candidate`
- `WeGoNext.SourceData`
- `WeGoNext.SourceData.SourceImport`
- `WeGoNext.SourceData.DbmMechanicCandidate`
- `WeGoNext.SourceData.DBM.Parser`

The DBM parser extracts:

- module id/addon/map id
- encounter id
- zone id
- creature ids
- module revision
- special-warning variable name
- warning constructor
- spell id
- role filter
- DBM common label tokens
- alert voice tokens from `SetAlert`
- source file and line number
- raw args and comments

Inference is conservative:

- `NewSpecialWarningInterrupt*` -> `interrupt`
- `NewSpecialWarningDodge*`, `GTFO`, movement labels/tokens -> `avoidable`
- `NewSpecialWarningSoak*`, `GROUPSOAK`, `GROUPSOAKS`, soak tokens -> `soak`
- tank constructors/labels/role filters -> `tank_mechanic`
- dispel/healer labels/role filters -> `healer_mechanic`

Candidates are stored as source evidence with confidence and review status. They do not create active rules or gold facts.

## Verification

Ran focused source-data tests:

```text
mix test test/we_go_next/source_data_test.exs test/we_go_next/source_data/dbm/parser_test.exs
```

Result:

```text
4 tests, 0 failures
```

Ran full suite:

```text
mix test
```

Result:

```text
5 features, 73 tests, 0 failures, 3 skipped
```

Also parsed a real installed DBM module:

```text
/mnt/e/World of Warcraft/_retail_/Interface/AddOns/DBM-Raids-Midnight/TheDreamrift/ChimaerustheUndreamtGod.lua
```

Observed:

- revision `20260509052555`
- encounter id `3306`
- zone id `2939`
- 10 warning candidates
- inferred counts: 2 avoidable, 1 interrupt, 1 soak, 6 low-confidence/unclassified

## Remaining Work

- Import all installed Midnight DBM modules through a Mix task or UI action.
- Add source-data read models for rule review.
- Cross-reference DBM candidates with observed silver rows.
- Add user override persistence and candidate promotion into draft rulesets.
- Add Blizzard/client DB2 source ingestion for spell and encounter name/version data.
