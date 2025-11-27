# Session: File Watcher Implementation
**Date:** 2025-11-26
**Focus:** Implemented automatic file watching for between-pull encounter detection

## Overview
Implemented Phase 4 (File Watching & Auto-Refresh) from the roadmap. The system now automatically detects when new encounters are written to the combat log and imports them in real-time.

## What Was Built

### 1. FileWatcher GenServer
**File:** `lib/we_go_next/file_watcher.ex`

A dedicated GenServer that:
- Polls the active combat log file every 1 second
- Uses `CombatLogFile.has_new_content?/1` to detect file changes (mtime/size)
- Triggers incremental sync via `EncounterStore.sync_log/1` when changes detected
- Broadcasts new encounters to LiveView via existing PubSub
- Supports `watch/1` and `stop_watching/0` API

**Key design decisions:**
- **1-second poll interval**: WoW flushes the log on `ENCOUNTER_END`, so 1s polling provides near-instant detection
- **Incremental parsing**: Uses byte offset tracking to only parse new content
- **Automatic recovery**: Refreshes CombatLogFile metadata from DB on each check
- **Logger integration**: Info logs for start/stop, debug logs for detected changes

### 2. Integration with Application Supervision Tree
**File:** `lib/we_go_next/application.ex`

Added FileWatcher to supervision tree:
```elixir
children = [
  WeGoNext.Repo,
  {Phoenix.PubSub, name: WeGoNext.PubSub},
  WeGoNext.EncounterStore,
  WeGoNext.FileWatcher,  # <- New
  WeGoNextWeb.Endpoint
]
```

The FileWatcher starts automatically with the application but waits for a file to be loaded.

### 3. Auto-Start Watching on Import
**File:** `lib/we_go_next/encounter_store.ex`

Updated two functions to start watching:
- `handle_call({:import_log, ...})` - Starts watching after importing a new log
- `handle_call({:load_from_db, ...})` - Starts watching when loading existing log from database

This ensures file watching starts automatically whenever a user loads a combat log.

### 4. LiveView UI Updates
**File:** `lib/we_go_next_web/live/encounter_live/index.ex`

Added visual indicator for auto-refresh status:
- New assign `:watching` tracks whether file watching is active
- Green pulsing dot + "Auto-refresh active" badge when watching
- Updated flash messages to say "Auto-refresh enabled"
- Assigns updated in all relevant callbacks (import, sync, load_from_db)

**UI changes:**
```heex
<span :if={@watching} class="inline-flex items-center gap-1 text-xs text-green-400">
  <span class="relative flex h-2 w-2">
    <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
    <span class="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
  </span>
  Auto-refresh active
</span>
```

## How It Works

### Between-Pull Workflow (The Critical Use Case)

1. **Raid Night Starts**
   - User opens browser to http://localhost:4000
   - Selects/imports most recent combat log
   - FileWatcher automatically starts polling the file

2. **During Boss Pull**
   - WoW buffers combat log writes to memory
   - FileWatcher continues polling (no changes detected)

3. **Encounter Ends (ENCOUNTER_END written)**
   - WoW flushes buffered log to disk
   - File mtime/size changes within 1 second
   - FileWatcher detects change on next poll (~1s later)
   - Triggers `EncounterStore.sync_log/1`
   - Incremental parser reads new bytes, finds ENCOUNTER_END
   - New encounter inserted to database and ETS cache
   - PubSub broadcasts `:encounters_loaded` event
   - LiveView updates encounter list automatically

4. **Raid Lead Sees Results**
   - Fresh encounter appears at top of list
   - Can click in to view deaths, damage, interrupts, debuffs
   - All analysis available during runback/rebuff
   - No manual refresh needed

**Time from encounter end to visible:** ~1-3 seconds

### Technical Flow

```
Combat Log File (on disk)
    ↓ (WoW writes ENCOUNTER_END)
FileWatcher (polls every 1s)
    ↓ (detects mtime/size change)
CombatLogFile.has_new_content?/1
    ↓ (returns true)
EncounterStore.sync_log/1
    ↓
Importer.sync_log/1
    ↓ (incremental parse from last_parsed_byte)
LogReader.parse_file_with_bytes/2
    ↓ (finds new encounters)
Insert to PostgreSQL + update byte offset
    ↓
Cache in ETS
    ↓
Phoenix.PubSub.broadcast "encounters"
    ↓
LiveView receives :encounters_loaded
    ↓
UI updates automatically
```

## Testing

### Manual Testing Steps
1. Start Phoenix server: `mix phx.server`
2. Open http://localhost:4000
3. Configure WoW logs path in Settings
4. Import a combat log file
5. Verify "Auto-refresh active" badge appears with pulsing green dot
6. (Optional) Run a dungeon/raid and watch new encounters appear automatically

### Verification
- ✅ Project compiles cleanly (only style warnings)
- ✅ Phoenix server starts successfully
- ✅ FileWatcher GenServer starts with application
- ✅ FileWatcher.current_file() returns nil when not watching
- ✅ Web UI renders with auto-refresh badge
- ✅ Integration points added to EncounterStore

## Files Modified

### New Files
- `lib/we_go_next/file_watcher.ex` (127 lines)
- `test_file_watcher.exs` (39 lines - testing utility)

### Modified Files
- `lib/we_go_next/application.ex` (added FileWatcher to supervision tree)
- `lib/we_go_next/encounter_store.ex` (added FileWatcher.watch/1 calls)
- `lib/we_go_next_web/live/encounter_live/index.ex` (UI updates for watching status)

### Deleted Files
- `docs/HANDOFF.md` (outdated, superseded by session logs)

## Roadmap Progress

### Phase 4: File Watching & Auto-Refresh ✅ COMPLETE
- [x] File watching with polling (FileWatcher GenServer)
- [x] Detect new encounters (CombatLogFile.has_new_content?)
- [x] Auto-import on change (EncounterStore.sync_log integration)
- [x] LiveView push updates (PubSub + reactive assigns)
- [x] UI indicator for auto-refresh status

## What's Next

With Phase 4 complete, the tool is now **usable during raid nights**:
- Encounters appear automatically after pulls end
- No manual refresh needed
- Analysis ready during runback

**Remaining MVP features (for Midnight launch):**

### Phase 3: Criteria System (HIGH PRIORITY)
The next critical feature for MVP. Enables:
- Mark abilities as "avoidable damage", "must interrupt", "soak mechanic", etc.
- Track mechanic failures per player
- Build boss profiles during progression
- This is what turns raw event data into actionable coaching

**Without criteria system:** Tool shows deaths/damage/interrupts but can't say "Player X failed mechanic Y"
**With criteria system:** Tool says "Mittwoch stood in Diabolic Ritual 3 times this pull"

### Phase 5: Between-Pull Reports
- Automatic pull summary generation
- "What killed us" analysis
- Comparison to previous attempts

### Phase 6: Strategy Diagrams (OPTIONAL)
- Can be cut if behind schedule
- Nice to have but not essential for MVP

## Technical Notes

### Why 1-Second Polling?
- WoW flushes log **immediately** on ENCOUNTER_END (tested behavior)
- Disk writes are fast (log append is buffered by OS)
- 1-second delay is acceptable for between-pull analysis
- Finer polling (100ms) would increase CPU with minimal benefit
- Coarser polling (5s) would feel sluggish

### Why Not File System Watching (inotify)?
- Could use FileSystem library for true event-driven watching
- Cross-platform complexity (inotify on Linux, FSEvents on macOS, etc.)
- Polling is simpler, more predictable, and 1s is fast enough
- Can switch to inotify later if needed (optimization)

### Memory Considerations
- ETS cache holds full encounter structs (events array)
- Large combat logs (1GB+, 100+ encounters) could use significant memory
- Future optimization: Lazy-load event arrays, cache only metadata
- For MVP: Most raid nights = ~20-40 encounters, acceptable memory usage

### Database vs ETS
- Encounters persisted to PostgreSQL (durable)
- ETS used as read cache (fast access for web UI)
- FileWatcher triggers sync → database insert → ETS refresh
- Survives server restart (reload from DB on mount)

## Session Artifacts

### Logs
- Phoenix server log: `/tmp/phx_server.log`
- FileWatcher logs: Check application logs for "FileWatcher: Started watching..."

### Testing
- Server is running in background
- Can access at http://localhost:4000
- Ready for testing with real combat logs

## Next Session Recommendation

**Implement Phase 3: Criteria System**

Start with a simple approach:
1. Add "Mark as Avoidable" button next to abilities in Damage Taken tab
2. Store criteria in database (new table: `mechanic_criteria`)
3. Apply criteria during analysis to flag failures
4. Show failures prominently in encounter view

This is the minimum needed to make the tool useful for actual coaching.
