# Integration Roadmap: End-to-End Combat Log Flow

> **Completed.** All four sprints below shipped in Nov–Dec 2025. The end-to-end flow (settings → log selection → file watch → PubSub-driven LiveView updates → Pull Summary on encounter end) is live and dogfooded. Kept for historical reference; tracking now happens in [ROADMAP.md](ROADMAP.md). Note that "ETS-backed encounter store" referenced below was later replaced by the Postgres encounter table in the April 2026 Zig parser rewrite — see [`../2026-04-09_zig_parser_rewrite.md`](../2026-04-09_zig_parser_rewrite.md).

**Goal:** Verify the complete flow from WoW combat → automatic analysis → dashboard display

**Target:** Working demo with trash mob pulls in current content

---

## Current State (as of Nov 28, 2025)

We have all the core pieces built:
- ✅ Combat log parser (reads WoW log files)
- ✅ Encounter detection (ENCOUNTER_START/END boundaries)
- ✅ Death analyzer, damage analyzer, interrupt analyzer, debuff analyzer
- ✅ Failure analyzer with criteria system
- ✅ Pull Summary report generation
- ✅ Phoenix LiveView dashboard with Summary tab
- ✅ File watcher (polls for changes)
- ✅ ETS-backed encounter store *(later replaced by Postgres; see April 2026 rewrite)*

**What's missing:** The pieces aren't fully wired together for the live workflow.

---

## Target Demo Flow

```
1. User opens web UI at localhost:4000
2. User selects/configures combat log directory
3. System finds most recent WoWCombatLog-*.txt file
4. System starts watching that file for changes
5. User plays WoW - pulls mobs, kills them, exits combat
6. WoW writes ENCOUNTER_END (or combat events stop)
7. System detects new content in log file
8. System parses new encounter(s)
9. Dashboard auto-updates with new encounter
10. User sees Pull Summary with damage/deaths/etc
```

---

## Phase 1: Settings & Log Selection

**Goal:** User can configure their combat log directory

### 1.1: Settings Page Updates

**File:** `lib/we_go_next_web/live/settings_live.ex`

Current state: Basic settings page exists but may not persist log path.

**Tasks:**
- [ ] Add "Combat Log Directory" field
- [ ] Default to `/mnt/g/World of Warcraft/_retail_/Logs/`
- [ ] Validate directory exists and contains WoWCombatLog files
- [ ] Save to user record (or application config)
- [ ] Show list of available log files in directory
- [ ] Allow selecting specific log file OR "use most recent"

**UI mockup:**
```
╔══════════════════════════════════════════════════════════════╗
║  Combat Log Settings                                          ║
╠══════════════════════════════════════════════════════════════╣
║  Log Directory: [/mnt/g/World of Warcraft/_retail_/Logs/]    ║
║                                                 [Browse]      ║
║                                                               ║
║  Available Logs:                                              ║
║  ○ Use most recent (recommended)                              ║
║  ○ WoWCombatLog-112225_112043.txt (603 MB, Nov 22)           ║
║  ○ WoWCombatLog-112125_193022.txt (412 MB, Nov 21)           ║
║                                                               ║
║  Status: ● Watching WoWCombatLog-112225_112043.txt           ║
║                                              [Start Watching] ║
╚══════════════════════════════════════════════════════════════╝
```

### 1.2: Log File Discovery

**File:** `lib/we_go_next/log_discovery.ex` (new)

**Tasks:**
- [ ] `list_logs(directory)` - returns all WoWCombatLog-*.txt files
- [ ] `most_recent_log(directory)` - returns newest by filename timestamp
- [ ] `parse_log_filename(filename)` - extracts date/time from name
- [ ] Handle case where no logs exist yet

**Example:**
```elixir
LogDiscovery.list_logs("/mnt/g/.../Logs/")
# => [
#   %{path: "...", filename: "WoWCombatLog-112225_112043.txt",
#     date: ~D[2025-11-22], size: 603_216_599},
#   ...
# ]
```

---

## Phase 2: File Watching Improvements

**Goal:** Robust file watching that handles WoW's logging behavior

### 2.1: Current File Watcher Audit

**File:** `lib/we_go_next/file_watcher.ex`

**Tasks:**
- [ ] Review current implementation
- [ ] Verify it polls file for size changes
- [ ] Verify it tracks read position (byte offset)
- [ ] Verify it handles file rotation (new log file created)
- [ ] Add "watching" status that UI can query

### 2.2: Combat Session Detection

WoW only writes ENCOUNTER_START/END for boss encounters. For trash/dungeon pulls, we need different detection.

**Options:**
1. **ENCOUNTER events only** - Works for raid bosses, not trash
2. **Combat state detection** - Look for gaps in combat events (>5 sec = combat ended)
3. **Zone change detection** - ZONE_CHANGED events
4. **Manual refresh** - User clicks "Refresh" button

**Recommended approach for MVP:**
- Focus on ENCOUNTER events (raid boss pulls)
- Add "Refresh Now" button for manual sync
- Future: Add combat gap detection for M+ trash

**Tasks:**
- [ ] Confirm ENCOUNTER_START/END detection works
- [ ] Add manual "Sync Now" button to UI
- [ ] (Future) Add combat gap detection for non-boss encounters

### 2.3: Live Dashboard Updates

**File:** `lib/we_go_next_web/live/encounter_live/index.ex`

**Tasks:**
- [ ] Subscribe to file watcher events via PubSub
- [ ] When new encounter detected, push update to LiveView
- [ ] Show "New encounter detected!" notification
- [ ] Auto-navigate to new encounter OR highlight in list
- [ ] Show "Watching..." indicator with file path

---

## Phase 3: Real-Time Dashboard Flow

**Goal:** Encounters appear in dashboard immediately after combat ends

### 3.1: PubSub Integration

**Tasks:**
- [ ] FileWatcher broadcasts on new encounter: `Phoenix.PubSub.broadcast(...)`
- [ ] EncounterLive.Index subscribes on mount
- [ ] Handle `handle_info({:new_encounter, encounter_id}, socket)`
- [ ] Prepend new encounter to list

### 3.2: Encounter List Improvements

**File:** `lib/we_go_next_web/live/encounter_live/index.ex`

**Tasks:**
- [ ] Show "most recent" encounter at top
- [ ] Highlight new encounters (animation/badge)
- [ ] Show encounter type (Boss/Trash/Dungeon)
- [ ] Quick stats preview (deaths, duration)

**UI mockup:**
```
╔══════════════════════════════════════════════════════════════╗
║  Encounters                      ● Watching: WoWCombatLog... ║
╠══════════════════════════════════════════════════════════════╣
║  🆕 Plexus Sentinel (Heroic)     KILL   3:50   6 deaths     ║
║     Just now                                                  ║
╠══════════════════════════════════════════════════════════════╣
║     Soulbinder Naazindhri        WIPE   2:44   17 deaths    ║
║     5 minutes ago                                             ║
╠══════════════════════════════════════════════════════════════╣
║     Loom'ithar                   WIPE   0:04   0 deaths     ║
║     8 minutes ago                                             ║
╚══════════════════════════════════════════════════════════════╝
```

### 3.3: Auto-Navigate to Latest

**Tasks:**
- [ ] Option: Auto-navigate to new encounter when detected
- [ ] Option: Stay on current view, show notification badge
- [ ] User preference in settings

---

## Phase 4: Demo Verification

**Goal:** Complete end-to-end test with real gameplay

### 4.1: Test Scenario: Raid Boss Pull

**Steps:**
1. Start Phoenix server: `mix phx.server`
2. Open http://localhost:4000
3. Verify log directory is configured
4. Verify "Watching" status shows active file
5. In WoW: Enter raid instance (e.g., Manaforge Omega)
6. Pull a boss
7. Complete encounter (kill or wipe)
8. **Verify:** New encounter appears in dashboard within seconds
9. Click encounter → verify Summary tab shows correct data

**Verification checklist:**
- [ ] Encounter name correct
- [ ] Duration correct
- [ ] Kill/Wipe status correct
- [ ] Deaths listed with causes
- [ ] Damage sources shown
- [ ] Interrupts counted
- [ ] Summary recommendations present

### 4.2: Test Scenario: Multiple Pulls

**Steps:**
1. Pull boss, wipe
2. Verify encounter 1 appears
3. Pull boss again, wipe
4. Verify encounter 2 appears
5. Pull boss, kill
6. Verify encounter 3 appears with "KILL" status

### 4.3: Test Scenario: Log Rotation

WoW creates a new log file when you reload UI or start a new session.

**Steps:**
1. Start watching current log
2. /reload in WoW (creates new log file)
3. Verify system detects new log file
4. Verify watching switches to new file (or prompts user)

---

## Phase 5: Edge Cases & Polish

### 5.1: Error Handling

**Tasks:**
- [ ] Handle: Log directory doesn't exist
- [ ] Handle: No log files in directory
- [ ] Handle: Log file deleted while watching
- [ ] Handle: Permission denied reading log
- [ ] Handle: Malformed log content

### 5.2: Performance

**Tasks:**
- [ ] Verify watching doesn't consume excessive CPU
- [ ] Verify large log files (600MB+) parse efficiently
- [ ] Verify memory usage stays reasonable during long sessions

### 5.3: User Feedback

**Tasks:**
- [ ] Show parse progress for large initial imports
- [ ] Show "Last updated: X seconds ago"
- [ ] Show byte position / file percentage
- [ ] Sound notification option when new encounter ready

---

## Implementation Order

### Sprint 1: Log Selection (1-2 hours)
1. Create LogDiscovery module
2. Update Settings page with directory picker
3. Show available log files
4. Persist selection

### Sprint 2: Watch Integration (2-3 hours)
1. Audit FileWatcher, fix any issues
2. Add PubSub broadcasts for new encounters
3. Subscribe in EncounterLive.Index
4. Show "Watching" status in UI

### Sprint 3: Live Updates (1-2 hours)
1. Push new encounters to LiveView
2. Add "New!" badge/highlight
3. Add "Sync Now" manual button
4. Test with real WoW gameplay

### Sprint 4: Polish & Edge Cases (1-2 hours)
1. Error handling
2. Log rotation handling
3. Performance verification
4. Final demo walkthrough

**Total estimated time:** 5-9 hours

---

## Quick Start for Testing

Once implemented, the demo flow is:

```bash
# Terminal 1: Start the server
cd we_go_next
mix phx.server

# Terminal 2: (optional) Watch the log file
tail -f "/mnt/g/World of Warcraft/_retail_/Logs/WoWCombatLog-*.txt"
```

1. Open http://localhost:4000
2. Go to Settings → verify log path
3. Start WoW
4. Enable combat logging: `/combatlog`
5. Enter a raid/dungeon
6. Pull a boss
7. Kill/wipe
8. Watch dashboard update!

---

## Notes

### WoW Combat Logging Behavior

- `/combatlog` toggles logging on/off
- Log file: `WoWCombatLog-MMDDYY_HHMMSS.txt`
- New file created on: game launch, /reload, or explicit toggle
- **Buffering:** WoW buffers writes during active combat
- **Flush:** Log flushes immediately on ENCOUNTER_END
- **Trash pulls:** No ENCOUNTER events, just raw combat events

### Non-Boss Encounters (Future)

For M+ and trash pulls without ENCOUNTER_START/END:
- Detect combat start: First damage event after >X seconds gap
- Detect combat end: No damage events for >5 seconds
- Group events into "combat sessions"
- Lower priority than boss encounters for MVP

---

## Success Criteria

**Demo is successful when:**
1. ✅ User can select combat log directory in UI
2. ✅ System auto-detects most recent log file
3. ✅ "Watching" indicator shows active monitoring
4. ✅ After boss kill/wipe, new encounter appears in <5 seconds
5. ✅ Click encounter → Summary shows deaths, damage, recommendations
6. ✅ System remains stable for multiple pulls in a row

This validates the core between-pull analysis workflow.
