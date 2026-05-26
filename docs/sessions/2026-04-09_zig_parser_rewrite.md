# 2026-04-09: Zig Parser Rewrite & Architecture Cleanup

## What Changed

### Problem
The old architecture had a wasteful roundtrip:
1. Elixir parsed combat log events line-by-line (slow, minutes for a 600MB file)
2. Every event was written as a row in `encounter_events` Postgres table (thousands of INSERTs per encounter)
3. Events were loaded back from DB to run analyzers
4. Analysis results were cached as JSON in `encounters.analysis`
5. The UI only ever read the cached analysis — event rows were dead weight

Additionally, `FailureAnalyzer` internally re-ran `DamageTakenAnalyzer` and `InterruptAnalyzer`, causing 7 sequential passes over events instead of 4.

### Solution

**Phase 0: Parallel Analysis**
- `FailureAnalyzer` now accepts pre-computed `damage_stats` and `interrupt_stats` via opts
- `Serializer.compute/1` runs 4 independent analyzers concurrently via `Task.async`
- Eliminates duplicate work (7 passes → 4 concurrent + 2 dependent)

**Phase 1-2: Zig NIF Parser (via Zigler)**
- New `WeGoNext.CombatLogParser` module with two NIF functions:
  - `scan_boundaries/2` — scans log for ENCOUNTER_START/END, returns byte offsets + metadata
  - `parse_events/4` — parses all events in a byte range into maps matching analyzer format
- Handles WoW timestamp parsing, CSV quoting, hex flag parsing, advanced combat log field layout (19 advanced info fields in TWW format)
- Returns events as Elixir maps with atom keys, ready for analyzers

**Phase 3: Drop encounter_events**
- Migration to drop the `encounter_events` table
- Deleted `EncounterEvent` Ecto schema, `EventParser` module
- `to_encounter_struct` now uses `CombatLogParser.parse_events` from byte offsets instead of DB
- Import pipeline uses Zig for boundary detection + event parsing, stores only encounter metadata + analysis JSON
- WoW log file is the source of truth for raw events

**Phase 4: Cleanup**
- Deleted `LogReader` module (replaced by Zig NIF)
- Updated `WeGoNext.parse/1` to use `CombatLogParser`
- Renamed from `ZigParser` to `CombatLogParser` (purpose-built, implementation-agnostic)

## Performance

On a 344MB combat log (8 encounters, 1.2M lines):
- Boundary scan: ~4s (was minutes in Elixir)
- Event parse (109K events): ~800ms
- Parallel analysis (4 analyzers): ~340ms
- **Total: ~5s** (was minutes with Elixir parsing + DB writes + DB reads)

## Test Results

7/8 feature tests passing. 1 pre-existing failure (`encounter_list_test` — UI element mismatch unrelated to parser work). Live sync tests (appending encounters and detecting via Refresh) all pass with incremental parsing.

## Files Changed

**Created:**
- `lib/we_go_next/combat_log_parser.ex` — Zig NIF module with inline Zig source
- `priv/repo/migrations/20260409175732_drop_encounter_events.exs`

**Modified:**
- `mix.exs` — added `{:zigler, "~> 0.15.1"}`
- `lib/we_go_next/analyzers/failure_analyzer.ex` — accepts pre-computed results
- `lib/we_go_next/analyzers/analysis_cache/serializer.ex` — parallel execution, string timestamp handling
- `lib/we_go_next/importer.ex` — uses Zig parser, no event insertion, timestamp helpers
- `lib/we_go_next/encounters/encounter.ex` — `to_encounter_struct` uses Zig, public `difficulty_name_for/1`
- `lib/we_go_next/encounter.ex` — public `difficulty_name_for/1`
- `lib/we_go_next.ex` — uses `CombatLogParser` instead of `LogReader`
- `~/.tool-versions` — added `zig 0.15.2`
- Test fixtures updated for TWW advanced combat log format (19 info fields)

**Deleted:**
- `lib/we_go_next/log_reader.ex`
- `lib/we_go_next/encounters/encounter_event.ex`
- `lib/we_go_next/encounters/event_parser.ex`
