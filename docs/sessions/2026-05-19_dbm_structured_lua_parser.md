# 2026-05-19: DBM Structured Lua Parser

## Context

Task `#59 Replace DBM regex parsing with structured Lua parsing` replaced the initial line-regex DBM source parser before DBM evidence moves closer to candidate review and rules promotion.

The parser still supports static extraction only. It does not execute DBM Lua files.

## Implementation

Updated `WeGoNext.SourceData.DBM.Parser` to tokenize Lua source and extract balanced method-call forms for:

- `DBM:NewMod`
- `mod:SetRevision`
- `mod:SetEncounterID`
- `mod:SetZone`
- `mod:SetCreatureID`
- `mod:NewSpecialWarning*`
- `warning:SetAlert`

The parser now handles:

- single-quoted and double-quoted strings,
- inline comments without misreading `--` inside strings,
- commented-out declarations,
- nested table arguments such as `{149, 431}`,
- source file/line preservation.

Tree-sitter Lua was considered as the full-AST option, and NimbleParsec was noted as an Elixir-native parser-building option. The implemented choice is a smaller focused Elixir tokenizer/call extractor because the supported surface is intentionally narrow and does not need a complete Lua grammar or a native parser dependency.

## Corpus Check

The structured parser was checked against the installed local DBM Midnight corpus:

```text
/mnt/e/World of Warcraft/_retail_/Interface/AddOns/DBM-Raids-Midnight
/mnt/e/World of Warcraft/_retail_/Interface/AddOns/DBM-Party-Midnight
/mnt/e/World of Warcraft/_retail_/Interface/AddOns/DBM-Midnight
/mnt/e/World of Warcraft/_retail_/Interface/AddOns/DBM-Delves-Midnight
```

Coverage matched the previous parser:

```text
80 Lua files scanned
25 files with warning declarations
135 warning candidates extracted
```

Importing through `WeGoNext.SourceData.import_dbm_midnight_sources(build_key: "local")` inserted:

```text
25 source imports
135 DBM mechanic candidates
```

Candidate inference remained conservative:

```text
avoidable: 28
healer_mechanic: 1
interrupt: 6
soak: 6
tank_mechanic: 7
untyped/low-confidence: 87
```

## Verification

Focused checks passed:

```bash
mix test test/we_go_next/source_data/dbm/parser_test.exs
mix test test/we_go_next/source_data_test.exs
mix test test/mix/tasks/wgn_import_dbm_test.exs
```

The first `wgn_import_dbm_test` attempt was run concurrently with another app-starting test and hit the shared test endpoint port. Rerunning the CLI test by itself passed.

Full-suite and quality checks passed:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Result:

```text
5 features, 120 tests, 0 failures, 3 skipped
```
