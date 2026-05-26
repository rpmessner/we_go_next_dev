# 2026-05-19: Reference Dimensions, Quality Gate, and CI Stabilization

## Context

This session moved the source-data roadmap forward, then added a local and CI quality gate for the Phoenix app.

The work started from task `#49`, which needed conformed spell and encounter reference dimensions before source-data facts and rule promotion start relying on spell and encounter metadata. After that, the user asked for code quality checks that could run locally and in CI. The first GitHub Actions runs exposed several CI-only assumptions around Zig installation and ignored combat-log fixtures, which were fixed in follow-up commits.

## Task Board Updates

- Completed `#49 Add conformed spell and encounter reference dimensions`.
- Created and completed `#56 Add local and CI code quality checks`.
- Created and completed `#57 Fix CI temp-directory test failures`.

## Reference Dimensions

Commit: `7933211 Add conformed source reference dimensions`

Added build-scoped source-data reference tables:

- `source_data.spell_reference`
- `source_data.encounter_reference`

Added schemas:

- `WeGoNext.SourceData.SpellReference`
- `WeGoNext.SourceData.EncounterReference`

The reference rows carry:

- spell or encounter identity,
- current display name,
- localized name map,
- product,
- channel,
- build version and build key,
- locale,
- source system,
- source priority,
- optional `source_import_id`,
- metadata.

Retail, beta, and PTR rows can coexist because lookup scope includes product, channel, build key, locale, and source system. Lookup helpers prefer lower `source_priority` values inside the requested build scope.

`WeGoNext.SourceData` now exposes upsert and lookup helpers for spell and encounter references. Rules seed and promotion paths can resolve spell and boss names from source-data references when a build scope is provided, falling back to static authored names when no reference exists.

`docs/ARCHITECTURE.md` was updated to document the new source-data boundary.

## Formatter Cleanup

Commit: `e6f5e00 Format active Elixir sources`

The initial quality-gate work found existing formatter drift in active non-generated Elixir files. A mechanical `mix format` cleanup was committed separately so the quality gate could enforce formatting going forward without mixing behavior changes into the CI setup commit.

Generated/static game-data modules remain excluded from formatter enforcement for now because they have broad pre-existing formatter churn and are better handled separately.

## Local Quality Gate and CI

Commit: `1f8dc76 Add quality gate and CI workflow`

Added `mix quality`, which runs:

```bash
mix format --check-formatted
mix zig.get
mix compile --warnings-as-errors
mix credo --only warning
mix ecto.create --quiet
mix ecto.migrate --quiet
mix test
```

Added GitHub Actions workflow:

- `.github/workflows/ci.yml`
- runs on pull requests and pushes to `main`,
- starts PostgreSQL 16,
- sets up OTP 28 and Elixir 1.19,
- fetches dependencies,
- runs `mix quality`.

`README.md` now documents `mix quality` as the local CI gate.

## CI Stabilization

The first CI runs uncovered issues that were not visible locally.

### Zig Not Installed

Commit: `8e05ce5 Install Zig in quality gate`

The first failure was:

```text
zig executable not found
```

`mix quality` was updated to run `mix zig.get` before compile.

### Zig Extraction Race

Commit: `9b7e44d Wait for Zig toolchain in quality checks`

The next run showed `mix zig.get` downloading and extracting Zig, but Zigler still could not see the executable immediately afterward. A wait was added locally and in CI to check for the expected executable before compiling.

### Cached Zig FileBusy

Commit: `306511b Use setup-zig for CI builds`

After the wait fix, CI moved forward but failed with:

```text
error: unable to wait for .../.cache/zigler/.../zig: FileBusy
```

The workflow was changed to use `mlugg/setup-zig@v2` and set:

```bash
ZIG_EXECUTABLE_PATH=$(command -v zig)
```

This points Zigler at the workflow-installed Zig binary instead of the Zigler cache copy. The workflow no longer caches `~/.cache/zigler`.

## Fixture and Temp-Directory Test Fix

Commit: `05fbee8 Track combat log fixture for CI`

Once CI reached the test suite, several importer and feature tests failed because they referenced:

```text
test/fixtures/WoWCombatLog-112725_120000.txt
```

That file existed locally but was ignored by the root `.gitignore` rule:

```text
WoWCombatLog*.txt
```

The fix was to add a tracked neutral fixture:

- `test/fixtures/combat_log_base.txt`

Tests now copy that tracked fixture into per-test temporary files named `WoWCombatLog-112725_120000.txt`, preserving app behavior while avoiding ignored fixture names.

Feature setup now creates per-test temp log directories instead of pointing the UI directly at `test/fixtures`. This keeps tests portable in CI and avoids shared fixture-directory mutation.

## Verification

Focused test run after the fixture fix:

```bash
mix test test/we_go_next/importer_test.exs test/features/minimal_flow_test.exs test/features/import_status_test.exs test/features/live_sync_test.exs
```

Result:

```text
3 features, 8 tests, 0 failures
```

Full quality gate:

```bash
ZIG_EXECUTABLE_PATH="$HOME/.cache/zigler/zig-x86_64-linux-0.15.2/zig" mix quality
```

Result:

```text
5 features, 85 tests, 0 failures, 3 skipped
```

GitHub Actions was reported passing after the final fixture fix.

## Notes and Follow-Up

- `mix quality` is now the expected local pre-push gate.
- Full Credo still has existing readability/refactor debt outside `--only warning`; the CI gate intentionally enforces warning checks first.
- Formatter enforcement excludes `lib/we_go_next/game_data/**/*.ex` until generated/static game-data formatting is handled in its own cleanup.
- Future test fixtures should avoid names matched by repository ignore rules, or should be explicitly unignored.
