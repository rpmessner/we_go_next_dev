# Technical Architecture

**Project:** WoW Raid Diagnostic Tool
**Last Updated:** 2025-11-24

This document outlines the technical decisions, architecture, and component design for the raid diagnostic dashboard.

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     WoW Raid Diagnostic Tool                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │  Combat Log  │───▶│  Log Watcher │───▶│   Parser     │       │
│  │    (File)    │    │  (GenServer) │    │  (Stream)    │       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
│                                                 │                │
│                                                 ▼                │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Event Pipeline                          │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐          │   │
│  │  │   Death    │  │  Damage    │  │ Interrupt  │  ...     │   │
│  │  │  Analyzer  │  │  Tracker   │  │  Tracker   │          │   │
│  │  └────────────┘  └────────────┘  └────────────┘          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                │                                 │
│                                ▼                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  Criteria Matching                        │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │   │
│  │  │ Boss Profile│  │   Failure   │  │   Failure   │       │   │
│  │  │   (Config)  │  │  Detection  │  │   Records   │       │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘       │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                │                                 │
│                                ▼                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      Output Layer                         │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐          │   │
│  │  │    Live    │  │   Report   │  │  Diagram   │          │   │
│  │  │ Dashboard  │  │ Generator  │  │  Builder   │          │   │
│  │  │ (LiveView) │  │            │  │            │          │   │
│  │  └────────────┘  └────────────┘  └────────────┘          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

### Core: Elixir/OTP

**Why Elixir:**
- **Real-time processing**: BEAM VM designed for low-latency message passing
- **Fault tolerance**: Supervisors restart crashed processes automatically
- **Concurrency**: Natural fit for tracking multiple raid members simultaneously
- **Hot code reload**: Update analysis rules without restarting
- **Developer expertise**: Strong Elixir background means faster development

### Web Layer: Phoenix LiveView

**Why LiveView:**
- **Real-time updates**: Push changes to browser instantly without WebSocket complexity
- **Server-rendered**: Minimal JavaScript, easier to maintain
- **State management**: Server-side state simplifies architecture
- **Built-in PubSub**: Easy broadcast of events to dashboard

### Storage

**Primary: ETS (Erlang Term Storage)**
- In-memory, fast reads/writes
- Perfect for encounter state during pulls
- No persistence needed during combat

**Secondary: JSON Files**
- Boss profiles (criteria configurations)
- Portable, human-readable
- Easy to share/version control

**Future: SQLite/PostgreSQL**
- Historical data (if needed)
- Cross-session analytics
- Not required for MVP

---

## Component Design

### 1. Log Watcher (GenServer)

Monitors the WoW combat log file for changes.

```elixir
defmodule RaidDiagnostic.LogWatcher do
  use GenServer

  # State: %{path: string, position: integer, encounter_pid: pid}

  # Watch for file changes
  # Stream new lines from last position
  # Handle file rotation (new log files)
  # Broadcast raw lines to parser
end
```

**Responsibilities:**
- Watch `/mnt/g/World of Warcraft/_retail_/Logs/WoWCombatLog.txt`
- Track file position between reads
- Detect file rotation (new combat log started)
- Emit raw log lines to parser

### 2. Event Parser

Transforms raw log lines into structured events.

```elixir
defmodule RaidDiagnostic.Parser do
  # Input: "11/24/2025 20:15:32.123  UNIT_DIED,..."
  # Output: %Event{type: :unit_died, timestamp: ~N[...], data: %{...}}
end
```

**Event Types:**
- `UNIT_DIED` - Death events
- `SPELL_DAMAGE`, `SPELL_PERIODIC_DAMAGE`, `SWING_DAMAGE` - Damage taken
- `SPELL_INTERRUPT` - Successful interrupts
- `SPELL_CAST_START`, `SPELL_CAST_SUCCESS` - Cast tracking
- `SPELL_AURA_APPLIED`, `SPELL_AURA_REMOVED` - Buff/debuff tracking
- `ENCOUNTER_START`, `ENCOUNTER_END` - Pull boundaries

### 3. Event Analyzers

Specialized processors for different diagnostic needs.

#### Death Analyzer
```elixir
defmodule RaidDiagnostic.Analyzers.Death do
  # Track recent damage per player (rolling window)
  # On UNIT_DIED: capture death recap
  # Output: %Death{player: "Name", time: 134.5, killing_blow: %{...}, recap: [...]}
end
```

#### Damage Tracker
```elixir
defmodule RaidDiagnostic.Analyzers.DamageTaken do
  # Aggregate damage by ability
  # Track damage per player
  # Flag outliers (players taking more than average)
end
```

#### Interrupt Tracker
```elixir
defmodule RaidDiagnostic.Analyzers.Interrupt do
  # Track SPELL_CAST_START for interruptible casts
  # Match with SPELL_INTERRUPT events
  # Detect uninterrupted casts (cast succeeded)
end
```

### 4. Criteria System

Defines what mechanics to track and how to identify failures.

```elixir
defmodule RaidDiagnostic.Criteria do
  defstruct [
    :spell_id,           # The ability to track
    :name,               # Human-readable name
    :type,               # :avoidable | :interrupt | :soak | :spread | ...
    :threshold,          # Failure condition (e.g., hits > 2)
    :notes               # Raid leader notes
  ]
end
```

#### Mechanic Types

| Type | Description | Failure Condition |
|------|-------------|-------------------|
| `:avoidable` | Damage that shouldn't happen | Any hit |
| `:interrupt` | Cast that must be kicked | Cast completed |
| `:soak` | Shared damage mechanic | Too few soakers |
| `:spread` | Requires separation | Hit multiple players |
| `:stack` | Requires grouping | Players too spread |
| `:tank_swap` | Tank-specific | Wrong tank hit |

### 5. Boss Profile System

Stores criteria configurations per boss.

```elixir
defmodule RaidDiagnostic.BossProfile do
  defstruct [
    :boss_name,          # "Manaforge Omega"
    :encounter_id,       # WoW encounter ID
    :criteria,           # [%Criteria{}, ...]
    :notes               # General strategy notes
  ]

  # Save/load from JSON files
  # Auto-load when encounter detected
end
```

**File Format:**
```json
{
  "boss_name": "Manaforge Omega",
  "encounter_id": 12345,
  "criteria": [
    {
      "spell_id": 99999,
      "name": "Fire Zone",
      "type": "avoidable",
      "threshold": {"hits": 1},
      "notes": "Don't stand in fire"
    }
  ]
}
```

### 6. Live Dashboard (Phoenix LiveView)

Real-time display during pulls.

```elixir
defmodule RaidDiagnosticWeb.DashboardLive do
  use Phoenix.LiveView

  # Subscribe to encounter events
  # Display:
  #   - Current encounter status
  #   - Death feed (as they happen)
  #   - Failure feed (criteria violations)
  #   - Raid status summary
end
```

**Dashboard Layout:**
```
┌─────────────────────────────────────────────────────────┐
│  Boss: Manaforge Omega          Duration: 2:34         │
│  Status: IN COMBAT              Deaths: 3              │
├─────────────────────────────────────────────────────────┤
│  DEATHS                    │  FAILURES                 │
│  ─────────                 │  ────────                 │
│  2:12 PlayerA - Fire Zone  │  2:05 PlayerB - Fire Zone │
│  2:18 PlayerB - Fire Zone  │  2:08 PlayerC - Fire Zone │
│  2:31 PlayerC - Slam       │  2:15 PlayerA - Fire Zone │
│                            │  2:20 PlayerD - Interrupt │
├─────────────────────────────────────────────────────────┤
│  RAID STATUS: 17/20 alive  │  Fire Zone hits: 8       │
└─────────────────────────────────────────────────────────┘
```

### 7. Report Generator

Produces between-pull analysis.

```elixir
defmodule RaidDiagnostic.Reports.PullSummary do
  # Generate after encounter ends
  # Include:
  #   - Deaths with causes
  #   - Failures by mechanic
  #   - Failures by player
  #   - Comparison to previous attempt
end
```

**Sample Output:**
```
=== Pull #5 Summary ===
Duration: 2:34 (Best: 3:45)
Deaths: 3 (Previous: 5) ✓ Improved

WHAT KILLED US:
  Fire Zone damage overwhelmed healers at 2:30

MECHANIC FAILURES:
  Fire Zone: 8 hits (PlayerA: 3, PlayerB: 2, PlayerC: 2, PlayerD: 1)
  Missed Interrupt: 1 (PlayerE)

PLAYER NOTES:
  PlayerA: Focus on Fire Zone positioning
  PlayerB: Improve Fire Zone awareness
  PlayerE: Watch interrupt assignment
```

### 8. Diagram Builder (Future)

Generates annotated minimap images.

```elixir
defmodule RaidDiagnostic.Diagrams do
  # Load minimap background image
  # Overlay:
  #   - Position markers
  #   - Movement arrows
  #   - Death locations (from combat data)
  # Export as PNG for Discord
end
```

---

## Data Flow

### During Pull (Real-Time)

```
Combat Log File
    │
    ▼ (file change detected)
Log Watcher (GenServer)
    │
    ▼ (raw lines)
Parser
    │
    ▼ (structured events)
    ├──▶ Death Analyzer ──────┐
    ├──▶ Damage Tracker ──────┤
    ├──▶ Interrupt Tracker ───┤
    └──▶ Debuff Tracker ──────┤
                              │
                              ▼
                    Criteria Matcher
                              │
                              ▼
                    Failure Records
                              │
                              ▼ (PubSub broadcast)
                    Live Dashboard
```

### Between Pulls (Analysis)

```
Encounter End Event
    │
    ▼
Report Generator
    │
    ├──▶ Pull Summary (terminal/web)
    ├──▶ Player Reports (private, exportable)
    └──▶ Progress Tracking (trends)
```

---

## OTP Supervision Tree

```
Application
└── Supervisor
    ├── LogWatcher (GenServer)
    │   └── monitors combat log file
    ├── EncounterSupervisor (DynamicSupervisor)
    │   └── spawns per-encounter processes
    ├── ProfileManager (GenServer)
    │   └── loads/saves boss profiles
    ├── CriteriaRegistry (ETS table owner)
    │   └── active criteria for current boss
    └── Phoenix.Endpoint
        └── LiveView sessions
```

---

## Performance Targets

| Metric | Target | Rationale |
|--------|--------|-----------|
| Event latency | <500ms | Visible feedback during pull |
| Memory usage | <500MB | Long raid nights (3+ hours) |
| Events/second | 500+ | Heavy combat scenarios |
| Crash recovery | <1s | Supervisor restart |

---

## Key Technical Decisions

### Why Not a Damage Meter?

Damage meters exist (Details!, Warcraft Logs). This tool solves a different problem:
- **Mechanics over meters**: DPS doesn't matter if you're dead
- **Coaching over ranking**: Help players improve, not shame them
- **Progression focus**: What's blocking our kill?

### Why Build Custom vs. Use Warcraft Logs?

Warcraft Logs is post-raid analysis. This tool is:
- **Real-time**: During and between pulls
- **Iterative**: Build criteria as you learn fights
- **Private**: Individual coaching without public logs

### Why Elixir vs. Existing Tools?

- **Real-time native**: Built for this use case
- **Full control**: Customize exactly what to track
- **Learning opportunity**: Deepen Elixir/OTP expertise
- **No dependencies**: Works offline, no API limits

---

## Future Considerations

### Position Tracking

Combat log doesn't include player positions directly. Options:
- Infer from damage events (who got hit by positional mechanic)
- Correlate with DBM/BigWigs timer data (if exposed)
- Manual position assignment in diagrams

### Integration Points

- **WoW Addon** (`~/dev/wow-addons/`): Lua addon to display reports in-game
  - Raid Leader report (full details, private)
  - Raid report (filtered, appropriate for sharing)
  - Per-boss configuration of what to expose
  - Future: Personalized reports per player
- **Discord Bot**: Post reports to channel
- **WeakAuras Export**: Generate WA strings for alerts
- **Warcraft Logs API**: Compare to public logs (optional)

### Scaling

Current design is single-raid focused. Future expansion:
- Multiple concurrent raids (guild management)
- Historical analytics across sessions
- Profile sharing/community library

---

## Security Considerations

- **Local only**: No data leaves local machine by default
- **No game modification**: Read-only combat log access
- **Private by design**: Reports are for raid leader only

---

## Development Approach

1. **Vertical slices**: Build end-to-end for one feature before expanding
2. **Real data first**: Test with actual combat logs immediately
3. **Iterate during progression**: Use current content as test bed
4. **Ship and refine**: MVP for Midnight, polish after

---

**Next Steps:** See `docs/HANDOFF.md` for immediate implementation tasks.
