# Session: Documentation Updates and MCP Integration Clarification
**Date:** 2025-11-26
**Focus:** Clarified MCP server role, updated all documentation with correct workflow and launch dates

## Overview

Major documentation update session to clarify the role of the wow_mcp server in the WeGoNext project and update all docs with the confirmed Midnight expansion launch date (March 2, 2026).

## Key Clarification: MCP Server Role

### Initial Confusion
The WOW_MCP_INTEGRATION_ROADMAP.md initially described MCP as being used for runtime data collection (position tracking, cooldown monitoring, etc.) with complex bidirectional workflows during raids.

### Correct Understanding
User clarified the actual intended workflow:
- **MCP is for development only** (deploying addons, testing, debugging)
- **Runtime workflow is simple:** we_go_next writes SavedVariables → you /reload → addon distributes
- **No MCP during raids** - it's just file writes and WoW addon communication

### The Actual Workflow

```
Combat Log File
    ↓
we_go_next (Phoenix app) analyzes encounter
    ↓
Writes WeGoNextResults.lua to WoW SavedVariables directory
    ↓
Server operator (you) runs /reload in WoW
    ↓
WeGoNext addon reads SavedVariables
    ↓
Addon broadcasts via C_ChatInfo.SendAddonMessage("WeGoNext", data, "RAID")
    ↓
Other raid members' addons receive & display personalized results
```

**Similar to Method Raid Tools (MRT):** Raid lead shares, everyone with addon receives.

### What MCP Actually Does (Development)
- Deploy WeGoNext addon to WoW from dev directory
- Read SavedVariables during testing
- Debug addon issues via MCPBridge commands
- Test SavedVariables parsing before implementing in we_go_next

### What MCP Does NOT Do (Runtime)
- ❌ Not used during raids
- ❌ Not required for we_go_next to work
- ❌ Not part of results distribution workflow
- ❌ Players don't need MCP installed

## Documentation Updates

### 1. ROADMAP.md

**Added Phase 6B: Addon-Based Results Distribution (Optional)**

New section documenting the in-game results distribution feature:
- Why an addon? (automated distribution vs manual callouts)
- Workflow diagram
- SavedVariables format
- we_go_next integration (LuaWriter, ResultsGenerator)
- Player UI examples
- MCP usage clarification (development only)

**Updated Milestone Schedule:**
```
| **M1: Core Events**          | ✅ Nov 2025        | Death tracking, damage taken analysis |
| **M2: Discovery Mode**       | ✅ Nov 2026        | Surface interesting events, basic UI |
| **M3: Criteria System**      | Dec 2025 - Jan 2026 | Mark/track mechanics, boss profiles |
| **M4: File Watching**        | ✅ Nov 2026        | Auto-refresh on encounter end |
| **M5: Analysis Reports**     | Feb 2026           | Between-pull summaries, trends |
| **M6: Pre-Launch Polish**    | Early Mar 2026     | Final testing, bug fixes |
| **MVP Launch**               | **Mid-March 2026** | **Ready for Midnight raids Day 1** |
| **Post-MVP: Strategy Diagrams** | Q2-Q3 2026      | Minimap annotations, Discord export |
| **Post-MVP: Addon Distribution** | Q3-Q4 2026     | In-game results sharing |
```

**Updated Timeline Section:**
- Midnight Launch: March 2, 2026 (confirmed)
- Raid Opening: Mid-March 2026 (typically 1-2 weeks after launch)
- Available Time: ~3-4 months until raid opening

### 2. WOW_MCP_INTEGRATION_ROADMAP.md

**Complete rewrite** from scratch with correct focus:

**New Structure:**
- Overview: MCP for development only
- Runtime Workflow (No MCP)
- Development Workflow (MCP Used)
  - Phase 0: Test MCP Server
  - Phase 1: Build WeGoNext Addon
  - Phase 2: we_go_next SavedVariables Writer
- Configuration
- Testing Workflow
- Summary (clear delineation of MCP vs runtime roles)

**Key Sections Added:**

**Runtime Workflow (No MCP):**
- Step-by-step flow from combat log to player display
- Emphasis on simplicity: file write → /reload → addon comm

**Phase 1: Build WeGoNext Addon:**
- Full code examples for Core.lua, ResultsHandler.lua, UI.lua
- SavedVariables format specification
- Slash commands (/wgn share, /wgn show)
- Addon communication via C_ChatInfo.SendAddonMessage

**Phase 2: we_go_next SavedVariables Writer:**
- LuaWriter module (Elixir → Lua table format)
- ResultsGenerator module (personalized stats per player)
- Web UI integration ("Prepare Results for Sharing" button)
- Configuration (WoW install path, account name)

**Implementation Priority:**
- Post-MVP (after Phase 5 in main roadmap)
- Q3-Q4 2026 timeframe
- MVP works fine with manual callouts
- Addon is UX enhancement, not core feature

### 3. CLAUDE.md

**Updated Output Modes Section:**

Changed from "Two Output Modes" to "Three Output Modes":

**Added Mode #2: In-Game Distribution (Optional - Post-MVP)**
- we_go_next writes analysis to WoW SavedVariables
- Raid lead /reload → WeGoNext addon reads results
- Addon broadcasts to all raid members via addon comm
- Each player sees personalized performance breakdown
- No verbal callouts needed (MRT-style sharing)
- **Note:** MCP server used only for addon development, not during raids

**Updated Project Structure:**
- Changed `HANDOFF.md` → `WOW_MCP_INTEGRATION_ROADMAP.md`

**Updated Target Launch Section:**
- Midnight release: March 2, 2026
- Raid opening: Mid-March 2026 (typically 1-2 weeks after expansion launch)
- First raids: The Voidspire (6 bosses), The Dreamrift (1 boss), March of Quel'Danas (2 bosses)
- MVP Goal: Working diagnostic tool ready for Day 1 raid progression

### 4. Deleted HANDOFF.md

Removed outdated handoff document (last updated 2025-11-25, superseded by session logs).

## Launch Date Confirmation

**User provided confirmed launch date:** March 2, 2026

**Implications:**
- Raids open mid-March 2026 (typically 1-2 weeks after expansion launch)
- ~3-4 months from now (Nov 2025) to raid opening
- Shorter timeline than originally planned (was estimated "late Jan - March 2026")
- MVP deadline is **firm**: Mid-March 2026

**Priority adjustments:**
- Criteria system (Phase 3) is next critical feature
- Between-pull reports (Phase 5) needed by Feb 2026
- Polish phase must be complete early March
- Addon distribution pushed to post-MVP (nice to have, not essential)

## Files Modified

### Updated Files
1. `docs/ROADMAP.md`
   - Added Phase 6B: Addon-Based Results Distribution
   - Updated milestone schedule with concrete dates
   - Marked M1, M2, M4 as complete
   - Updated timeline section with March 2, 2026 launch

2. `docs/WOW_MCP_INTEGRATION_ROADMAP.md`
   - Complete rewrite (546 lines)
   - Clear separation of development vs runtime workflows
   - Full code examples for addon and we_go_next integration
   - Positioned as Post-MVP feature

3. `CLAUDE.md`
   - Updated output modes (added in-game distribution)
   - Updated target launch section with confirmed date
   - Updated project structure reference

### Deleted Files
1. `docs/HANDOFF.md` (outdated, superseded by session logs)

## Current Project State

### Completed (Phase 1-2, 4)
- ✅ Combat log parser with 4 analyzers (death, damage, interrupts, debuffs)
- ✅ Phoenix LiveView web UI
- ✅ File watching for auto-refresh (implemented this session earlier)
- ✅ PostgreSQL storage with incremental parsing
- ✅ ETS cache backed by database

### Next Priority (Phase 3)
- ⏳ Criteria System (Dec 2025 - Jan 2026)
  - Mark abilities as "avoidable damage", "must interrupt", "soak mechanic", etc.
  - Track mechanic failures per player
  - Build boss profiles during progression
  - Enable meaningful coaching ("Player X failed mechanic Y")

### Timeline to MVP
- **Phase 3 (Criteria):** Dec 2025 - Jan 2026
- **Phase 5 (Reports):** Feb 2026
- **Phase 6 (Polish):** Early Mar 2026
- **MVP Launch:** Mid-March 2026

### Post-MVP Features
- Strategy diagrams (Q2-Q3 2026)
- Addon distribution (Q3-Q4 2026)

## Technical Notes

### SavedVariables Writer Design

**LuaWriter Module:**
```elixir
defmodule WeGoNext.LuaWriter do
  def write_saved_variables(path, variable_name, data) do
    lua_content = "#{variable_name} = #{to_lua(data)}\n"
    File.write!(path, lua_content)
  end

  defp to_lua(map) when is_map(map) do
    # Convert Elixir map to Lua table
  end
  # ... handle lists, strings, numbers, booleans, nil
end
```

**ResultsGenerator Module:**
```elixir
defmodule WeGoNext.ResultsGenerator do
  def generate_results(encounter) do
    %{
      encounter: %{id: ..., name: ..., pull_number: ...},
      summary: %{result: "WIPE", percent: 43, ...},
      players: %{
        "Mittwoch-WyrmrestAccord" => %{
          deaths: 2,
          causes: ["Diabolic Ritual", ...],
          tips: ["Move faster..."]
        },
        # ... all raid members
      }
    }
  end
end
```

### WoW Addon Architecture

**Core.lua:**
- Initialize on ADDON_LOADED
- Check for WeGoNextResults SavedVariable
- Register addon message prefix "WeGoNext"

**ResultsHandler.lua:**
- ProcessResults() - cache results when found
- ShareResults() - serialize and broadcast via addon comm
- Listen for CHAT_MSG_ADDON events from other players

**UI.lua:**
- DisplayPersonalStats() - show player-specific breakdown
- Slash commands: /wgn share, /wgn show

**Addon Communication:**
```lua
-- Broadcast
C_ChatInfo.SendAddonMessage("WeGoNext", "RESULTS:" .. serialized, "RAID")

-- Listen
frame:RegisterEvent("CHAT_MSG_ADDON")
-- handle prefix == "WeGoNext"
```

### SavedVariables Path

```
/mnt/g/World of Warcraft/_retail_/WTF/Account/{account}/SavedVariables/WeGoNext.lua
```

we_go_next needs configuration:
```elixir
config :we_go_next,
  wow_install_path: "/mnt/g/World of Warcraft/_retail_",
  wow_account: "YourAccount#1"
```

## Key Decisions

### Addon Distribution is Post-MVP

**Rationale:**
- MVP works fine with manual callouts (raid lead reads web UI verbally)
- Criteria system more important for functionality
- Addon is UX enhancement, not core diagnostic feature
- 3-4 months to MVP is tight - focus on essentials

**Implementation Timeline:**
- After criteria system working (Phase 3)
- After between-pull reports (Phase 5)
- After tool tested with real progression
- Q3-Q4 2026 timeframe

### MCP Only for Development

**Rationale:**
- Runtime workflow is simpler without MCP
- No extra dependencies for users
- Direct file write is reliable and fast
- MCP adds value during addon development only

**Use cases:**
- Deploy addon: `mix deploy_we_go_next`
- Test SavedVariables parsing via Claude
- Debug addon issues: `/mcp inspect`, `/mcp dump`
- Read results during testing: "Read WeGoNext SavedVariables"

## Success Metrics

### Documentation Quality
- ✅ Clear separation of development vs runtime workflows
- ✅ Concrete examples for all major components
- ✅ Timeline aligned with confirmed launch date
- ✅ Prioritization clear (MVP vs Post-MVP)

### Clarity Improvements
- ✅ Eliminated confusion about MCP role
- ✅ Simplified runtime workflow
- ✅ Positioned addon as enhancement, not requirement
- ✅ Updated all references to old timelines/dates

### Next Session Readiness
- ✅ Clear priority: Criteria System (Phase 3)
- ✅ MVP scope defined and achievable
- ✅ Post-MVP features documented for future
- ✅ All docs consistent and up-to-date

## Related Sessions

- **2025-11-26_file_watcher_implementation.md** - Earlier this session, implemented Phase 4
- **2025-11-26_project_rename_to_we_go_next.md** - Project renamed from combat_log_parser
- **2025-11-25_phase1_complete.md** - Completed all 4 core analyzers

## Next Steps

**Immediate (Phase 3 - Dec-Jan 2026):**
1. Design criteria data model (database schema)
2. Build criteria builder UI (mark abilities in web UI)
3. Implement failure detection logic
4. Create boss profile save/load

**Near-term (Phase 5 - Feb 2026):**
5. Automatic pull summary generation
6. Player performance reports
7. Progress tracking across pulls

**Pre-Launch (Early Mar 2026):**
8. Testing with current raid content
9. Bug fixes and polish
10. Performance optimization

**Post-MVP (Q3-Q4 2026):**
11. Strategy diagrams with minimap
12. Addon distribution system
13. Advanced coaching features
