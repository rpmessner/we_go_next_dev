# Technical Architecture

**Project:** WeGoNext — WoW Combat Log Analysis Tool
**Last Updated:** 2026-05-18

This document describes the architecture *as it stands today* — the Zig-NIF parser, Postgres-backed encounter store, and Phoenix LiveView UI. Earlier design notes (ETS-backed storage, in-Elixir parser, JSON boss profiles) are superseded; the relevant rewrite session is in [`../2026-04-09_zig_parser_rewrite.md`](../2026-04-09_zig_parser_rewrite.md).

For *why* this shape (vs. damage meters, Warcraft Logs, etc.) see [VISION.md](VISION.md).

---

## System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              WeGoNext                                    │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  WoW client                                                              │
│  WoWCombatLog-*.txt ──► FileWatcher ──► Importer ──► CombatLogParser    │
│                         (GenServer)     (per user      (Zig NIF)         │
│                                          via              │              │
│                                          ImportWorker)    │ byte offsets │
│                                          │                │ + events     │
│                                          ▼                ▼              │
│                                  ┌─────────────────────────────┐         │
│                                  │  public.encounters          │         │
│                                  │  transitional import rows   │         │
│                                  │  — wow_encounter_id, name,  │         │
│                                  │    difficulty, success, ms  │         │
│                                  │  — start_byte / end_byte    │         │
│                                  └─────────────────────────────┘         │
│                                                │                         │
│                                                ▼                         │
│                                  ┌─────────────────────────────┐         │
│                                  │  Silver projections         │         │
│                                  │  damage/death/interrupt/    │         │
│                                  │  debuff/player rows keyed   │         │
│                                  │  by gold.dim_encounter.id   │         │
│                                  └─────────────────────────────┘         │
│                                                │                         │
│                                                ▼                         │
│                                  ┌─────────────────────────────┐         │
│                                  │  Gold read models           │         │
│                                  │  dim_encounter / dim_player │         │
│                                  │  dim_mechanic_criterion /   │         │
│                                  │  fact_failure               │         │
│                                  └─────────────────────────────┘         │
│                                                │                         │
│                                                ▼                         │
│                                  ┌─────────────────────────────┐         │
│                                  │  LiveView (Phoenix)         │         │
│                                  │  Index (encounter list)     │         │
│                                  │  Failures (gold facts)      │         │
│                                  │  Settings                   │         │
│                                  └─────────────────────────────┘         │
│                                                                          │
│            PubSub (`WeGoNext.PubSub`): new-encounter broadcasts,         │
│                  import progress, log-rotation events                    │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

| Layer       | Choice                                  | Rationale                                                                      |
| ----------- | --------------------------------------- | ------------------------------------------------------------------------------ |
| BEAM        | Elixir 1.19 + Erlang/OTP 27             | GenServers, supervisors, PubSub, hot reload. Strong existing expertise.        |
| Web         | Phoenix 1.8 + LiveView 1.0              | Server-rendered UI, push-on-change without writing JS.                          |
| Database    | PostgreSQL + Ecto 3                     | Import bookkeeping plus bronze/silver/gold/rules persistence.                  |
| Parser      | Zig 0.15.x via Zigler 0.15              | Native NIF; a 344 MB log scans in ~5 s where pure Elixir took minutes.          |
| Styling     | Tailwind 0.4 (Phoenix integration)      | Utility-first, precompiled.                                                    |
| Tests       | ExUnit + Wallaby (page objects)         | Unit + browser-driven feature tests.                                           |

---

## Storage Model

### What lives in Postgres

- **`combat_log_files`** — one row per imported `WoWCombatLog-*.txt`, with `last_parsed_byte` for incremental imports and `file_size` for rotation detection.
- **`encounters`** — transitional boss + dungeon import records:
  - `wow_encounter_id`, `name`, `difficulty_id`, `group_size`, `instance_id`, `success`, `fight_time_ms`
  - `start_byte`, `end_byte` — byte offsets into the parent combat log file
- **`silver.*`** — deterministic encounter-grain projections for damage taken, damage done, deaths, interrupt opportunities, debuff applications, and player info.
- **`gold.*`** — analytic dimensions/facts. Current UI fact path: `gold.fact_failure`, keyed by `gold.dim_encounter`, `gold.dim_player`, and `gold.dim_mechanic_criterion`.
- **`rules.*`** — authored mechanic configuration. `rules.mechanic_criterion` rows are promoted into immutable gold criterion snapshots before facts use them.
- **`users`** — minimal: name, `wow_logs_path`, `last_loaded_log`, `character_name`, `is_admin`.

### What does *not* live in Postgres

- **Combat events.** The `encounter_events` table was dropped in the April 2026 rewrite. Events are re-parsed on demand from the log file using the stored byte offsets when an encounter is opened. The Zig parser is fast enough that this is effectively free.

### Why no per-event table

The previous design wrote thousands of event rows per encounter and then immediately read them back to run analyzers. The current medallion shape stores coarse-grain silver projections instead: enough structure for deterministic rebuilds and SQL facts without taking on event-grain volume.

---

## Component Design

### `WeGoNext.FileWatcher` (GenServer)

Tracks the user's currently active combat log file.

- Polls the configured logs directory for `WoWCombatLog-*.txt` files.
- Detects rotation when a newer file appears or the current file shrinks (typical after `/reload`).
- Broadcasts `{:log_rotated, new_clf, count}` on `WeGoNext.PubSub` so LiveViews can update their "watching" indicator.

### `WeGoNext.ImportWorker` (GenServer)

One import operation at a time per user; survives page refresh.

- Triggered by the user clicking **Import** in the encounter list, or by file-watcher rotation events.
- Runs the import inside `WeGoNext.ImportTaskSupervisor` so the worker stays responsive.
- Broadcasts `{:import_progress, %{bytes_read, total_bytes, encounters_found}}` on a per-user PubSub topic.

### `WeGoNext.CombatLogParser` (Zig NIF)

The hot path. Implemented in [`we_go_next/priv/native/combat_log_parser.zig`](../we_go_next/priv/native/combat_log_parser.zig) and wired into Elixir via Zigler's `zig_code_path` option.

Two functions:

```elixir
@spec scan_boundaries(String.t(), non_neg_integer()) ::
        {:ok, [map()], non_neg_integer()} | {:error, term()}
@spec parse_events(String.t(), non_neg_integer(), non_neg_integer(), String.t()) ::
        {:ok, [map()]} | {:error, term()}
```

- `scan_boundaries/2` walks the file once, returns a list of encounter boundaries `%{wow_encounter_id, name, difficulty_id, group_size, instance_id, success, fight_time_ms, start_byte, end_byte}` plus the new end-of-file byte. Used during import.
- `parse_events/4` parses every event in a byte range into Elixir maps matching the format the analyzers consume. Called on demand when an encounter is opened.

The parser handles WoW's CSV quoting, hex flag parsing, the 19-field "advanced combat log" layout introduced in TWW, and the `M/D/YYYY HH:MM:SS.mmm-TZ` timestamp format.

### `WeGoNext.Importer`

Glue between FileWatcher events and the database.

- Calls `CombatLogParser.scan_boundaries/2` from the last-parsed byte.
- Inserts or fetches one transitional `encounters` row per boundary.
- Upserts the corresponding `gold.dim_encounter` row.
- Projects silver rows and rebuilds gold failure facts for newly inserted encounters.
- Updates `last_parsed_byte` after each encounter so failures resume cleanly.
- Broadcasts progress over PubSub.

### Analyzers (`WeGoNext.Analyzers.*`)

Legacy diagnostic helpers taking a `%WeGoNext.Encounter{}` with events loaded and returning a result map. They are retained for command-line inspection and projection parity tests, not as active UI read models.

| Module                  | Output                                                                          |
| ----------------------- | ------------------------------------------------------------------------------- |
| `DeathAnalyzer`         | Deaths with killing blow + damage recap                                         |
| `DamageTakenAnalyzer`   | Per-player damage taken; tank vs. non-tank split; per-ability breakdown         |
| `DamageDoneAnalyzer`    | Per-player damage done; per-target breakdown                                    |
| `InterruptAnalyzer`     | Per-player interrupt counts; missed-kick detection                              |
| `DebuffAnalyzer`        | Debuff applications by player/spell                                             |
| `PlayerInfoAnalyzer`    | Player classes/specs from `COMBATANT_INFO`                                      |

The legacy analyzer JSON cache, `FailureAnalyzer`, and `PullSummary` were removed during the medallion refactor. New analysis views should query silver/gold/rules read models.

### Rules and Failure Facts

Authored mechanics live in the `rules` schema, not in public UI-model tables.

- `rules.ruleset` tracks draft, active, and archived rulesets.
- `rules.mechanic_criterion` stores authored criteria and threshold semantics.
- `gold.dim_mechanic_criterion` snapshots rule rows for fact stability.
- `gold.fact_failure` rebuilds from silver projections plus selected gold criterion snapshots.

### LiveView UI

```
WeGoNextWeb.EncounterLive.Index   → /             (encounter list, grouped by instance)
WeGoNextWeb.FailureLive.Index     → /failures     (gold-backed mechanic failures)
WeGoNextWeb.SettingsLive          → /settings     (logs path, character name, file watcher status)
```

The legacy `/encounters/:id` analyzer-cache tab UI has been pruned. Any replacement encounter detail page should be built against silver/gold/rules read models.

### M+ Support (in progress)

Data layer is in place:

- `WeGoNext.GameData.{Instances, Dungeons, Spells}` — instance/dungeon name lookups, per-mob NPC IDs and forces values, spell name lookups
- `WeGoNext.GameData.Dungeons.*` — 8 modules for the Midnight rotation (AlgetharAcademy, MagistersTerrace, MaisaraCaverns, NexusPointXenas, PitOfSaron, SeatOfTheTriumvirate, Skyreach, WindrunnerSpire)
- `WeGoNext.MythicPlusRun`, `WeGoNext.TrashPull` — run + pull data structures with gap-based segmentation
- Minimap PNGs in `priv/static/images/maps/`

Runtime wiring is **not done yet** — the Zig parser doesn't yet detect `CHALLENGE_MODE_START`/`CHALLENGE_MODE_END`, and `parse_events` only reads inside `ENCOUNTER_START`/`END` ranges. See [`../we_go_next/docs/sessions/2026-04-10_m_plus_trash_research.md`](../we_go_next/docs/sessions/2026-04-10_m_plus_trash_research.md) for the detailed gap.

---

## Data Flow

### Import (user clicks Import, or watcher fires)

```
FileWatcher detects new bytes / rotation
        │
        ▼ broadcasts new encounter via PubSub
ImportWorker.import_log/2
        │
        ▼
CombatLogParser.scan_boundaries(path, last_parsed_byte)
        │
        ▼ for each boundary
Importer.insert_single_encounter/3   ──►  encounters row
        │
        ▼
gold.dim_encounter upsert
        │
        ▼
silver projection rows
        │
        ▼
gold.fact_failure rebuild
        │
        ▼
Importer.update_file_progress/2      ──►  last_parsed_byte
        │
        ▼ broadcasts {:import_progress, ...}
LiveView (Index)  ──►  refreshes encounter list
```

### Viewing failure facts

```
User opens /failures
        │
        ▼
FailureLive.Index.mount/3
        │
        ▼
Gold.FailureSummary.list_failures/0
        │
        ▼
gold.fact_failure + gold dimensions
        │
        ▼
LiveView renders grouped failures by encounter, mechanic, and player
```

---

## OTP Supervision Tree

From `WeGoNext.Application`:

```
WeGoNext.Supervisor (one_for_one)
├── WeGoNext.Repo                        Ecto / PostgreSQL
├── Phoenix.PubSub (name: WeGoNext.PubSub)
├── Task.Supervisor (name: WeGoNext.ImportTaskSupervisor)
├── WeGoNext.ImportWorker                One import at a time per user
├── WeGoNext.FileWatcher                 Tracks active combat log file
└── WeGoNextWeb.Endpoint                 Phoenix HTTP
```

No `ProfileManager`, no `CriteriaRegistry`, no per-encounter `DynamicSupervisor`. Earlier design notes referenced these, but they were never built. Mechanic rules persist in Postgres under `rules`, and active analysis views read gold facts.

---

## Performance

Measured against a 344 MB combat log with 8 encounters and ~1.2 M lines (Manaforge Omega progression):

| Stage                              | Time           |
| ---------------------------------- | -------------- |
| `scan_boundaries` (full file)      | ~4 s           |
| `parse_events` (~109K events)      | ~800 ms        |
| Legacy analyzer pass               | ~340 ms        |
| **End-to-end boundary scan**        | **~5 s**       |

For comparison the prior pure-Elixir implementation took minutes on the same file. The win comes from (a) avoiding the per-event DB roundtrip entirely and (b) doing the CSV/timestamp/hex parsing in Zig with `std.heap.page_allocator`.

---

## Key Technical Decisions

### Why between-pull, not live

WoW buffers combat log writes during active combat — events can be delayed several minutes from gameplay. The external log file is *not* a real-time stream during a pull. It flushes immediately on `ENCOUNTER_END`, which is when analysis is actually actionable (during runback). A true live-during-combat view would require a companion addon emitting events over WebSocket; that's deliberately out of scope.

### Why Zig (and not Rust or NIFs in C)

A pure-Elixir parser was the bottleneck. Two paths to native speed: Rustler or Zigler. Zig 0.15 was easier to drop in given the no-dependency build, and Zigler 0.15 supports loading the Zig source from an external file via `:zig_code_path`, which keeps the Elixir module a thin NIF declaration and lets the Zig code be edited with ZLS / `zig fmt` / proper syntax highlighting.

### Why not Warcraft Logs

WCL is post-raid analysis with a public-facing rankings angle. WeGoNext is between-pull and private. Different problem.

### Why not a damage meter

Damage meters answer "who did the most." WeGoNext answers *why* — per-target, per-phase, per-pull context that the in-game meter aggregates away. See [VISION.md](VISION.md).

---

## Security & Privacy

- **Local only.** No data leaves the machine. The Phoenix server binds to all interfaces by default so the Windows host can reach a WSL2-hosted server, but only on the local network.
- **Read-only.** Combat log access is read-only; the tool never writes to game files or modifies the client.
- **Private by design.** Criteria, analyses, and per-player breakdowns are not shared anywhere unless the user explicitly exports them.

---

## What's Out of Scope (For Now)

- **Live-during-combat updates.** Combat log buffering makes this impossible without an in-game addon.
- **Position tracking.** Combat log doesn't include player coordinates. Would require an addon or DBM/BigWigs integration to overlay positions on minimaps.
- **Multi-user / hosted version.** The data model has a `users` table but the deployment model is single-user-on-localhost. A hosted version with role-based access (raid leads see everything, players see own data) is post-MVP.
- **WCL parity.** No public rankings, no log uploads, no public profile pages.

---

## See Also

- [README.md](../README.md) — project overview and quick start
- [VISION.md](VISION.md) — what this tool is and isn't (April 2026)
- [ROADMAP.md](ROADMAP.md) — phases and Midnight launch timeline
- [`../2026-04-09_zig_parser_rewrite.md`](../2026-04-09_zig_parser_rewrite.md) — full session log on the parser rewrite
- [`../we_go_next/docs/sessions/2026-04-10_m_plus_trash_research.md`](../we_go_next/docs/sessions/2026-04-10_m_plus_trash_research.md) — what M+ runtime wiring still needs
