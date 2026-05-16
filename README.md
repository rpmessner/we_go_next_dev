# WeGoNext

A WoW combat log analysis tool that runs alongside the game on a second monitor and tells you what went wrong on the pull you just did.

It's not a damage meter. WoW ships one now, and it's fine for "who did the most DPS." This tool answers different questions:

- **Why** did I die at 2:34?
- Was my rotation actually broken, or was the boss just in a phase change?
- Did anyone hit the boss when they were supposed to be on the adds?
- Are we improving pull over pull, or dying to the same thing every time?
- On a depleted key, which death cost us the timer?

The built-in meter aggregates everything across the encounter. WeGoNext drills into per-target, per-phase, per-pull context — the analysis layer that the meter glosses over.

## Priority Stack

What the tool optimizes for, in order:

1. **My play, this pull** — what did *I* do wrong; where did my rotation break down; uptime gaps not caused by phase changes
2. **My play, over time** — am I improving pull-over-pull; am I dying to the same things
3. **Raid-wide diagnosis** — what killed *us*; who failed mechanics; who needs to improve
4. **Sharing** — give analysis to raid leads; let players see their own data via hosted site or in-game addon link

The original build jumped straight to #3 and skipped #1 and #2. The April 2026 [VISION.md](docs/VISION.md) rewrite corrected that ordering.

## Two Content Modes

After a **wipe** the UI surfaces what went wrong — deaths, mechanic failures, what to fix on the next pull. After a **kill** it surfaces how the pull compared to previous attempts on the same boss. M+ runs are first-class (not "raids plus dungeons"), with key-specific shape: time penalty per death, kick rotation coverage, run-vs-pull views.

## Status

MVP core is complete and being dogfooded in Manaforge Omega progression and pug M+ on **Mittwoch (Warlock, Hand of Algalon, Wyrmrest Accord US)**. Targeting Day-1 usability for the **Midnight expansion raids in March 2026**.

### Working today

- **Combat log parser** — Zig NIF (via Zigler); parses a 344 MB log in ~5 s, where the original Elixir implementation took minutes. Events are no longer persisted to Postgres — only encounter metadata and byte offsets, with events re-parsed on demand.
- **Incremental import** — tracks last-parsed byte per log file; rotations detected automatically; only new bytes are read on refresh.
- **Analyzers** — deaths (with killing blow and damage recap), damage taken (tank/non-tank split, class colors, spell icons), interrupts (with missed-kick detection), debuffs, mechanic failures.
- **Criteria system** — click an ability in the Damage Taken tab to mark it as `avoidable`, `must interrupt`, `soak`, etc. Criteria persist per boss and inherit across difficulties (a Heroic "avoidable" applies on Mythic unless overridden).
- **Pull Summary** — default tab on encounter detail; aggregates wipe cause, deaths, critical failures, players needing coaching, and recommendations.
- **Phoenix LiveView dashboard** — encounter list grouped by instance (dungeon/raid), tabs for Summary / Failures / Deaths / Damage Taken / Damage Done / Interrupts / Debuffs (plus a Between-Pull tab scaffolded for M+).
- **File watcher** — finds the latest `WoWCombatLog-*.txt`, broadcasts new-encounter events over PubSub; LiveViews react in place.
- **Concurrent analysis** — independent analyzers run in parallel via `Task.await_many`; per-encounter analysis is cached as JSON on the encounter row.

### Scaffolded, not wired up yet

- **M+ data layer** — `MythicPlusRun`, `TrashPull`, `GameData.{Instances,Dungeons,Spells}` modules. The 8 Midnight-rotation dungeons (Algethar Academy, Magisters' Terrace, Maisara Caverns, Nexus Point Xenas, Pit of Saron, Seat of the Triumvirate, Skyreach, Windrunner Spire) are seeded with NPC IDs, forces values, and minimap PNGs (`priv/static/images/maps/`). Extraction tooling lives in `tools/` (MDT addon → Lua → Python → `.ex` modules).
- **BetweenPullTab** component — defined and aliased; no LiveView renders it yet.

### Next up (per [docs/sessions/2026-04-10_m_plus_trash_research.md](we_go_next/docs/sessions/2026-04-10_m_plus_trash_research.md))

1. Detect `CHALLENGE_MODE_START` / `CHALLENGE_MODE_END` in the Zig parser to bracket M+ runs.
2. Parse events outside `ENCOUNTER_START`/`END` boundaries — combat log has no `PULL_START` event, so trash pulls have to be inferred from gaps in combat activity.
3. Extract NPC IDs from creature GUIDs (`Creature-0-...-{npcID}-...`) and map to `GameData` enemies.
4. Render per-pull results on dungeon-map minimap overlays.

## Architecture

```
WoW client                         WeGoNext (Phoenix app)
WoWCombatLog-*.txt  ─► FileWatcher ─► Importer ─► CombatLogParser  (Zig NIF)
                       (GenServer)    (per user)  ├─ scan_boundaries/2
                                                  └─ parse_events/4
                                                       │
                                                       ▼
                       Encounters (Postgres) ◄─────  Analyzers
                       — byte offsets                Death / DamageTaken /
                       — metadata                    Interrupt / Debuff /
                       — cached analysis JSON        Failure / PullSummary
                                                       │
                                                       ▼
                                                  LiveView dashboard
                                                  (Summary / Failures /
                                                   Deaths / Damage / etc.)
```

The combat log on disk is the only source of truth for events. The database stores encounter metadata (byte offsets, boss info, fight time) plus cached analysis JSON. When you open an encounter, events are re-parsed in-memory from the log file using the stored offsets. That sounds wasteful but the Zig parser makes it free, and it means there's no per-event table to migrate, vacuum, or balloon. The full session log on this rewrite is in [`2026-04-09_zig_parser_rewrite.md`](2026-04-09_zig_parser_rewrite.md).

OTP layout:

- `WeGoNext.Repo` — Ecto / PostgreSQL
- `Phoenix.PubSub` named `WeGoNext.PubSub` — broadcasts import progress, new-encounter events, log rotation
- `Task.Supervisor` named `WeGoNext.ImportTaskSupervisor` — background imports
- `WeGoNext.ImportWorker` — one import at a time per user, survives page refresh
- `WeGoNext.FileWatcher` — tracks the active combat log file
- `WeGoNextWeb.Endpoint`

The Zig source lives in [`we_go_next/priv/native/combat_log_parser.zig`](we_go_next/priv/native/combat_log_parser.zig) (~1150 lines) and is wired via Zigler's `zig_code_path` option, so the Elixir module stays a thin NIF declaration. The parser handles WoW's CSV quoting, hex flag parsing, the 19-field "advanced combat log" layout introduced in TWW, and the M/D/YYYY HH:MM:SS.mmm timezone-aware timestamp format.

## Quick Start

### Prerequisites

- Elixir `~> 1.19` and Erlang/OTP 27+
- PostgreSQL running locally on the default port
- Zig 0.15.x on `PATH` (Zigler will find it or download it on first compile)
- A WoW retail install. Enable combat logging in-game: `/combatlog`, plus Advanced Combat Logging in **System → Network**.

### Setup

```bash
cd we_go_next
mix setup          # deps.get + asset setup + asset build
mix ecto.setup     # create database + run migrations
mix phx.server     # serves http://localhost:4000
```

The Phoenix endpoint binds to all interfaces by default so a Windows host can reach a WSL2-hosted server at `http://<wsl-ip>:4000` (see commit `37616e1`).

### Pointing at your logs

Open `/settings` and set the path to your WoW logs directory. The typical WSL2-against-Windows path is:

```
/mnt/c/World of Warcraft/_retail_/Logs/
```

The file watcher picks up the most recent `WoWCombatLog-*.txt` automatically. Click **Import** on the encounter list to ingest it; subsequent refreshes are incremental. If you `/combatlog` mid-session, the new file is detected on the next refresh and parsed from byte 0.

### CLI smoke test

```bash
mix run test_parse.exs    # parse the most recent log, print encounter summaries
```

## Project Layout

```
.
├── we_go_next/                            # Phoenix/Elixir Mix project
│   ├── lib/we_go_next/
│   │   ├── combat_log_parser.ex           # NIF surface (loads priv/native/*.zig)
│   │   ├── importer.ex                    # Incremental log import
│   │   ├── file_watcher.ex                # Tracks active log file
│   │   ├── import_worker.ex               # Background import GenServer
│   │   ├── analyzers/                     # Death / DamageTaken / Interrupt /
│   │   │                                  # Debuff / Failure / PullSummary /
│   │   │                                  # DamageDone / PlayerInfo
│   │   ├── analyzers/analysis_cache/      # Serializer + Deserializer
│   │   ├── encounters/                    # Ecto schemas (encounter, criteria)
│   │   ├── game_data/                     # M+ instances, dungeons, spells
│   │   ├── mythic_plus_run.ex             # M+ run grouping (not wired yet)
│   │   └── trash_pull.ex                  # Gap-based pull segmentation
│   ├── lib/we_go_next_web/
│   │   ├── live/encounter_live/           # Index + Show LiveViews
│   │   ├── live/settings_live.ex
│   │   └── components/tabs/               # Summary / Failures / Deaths /
│   │                                      # DamageTaken / DamageDone / Interrupts /
│   │                                      # Debuffs / BetweenPull
│   ├── priv/native/combat_log_parser.zig  # The Zig NIF source
│   ├── priv/repo/migrations/
│   └── priv/static/images/maps/           # Dungeon minimap PNGs
├── docs/
│   ├── VISION.md                          # Product vision (April 2026 rewrite)
│   ├── ROADMAP.md                         # Phases and Midnight timeline
│   ├── TECHNICAL_ARCHITECTURE.md          # Current architecture (May 2026)
│   ├── INTEGRATION_ROADMAP.md             # End-to-end testing plan (completed Nov 2025)
│   └── sessions/                          # Chronological work logs
├── tools/                                 # Data extractors (MDT, spell names, maps)
└── CLAUDE.md                              # Working context for AI-assisted dev
```

## Testing

```bash
mix test                       # full suite (unit + Wallaby feature tests)
mix test test/features/        # feature tests only
mix credo                      # static analysis
```

Feature tests use the **page object pattern**. Put selectors and click flows in `test/support/pages/`, not in the test itself. Existing page objects: `HomePage`, `EncounterDetailPage`, `SettingsPage` — extend these rather than reaching for `css(...)` selectors in a new test.

## Tech Stack

| Layer       | Choice                                  | Why                                                            |
| ----------- | --------------------------------------- | -------------------------------------------------------------- |
| Web         | Phoenix 1.8 + LiveView 1.0              | Between-pull updates without JS; server state                  |
| Database    | PostgreSQL + Ecto                       | Encounter metadata, cached analysis JSON, criteria             |
| Parser      | Zig 0.15.x via Zigler 0.15              | 344 MB log in ~5 s; the Elixir version took minutes            |
| Concurrency | OTP (FileWatcher, ImportWorker)         | One import at a time per user; survives page refresh           |
| Tests       | ExUnit + Wallaby (page objects)         | Browser-driven feature tests for the LiveView UI               |
| Styling     | Tailwind 0.4                            | Utility-first; precompiled, no runtime overhead                |

## Further Reading

- **[docs/VISION.md](docs/VISION.md)** — what this tool is and isn't, priority stack, who uses it (the April 2026 rewrite is the canonical source)
- **[docs/ROADMAP.md](docs/ROADMAP.md)** — phases, milestones, scope cuts if Midnight slips
- **[docs/TECHNICAL_ARCHITECTURE.md](docs/TECHNICAL_ARCHITECTURE.md)** — current architecture: Zig NIF parser, Postgres-backed encounter store, analyzer/LiveView wiring
- **[docs/INTEGRATION_ROADMAP.md](docs/INTEGRATION_ROADMAP.md)** — end-to-end testing plan (completed Nov 2025; kept for history)
- **[2026-04-09_zig_parser_rewrite.md](2026-04-09_zig_parser_rewrite.md)** — the parser-rewrite session log; explains why `encounter_events` is gone
- **[we_go_next/docs/sessions/2026-04-10_m_plus_trash_research.md](we_go_next/docs/sessions/2026-04-10_m_plus_trash_research.md)** — how Warcraft Logs / Details! / WoWAnalyzer handle M+ trash, and what we need to add
- **[docs/sessions/](docs/sessions/)** — chronological session logs from project start (immutable; new sessions append rather than edit)
- **[CLAUDE.md](CLAUDE.md)** — operational context for AI-assisted development
