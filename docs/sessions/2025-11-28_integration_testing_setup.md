# Session: Integration Testing Setup with Wallaby
**Date:** 2025-11-28
**Focus:** Set up end-to-end integration tests using Wallaby/ChromeDriver

## Overview
Implemented comprehensive browser-based integration tests for the combat log workflow. Set up SQL sandbox for database isolation in browser tests, created test fixtures, and fixed several bugs discovered during testing.

## What Was Built

### 1. SQL Sandbox Configuration for Browser Tests

**Problem:** Wallaby browser tests run in a separate process from the test, so they can't share the Ecto SQL Sandbox connection by default.

**Solution:**
- Added `phoenix_ecto` dependency for `Phoenix.Ecto.SQL.Sandbox` plug
- Configured endpoint to conditionally load sandbox plug in test environment
- Created `FeatureCase` test helper that passes sandbox metadata to Wallaby sessions

**Files:**
- `mix.exs` - Added `{:phoenix_ecto, "~> 4.4"}`
- `config/test.exs` - Added `sql_sandbox: true`, increased `pool_size` and `ownership_timeout`
- `lib/we_go_next_web/endpoint.ex` - Added conditional sandbox plug
- `test/support/feature_case.ex` - Sets up sandbox and passes metadata to sessions

### 2. Test Fixtures

Created minimal combat log fixtures for testing without requiring a live WoW session:

**Files:**
- `test/fixtures/WoWCombatLog-112725_120000.txt` - Base log with one encounter (Test Boss, WIPE)
- `test/fixtures/second_encounter.txt` - Additional encounter (Second Boss, KILL) for sync testing

### 3. Integration Test Suite

Created 6 feature tests covering the complete workflow:

#### `test/features/minimal_flow_test.exs`
End-to-end flow test:
- Home page loads
- Select and import combat log
- Verify encounter list displays
- Click encounter → verify detail page
- Switch tabs (Summary, Deaths, etc.)
- Navigate back to home

#### `test/features/live_sync_test.exs`
Manual refresh flow (simulates WoW appending to log):
- Import initial log with 1 encounter
- Append new encounter to file (simulates WoW writing)
- Click "Refresh" button
- Verify new encounter appears
- Includes multi-sync test (3 encounters)

#### `test/features/auto_update_test.exs`
FileWatcher + PubSub auto-update flow:
- Import initial log
- Append new encounter to file
- Wait for FileWatcher to detect (polls every 1 second)
- Verify dashboard auto-updates via PubSub (no manual refresh needed)
- Validates Phase 3 of Integration Roadmap

### 4. Bug Fixes Discovered During Testing

#### Timestamp Handling in Importer
**File:** `lib/we_go_next/importer.ex`

**Problem:** `DateTime` values had microseconds, causing Ecto errors with `:utc_datetime` fields.

**Fix:**
```elixir
# Changed from:
now = DateTime.utc_now() |> DateTime.truncate(:second)
# To:
now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

# Added truncation for file_mtime and last_parsed_at
mtime_dt = ... |> DateTime.truncate(:second)
last_parsed_at: DateTime.utc_now() |> DateTime.truncate(:second)
```

#### FileWatcher Crash on Deleted Records
**File:** `lib/we_go_next/file_watcher.ex`

**Problem:** `Repo.get!` crashed when the CombatLogFile record was deleted (e.g., during test sandbox cleanup).

**Fix:**
```elixir
# Changed from:
clf = Repo.get!(CombatLogFile, clf.id)

# To:
case Repo.get(CombatLogFile, clf.id) do
  nil ->
    Logger.debug("FileWatcher: Watched file record no longer exists, stopping")
    {:noreply, %{state | clf: nil, timer_ref: nil}}
  clf ->
    # ... normal processing
end
```

### 5. PullSummary Analyzer and Summary Tab

**File:** `lib/we_go_next/analyzers/pull_summary.ex`

New analyzer that aggregates all other analyzer outputs into a between-pull summary:
- Wipe cause determination
- Deaths breakdown (first death, killing blows)
- Critical failures (from tracked mechanics)
- Players needing coaching
- Actionable recommendations

**File:** `lib/we_go_next_web/live/encounter_live/show.ex`

- Added "Summary" tab as default view
- Displays wipe cause banner, deaths summary, critical failures
- Shows "Next Pull Focus" recommendations

## Test Results

All 6 feature tests passing:
```
Finished in 28.2 seconds
6 features, 0 failures
```

## Key Technical Learnings

### Wallaby + SQL Sandbox
Browser tests need special handling for database isolation:
1. Enable `Phoenix.Ecto.SQL.Sandbox` plug in endpoint
2. Pass sandbox metadata from test setup to Wallaby session
3. Use `Ecto.Adapters.SQL.Sandbox.mode(:shared, self())` for non-async tests

### Simulating Live Combat Log Updates
Tests can simulate WoW writing to combat logs:
1. Copy fixture to temp directory
2. Import initial log
3. Append new encounter content with `File.write!(path, content, [:append])`
4. Either click Refresh or wait for FileWatcher auto-detect

### FileWatcher Polling
- Polls every 1 second (`@poll_interval 1000`)
- Detects changes via `CombatLogFile.has_new_content?/1`
- Broadcasts via PubSub when new encounters found
- LiveView subscribes and auto-updates

## Integration Roadmap Status

After this session, the following success criteria are met:

1. ✅ User can select combat log directory in UI
2. ✅ System detects log files
3. ✅ "Watching" indicator shows active monitoring (green pulse)
4. ✅ New encounters appear automatically after file changes
5. ✅ Summary tab shows deaths, damage, recommendations
6. ✅ System stable for multiple pulls

## Commits Created

13 granular commits were created for this work:

1. Add phoenix_ecto dependency for SQL sandbox support
2. Configure SQL sandbox for browser tests
3. Add FeatureCase test helper for Wallaby browser tests
4. Add test fixtures for combat log integration tests
5. Fix timestamp handling in importer
6. Fix FileWatcher crash when watched record is deleted
7. Add PullSummary analyzer and Summary tab
8. Add minimal flow integration test
9. Add live sync integration test
10. Add auto-update integration test
11. Add Integration Roadmap documentation
12. Add session log for integration testing work
13. Update CLAUDE.md and ROADMAP with MVP status

## Next Steps

- Phase 5: Edge Cases & Polish (error handling, performance verification)
- Live gameplay testing with real WoW
- Log rotation handling
