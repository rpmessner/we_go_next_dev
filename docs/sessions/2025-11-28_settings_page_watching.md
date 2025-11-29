# Session: Settings Page File Watching UI

**Date:** 2025-11-28
**Goal:** Add file watching controls to Settings page for better UX

---

## Summary

Enhanced the Settings page with comprehensive file watching controls, including:
- Watch status indicator with animated pulse
- "Watch Most Recent Log" quick action button
- Dropdown to select specific log file
- Stop watching button
- PubSub integration for real-time new encounter notifications

## Changes Made

### `lib/we_go_next_web/live/settings_live.ex`

**Added:**
- PubSub subscription for `"encounters"` topic on connect
- `watching_file` assign to track current watching state
- `selected_log` assign for dropdown selection
- `importing` assign for loading state

**New Event Handlers:**
- `select_log` - handles dropdown selection
- `watch_log` - imports and starts watching selected file
- `watch_most_recent` - one-click action to watch newest log
- `stop_watching` - stops the file watcher

**New Async Handlers:**
- `import_and_watch` - handles async import/watch operation

**New PubSub Handler:**
- `handle_info({:encounters_loaded, count})` - shows flash on new encounters

**UI Additions:**
- Green status banner when actively watching (with animated pulse indicator)
- "Watch Most Recent Log" prominent button
- File selector dropdown with "Import & Watch Selected" button
- "Currently Watching" row in configuration summary

### `test/we_go_next_test.exs`

Removed placeholder `hello/0` test that was failing (Phoenix boilerplate).

## Test Results

All 6 feature tests pass:
- Log file selection enables import button
- Auto-updates work when file changes
- Multiple syncs work correctly
- End-to-end flow works

## UI Flow

1. User navigates to Settings (`/settings`)
2. Logs folder is auto-configured to `/mnt/g/World of Warcraft/_retail_/Logs`
3. If log files exist, "Start Watching" section appears
4. User clicks "Watch Most Recent Log" (or selects specific file)
5. Import runs, then file watcher starts
6. Green "Watching for new encounters" banner appears
7. When WoW writes new encounters, flash notification shows "X new encounter(s) detected!"
8. User can click "Stop Watching" to disable

## Technical Notes

- File watching uses `WeGoNext.FileWatcher` GenServer (polls every 1s)
- Imports are handled via `WeGoNext.EncounterStore.import_log/2`
- PubSub broadcasts happen on `:encounters_loaded` from EncounterStore
- The watching file is a `%CombatLogFile{}` Ecto struct

## Next Steps

The Settings page now has full watching capability. The Index page already had similar functionality but the Settings page provides a cleaner dedicated interface for configuration.

Remaining integration work:
- Test with live WoW gameplay (pull a boss, verify encounter appears)
- ~~Add log rotation handling (detect when WoW creates new log file)~~ **DONE** - See below
- Consider adding sound notification option

---

## Log Rotation Feature (Added Same Session)

### Implementation

Added automatic log rotation detection to the FileWatcher:

1. **FileWatcher now tracks:**
   - `logs_dir` - The directory containing combat logs
   - `user_id` - For importing new logs

2. **On each poll interval:**
   - Check if a newer log file exists in the directory
   - If found, automatically import it and switch to watching it
   - Broadcast `{:log_rotated, new_clf, count}` via PubSub

3. **UI Updates:**
   - Both Index and Settings LiveViews handle `:log_rotated` events
   - Flash notification shows "Log rotation detected! Switched to X (Y encounters)"

### Files Changed

- `lib/we_go_next/file_watcher.ex` - Added rotation detection logic
- `lib/we_go_next/accounts.ex` - Fixed NaiveDateTime sorting bug
- `lib/we_go_next_web/live/encounter_live/index.ex` - Handle rotation events
- `lib/we_go_next_web/live/settings_live.ex` - Handle rotation events
- `test/features/log_rotation_test.exs` - New test file

### Test Results

All 8 feature tests pass:
- 4 existing tests (minimal flow, encounter list, auto-update x2)
- 2 new log rotation tests

### How It Works

When WoW creates a new log file (after /reload or new session):
1. FileWatcher detects the new file is more recent than current
2. Imports the new file automatically
3. Switches watching to the new file
4. Broadcasts rotation event
5. UI shows flash notification and updates state
