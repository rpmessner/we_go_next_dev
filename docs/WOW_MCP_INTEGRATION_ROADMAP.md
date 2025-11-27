# WoW MCP Integration for WeGoNext Development

**Date:** 2025-11-26
**Purpose:** Document MCP server usage for WeGoNext addon development

---

## Overview

The `wow_mcp` MCP server is used **during addon development only**. It is NOT part of the runtime workflow for raid diagnostics.

### What MCP Does (Development)

- **Deploy addon** to WoW from development directory
- **Read SavedVariables** during testing
- **Debug addon issues** via MCPBridge commands
- **Test SavedVariables parsing** before implementing in we_go_next

### What MCP Does NOT Do (Runtime)

- ❌ Not used during raids
- ❌ Not required for we_go_next to work
- ❌ Not part of results distribution workflow
- ❌ Players don't need MCP installed

---

## Runtime Workflow (No MCP)

### How Results Get to Raid Members

```
1. Combat Log File
       ↓
2. we_go_next (Phoenix app) analyzes encounter
       ↓
3. we_go_next writes WeGoNextResults.lua to WoW SavedVariables directory
       ↓
4. Server operator (you) runs /reload in WoW
       ↓
5. Your WeGoNext addon reads SavedVariables
       ↓
6. Your addon broadcasts via C_ChatInfo.SendAddonMessage("WeGoNext", data, "RAID")
       ↓
7. Other raid members' WeGoNext addons receive broadcast
       ↓
8. Each player sees their personalized performance breakdown
```

**Key Point:** MCP is not involved at all during raids. It's just:
- we_go_next → writes file → you /reload → addon distributes

---

## Development Workflow (MCP Used)

### Phase 0: Test MCP Server (One-Time Setup)

**Goal:** Verify wow_mcp works before building WeGoNext addon

**Tasks:**

1. **Deploy MCPBridge addon** (for development/debugging):
   ```bash
   cd ~/dev/games/wow-addons/wow_mcp
   WOW_FOLDER="/mnt/g/World of Warcraft" mix deploy_bridge --version retail
   ```

2. **Add MCP server to Claude Code** (`.mcp.json`):
   ```json
   {
     "mcpServers": {
       "wow": {
         "command": "mix",
         "args": ["run", "--no-halt"],
         "cwd": "/home/rpmessner/dev/games/wow-addons/wow_mcp"
       }
     }
   }
   ```

3. **Test MCP tools via Claude:**
   - "Check wow errors"
   - "List wow addons"
   - "Read WeGoNext SavedVariables" (once addon exists)

4. **Test MCPBridge in-game:**
   - `/mcp status`
   - `/mcp ping`
   - `/reload`
   - Verify results appear

**Success:** Can use MCP tools to inspect WoW state during addon development

---

### Phase 1: Build WeGoNext Addon

**Goal:** Create addon that reads results and broadcasts to raid

**Use MCP for:**
- Deploying addon: `mix deploy_bridge` or similar task
- Testing SavedVariables format
- Debugging addon issues

#### 1.1: Addon Structure

```
~/dev/games/wow-addons/WeGoNext/
├── WeGoNext.toc
├── Core.lua           # Addon initialization
├── ResultsHandler.lua # Read SavedVariables, broadcast
├── UI.lua            # Display results to players
└── Utils.lua         # Helper functions
```

#### 1.2: Core.lua

```lua
local ADDON_NAME = "WeGoNext"
local WGN = {}
_G.WeGoNext = WGN

WGN.version = "0.1.0"

-- Initialize on load
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == ADDON_NAME then
        WGN:OnLoad()
    end
end)

function WGN:OnLoad()
    print("|cFF00CCFF[WeGoNext]|r Loaded v" .. self.version)

    -- Check for results to broadcast
    if WeGoNextResults then
        self:ProcessResults()
    end

    -- Register for addon messages from other players
    C_ChatInfo.RegisterAddonMessagePrefix("WeGoNext")
end
```

#### 1.3: ResultsHandler.lua

```lua
local WGN = WeGoNext

function WGN:ProcessResults()
    if not WeGoNextResults or not WeGoNextResults.encounter then
        return
    end

    local results = WeGoNextResults

    print("|cFF00CCFF[WeGoNext]|r Found results for " .. results.encounter.name)
    print("|cFF00CCFF[WeGoNext]|r Use /wgn share to broadcast to raid")

    -- Cache for later sharing
    self.cachedResults = results
end

function WGN:ShareResults()
    if not self.cachedResults then
        print("|cFFFF0000[WeGoNext]|r No results to share. Run /reload after encounter.")
        return
    end

    local serialized = self:SerializeResults(self.cachedResults)
    C_ChatInfo.SendAddonMessage("WeGoNext", "RESULTS:" .. serialized, "RAID")

    print("|cFF00CCFF[WeGoNext]|r Results shared with raid!")

    -- Clear SavedVariable so it doesn't re-process
    WeGoNextResults = nil
end

-- Listen for broadcasts from other players
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if prefix ~= "WeGoNext" then return end

    if message:match("^RESULTS:") then
        local data = message:gsub("^RESULTS:", "")
        local results = WGN:DeserializeResults(data)
        WGN:DisplayPersonalStats(results)
    end
end)
```

#### 1.4: UI.lua

```lua
local WGN = WeGoNext

function WGN:DisplayPersonalStats(results)
    local playerName = UnitName("player") .. "-" .. GetRealmName()
    local myStats = results.players[playerName]

    if not myStats then
        print("|cFF00CCFF[WeGoNext]|r No data for you in these results.")
        return
    end

    -- Simple chat output
    print(" ")
    print("|cFF00CCFF===== WeGoNext Analysis =====|r")
    print("Encounter: " .. results.encounter.name)
    print("Result: " .. results.summary.result)
    print(" ")
    print("Your Performance:")
    print("  Deaths: " .. (myStats.deaths or 0))

    if myStats.tips and #myStats.tips > 0 then
        print(" ")
        print("Tips:")
        for _, tip in ipairs(myStats.tips) do
            print("  • " .. tip)
        end
    end
    print("|cFF00CCFF================================|r")
    print(" ")

    -- TODO: Custom frame UI for detailed breakdown
end

-- Slash commands
SLASH_WGN1 = "/wgn"
SlashCmdList["WGN"] = function(msg)
    if msg == "share" then
        WGN:ShareResults()
    elseif msg == "show" or msg == "me" then
        if WGN.lastResults then
            WGN:DisplayPersonalStats(WGN.lastResults)
        else
            print("|cFFFF0000[WeGoNext]|r No results available.")
        end
    else
        print("|cFF00CCFF[WeGoNext]|r Commands:")
        print("  /wgn share - Share results with raid")
        print("  /wgn show  - Show your last results")
    end
end
```

#### 1.5: Deploy with MCP

**Create mix task (in wow_mcp):**

```elixir
# lib/mix/tasks/deploy_we_go_next.ex
defmodule Mix.Tasks.DeployWeGoNext do
  use Mix.Task

  def run(_) do
    source = Path.expand("~/dev/games/wow-addons/WeGoNext")
    dest = WowMcp.Paths.addons_path() <> "/WeGoNext"

    File.rm_rf!(dest)
    File.cp_r!(source, dest)

    IO.puts("✓ Deployed WeGoNext addon")
  end
end
```

**Deploy:**
```bash
cd ~/dev/games/wow-addons/wow_mcp
mix deploy_we_go_next
```

Or ask Claude: "Deploy WeGoNext addon"

---

### Phase 2: we_go_next SavedVariables Writer

**Goal:** Make we_go_next write results to SavedVariables file

**No MCP involved** - just direct file writing from Phoenix app.

#### 2.1: Add Lua Writer Module

```elixir
# lib/we_go_next/lua_writer.ex
defmodule WeGoNext.LuaWriter do
  @moduledoc """
  Writes Elixir data structures to Lua SavedVariables format.
  """

  def write_saved_variables(path, variable_name, data) do
    lua_content = "#{variable_name} = #{to_lua(data)}\n"
    File.write!(path, lua_content)
  end

  defp to_lua(map) when is_map(map) do
    pairs =
      map
      |> Enum.map(fn {k, v} ->
        "[#{to_lua_key(k)}] = #{to_lua(v)}"
      end)
      |> Enum.join(",\n  ")

    "{\n  #{pairs}\n}"
  end

  defp to_lua(list) when is_list(list) do
    items = Enum.map_join(list, ", ", &to_lua/1)
    "{#{items}}"
  end

  defp to_lua(str) when is_binary(str) do
    ~s("#{String.replace(str, "\"", "\\\"")}")
  end

  defp to_lua(num) when is_number(num), do: to_string(num)
  defp to_lua(true), do: "true"
  defp to_lua(false), do: "false"
  defp to_lua(nil), do: "nil"

  defp to_lua_key(key) when is_binary(key), do: ~s("#{key}")
  defp to_lua_key(key) when is_atom(key), do: ~s("#{key}")
end
```

#### 2.2: Results Generator

```elixir
# lib/we_go_next/results_generator.ex
defmodule WeGoNext.ResultsGenerator do
  @moduledoc """
  Generates personalized results for raid members.
  """

  alias WeGoNext.Analyzers.{DeathAnalyzer, DamageTakenAnalyzer, InterruptAnalyzer}

  def generate_results(encounter) do
    %{
      encounter: %{
        id: encounter.encounter_id,
        name: encounter.name,
        pull_number: encounter.pull_number || 1,
        timestamp: DateTime.to_unix(encounter.start_time)
      },
      summary: generate_summary(encounter),
      players: generate_player_stats(encounter)
    }
  end

  defp generate_summary(encounter) do
    %{
      result: if(encounter.success, do: "KILL", else: "WIPE"),
      percent: calculate_boss_percent(encounter),
      duration: div(encounter.fight_time_ms, 1000),
      total_deaths: length(DeathAnalyzer.analyze(encounter))
    }
  end

  defp generate_player_stats(encounter) do
    deaths = DeathAnalyzer.analyze(encounter)
    damage = DamageTakenAnalyzer.analyze(encounter)
    interrupts = InterruptAnalyzer.analyze(encounter)

    # Get all players
    players = get_all_players(encounter)

    players
    |> Enum.map(fn player ->
      {player, %{
        deaths: count_player_deaths(deaths, player),
        causes: get_death_causes(deaths, player),
        avoidable_damage: get_avoidable_damage(damage, player),
        interrupts: get_interrupt_stats(interrupts, player),
        tips: generate_tips(encounter, player)
      }}
    end)
    |> Map.new()
  end

  defp generate_tips(encounter, player) do
    # TODO: Intelligent tip generation based on failures
    []
  end
end
```

#### 2.3: Web UI Integration

```elixir
# lib/we_go_next_web/live/encounter_live/show.ex

def handle_event("prepare_results", _params, socket) do
  encounter = socket.assigns.encounter

  # Generate results
  results = ResultsGenerator.generate_results(encounter)

  # Write to SavedVariables
  wow_path = Application.get_env(:we_go_next, :wow_install_path)
  account = Application.get_env(:we_go_next, :wow_account)

  sv_path = Path.join([
    wow_path,
    "WTF/Account",
    account,
    "SavedVariables",
    "WeGoNext.lua"
  ])

  LuaWriter.write_saved_variables(sv_path, "WeGoNextResults", results)

  {:noreply,
   socket
   |> put_flash(:info, "Results ready! Run /reload in WoW, then /wgn share")}
end
```

**Add button to template:**
```heex
<button
  phx-click="prepare_results"
  class="px-4 py-2 bg-wow-gold text-zinc-900 font-semibold rounded"
>
  Prepare Results for Sharing
</button>
```

---

## Configuration

### we_go_next config

```elixir
# config/config.exs
config :we_go_next,
  wow_install_path: "/mnt/g/World of Warcraft/_retail_",
  wow_account: "YourAccount#1"
```

### SavedVariables Path

```
/mnt/g/World of Warcraft/_retail_/WTF/Account/YourAccount#1/SavedVariables/WeGoNext.lua
```

---

## Testing Workflow

### End-to-End Test

1. **Run a dungeon/raid boss**
2. **Open we_go_next:** `http://localhost:4000`
3. **View encounter analysis**
4. **Click "Prepare Results for Sharing"**
5. **Check SavedVariables file written:**
   ```bash
   cat "/mnt/g/World of Warcraft/_retail_/WTF/Account/YourAccount#1/SavedVariables/WeGoNext.lua"
   ```
6. **/reload in WoW**
7. **Verify addon output:** Should see "Found results for..."
8. **/wgn share**
9. **Check other raid members see results** (if they have addon)

### MCP Testing (Development)

Use MCP to inspect SavedVariables during development:

Ask Claude:
- "Read WeGoNext SavedVariables"
- "What's in the results for Mittwoch?"
- "Show me the summary section"

---

## Summary

### MCP Role: Development Only

- ✅ Deploy addon during development
- ✅ Test SavedVariables parsing
- ✅ Debug addon issues via MCPBridge
- ✅ Inspect WoW state via Claude Code

### Runtime: No MCP

- ✅ we_go_next writes SavedVariables directly
- ✅ You /reload in WoW
- ✅ Addon broadcasts to raid
- ✅ Players see personalized stats

### Files Modified in we_go_next

**New:**
- `lib/we_go_next/lua_writer.ex` - Writes Lua format
- `lib/we_go_next/results_generator.ex` - Generates personalized results

**Modified:**
- `config/config.exs` - Add WoW paths
- `lib/we_go_next_web/live/encounter_live/show.ex` - Add button handler

### Files in WeGoNext Addon

**New addon at:** `~/dev/games/wow-addons/WeGoNext/`
- `WeGoNext.toc`
- `Core.lua`
- `ResultsHandler.lua`
- `UI.lua`
- `Utils.lua`

---

## Next Steps

1. **Test MCP server** (Phase 0) - one-time setup
2. **Build WeGoNext addon** (Phase 1) - core functionality
3. **Add SavedVariables writer to we_go_next** (Phase 2) - integration
4. **Test end-to-end** with real raid data
5. **Polish addon UI** (custom frames, better formatting)
6. **Distribute to raid team** for beta testing

---

## Decision: When to Implement

**Priority:** Post-MVP (after Phase 5 in main roadmap)

**Why later:**
- MVP works fine with manual callouts
- Combat log parsing is the foundation
- Criteria system more important for functionality
- Addon is a UX enhancement, not core feature

**When to implement:**
- After criteria system working (Phase 3)
- After between-pull reports (Phase 5)
- When tool has been tested with real progression
- Q3-Q4 2026 timeframe
