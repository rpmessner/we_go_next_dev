# 2026-05-19: WowAnalyzer Timeline Source Import

## Context

Task `#58 Add WowAnalyzer timeline source import` implemented a source-data intake path for the local WowAnalyzer checkout:

```text
/home/rpmessner/dev/games/wow-addons/WoWAnalyzer
```

The target source directory is:

```text
src/game/raids/vs_dr_mqd
```

WowAnalyzer is licensed `AGPL-3.0-or-later`, so the app treats this input as provenance-tracked source evidence. Imported data is not active rules, not promoted gold criterion snapshots, and not fact-builder input.

## Implementation

Added:

- `source_data.wowanalyzer_timeline_candidate`
- `WeGoNext.SourceData.WowAnalyzerTimelineCandidate`
- `WeGoNext.SourceData.WowAnalyzer.Parser`
- `WeGoNext.SourceData.import_wowanalyzer_file/2`
- `WeGoNext.SourceData.import_wowanalyzer_sources/1`
- `WeGoNext.SourceData.list_wowanalyzer_timeline_candidates/1`
- `mix wgn.import_wowanalyzer`

The parser reads static TypeScript boss declarations as text. It extracts:

- encounter id and name,
- timeline type (`ability` or `debuff`),
- event type (`cast`, `begincast`, `summon`, `debuff`, or `buff`),
- spell id,
- boss-only flag when present,
- nearby source comments,
- source file and line,
- raw simple timeline entry fields.

The importer also stores repository revision and license metadata on both `source_data.source_import` and each timeline candidate row.

## Inference Boundary

Comments and timeline type are mapped to tentative mechanic candidates only:

- group soak comments -> `soak`,
- dispel/cleanse comments -> `healer_mechanic`,
- interrupt/kick comments -> `interrupt`,
- tank/taunt comments -> `tank_mechanic`,
- spread comments -> `spread`,
- movement/area-denial hints -> `avoidable`.

These are review hints. They do not write `rules.mechanic_criterion`, `gold.dim_mechanic_criterion`, or `gold.fact_failure`.

## Real Local Import

After migrating the development database, the importer was run through the project runtime against the local WowAnalyzer checkout with `build_key: "local"`.

Result:

```text
9 files imported
9 source imports inserted
81 candidates inserted
repository_license: AGPL-3.0-or-later
```

## Verification

Focused checks passed:

```bash
MIX_ENV=test mix ecto.migrate
mix test test/we_go_next/source_data/wow_analyzer/parser_test.exs
mix test test/we_go_next/source_data_test.exs
mix test test/mix/tasks/wgn_import_wowanalyzer_test.exs
```

The first `wgn_import_wowanalyzer_test` attempt was run concurrently with another test file and hit a test endpoint port collision; rerunning the CLI test by itself passed.

Full-suite verification also passed:

```bash
mix format --check-formatted
mix test
```

Result:

```text
5 features, 118 tests, 0 failures, 3 skipped
```
