# Session: Encounter Events Normalization

**Date:** 2025-11-29

## Problem Statement

The original data model stored combat log events in two problematic ways:

1. **`raw_log` column** - Stored the entire raw text of combat log lines in each encounter record. This required re-parsing the text every time we needed to analyze the encounter.

2. **`analysis` JSON blob** - Pre-computed analysis results cached in a JSON column. This had issues:
   - Gets stale when new analyzers are added
   - Won't work well in embedded/SQLite mode
   - Not queryable

The goal was to create a proper normalized data model where:
- Events are parsed once during import
- Analyzers query structured data from the database
- No re-parsing needed for analysis

## Solution: `encounter_events` Table

Created a new normalized table to store parsed combat log events with structured fields.

### Schema Design

```elixir
schema "encounter_events" do
  belongs_to :encounter, Encounter

  # Core timing
  field :event_type, :string           # "SPELL_DAMAGE", "UNIT_DIED", etc.
  field :timestamp, :utc_datetime_usec
  field :time_into_fight, :float

  # Source/Target (most events have these)
  field :source_guid, :string
  field :source_name, :string
  field :source_flags, :integer
  field :target_guid, :string
  field :target_name, :string
  field :target_flags, :integer

  # Spell info (spell events)
  field :spell_id, :integer
  field :spell_name, :string
  field :spell_school, :integer

  # Damage/healing amounts
  field :amount, :integer
  field :overkill, :integer
  field :absorbed, :integer

  # For interrupts - the spell that was interrupted
  field :extra_spell_id, :integer
  field :extra_spell_name, :string

  # For COMBATANT_INFO and variable data
  field :extra, :map

  timestamps()
end
```

### Indexes

- `(encounter_id)` - Basic lookup
- `(encounter_id, event_type)` - "All deaths in encounter"
- `(encounter_id, target_guid)` - "All damage to player X"
- `(encounter_id, timestamp)` - Timeline queries

## Files Changed

### New Files

| File | Purpose |
|------|---------|
| `priv/repo/migrations/..._create_encounter_events.exs` | Migration for new table |
| `lib/we_go_next/encounters/encounter_event.ex` | Ecto schema for normalized events |
| `lib/we_go_next/encounters/event_parser.ex` | Parses raw events into normalized format |

### Modified Files

| File | Changes |
|------|---------|
| `lib/we_go_next/importer.ex` | Inserts normalized events during import |
| `lib/we_go_next/encounters/encounter.ex` | `to_encounter_struct/1` now loads from DB instead of parsing raw_log |
| `lib/we_go_next/analyzers/death_analyzer.ex` | Uses normalized event fields |
| `lib/we_go_next/analyzers/damage_taken_analyzer.ex` | Uses normalized event fields |
| `lib/we_go_next/analyzers/interrupt_analyzer.ex` | Uses normalized event fields |
| `lib/we_go_next/analyzers/debuff_analyzer.ex` | Uses normalized event fields |
| `lib/we_go_next/analyzers/damage_done_analyzer.ex` | Uses normalized event fields |
| `lib/we_go_next/analyzers/player_info_analyzer.ex` | Uses normalized event fields |

## Key Implementation Details

### Event Parsing (EventParser)

The `EventParser` module handles converting raw combat log data into normalized fields. WoW combat log events have variable formats depending on event type:

- **Common prefix** (positions 1-8): source_guid, source_name, source_flags, etc.
- **Spell prefix** (positions 9-11): spell_id, spell_name, spell_school
- **Event-specific suffix**: varies by event type

The parser extracts these into consistent named fields.

### Analyzer Updates

Before (position-based):
```elixir
source_guid = Enum.at(data, 1)
amount = Enum.at(data, 31) |> parse_int()
```

After (field-based):
```elixir
source_guid = event.source_guid
amount = event.amount || 0
```

This is cleaner, less error-prone, and self-documenting.

### Event Loading

Events are loaded from DB in `to_encounter_struct/1`:

```elixir
defp load_events_from_db(encounter_id) do
  EncounterEvent
  |> where([e], e.encounter_id == ^encounter_id)
  |> order_by([e], asc: e.timestamp)
  |> Repo.all()
  |> Enum.map(&event_to_map/1)
end
```

Events are returned in chronological order (no more reversing needed).

## Data Flow

```
Import Flow:
  1. LogReader parses raw log file → raw event maps
  2. EventParser normalizes each event → structured attributes
  3. Importer inserts into encounter_events table

Analysis Flow:
  1. EncounterStore.get_encounter(id) called
  2. load_events_from_db() queries encounter_events
  3. Events converted to maps for analyzer compatibility
  4. Analyzers process events using field access
```

## Performance Characteristics

- **Import**: Slightly slower (parsing + inserting events)
- **Analysis**: Faster (no parsing, direct field access)
- **List view**: No change (doesn't load events)
- **Storage**: Similar to raw_log (normalized fields vs text)

## Completed

All tasks done:
1. ✅ Created `encounter_events` table with normalized fields
2. ✅ Updated all analyzers to use normalized fields
3. ✅ Dropped `raw_log` column from `encounters` table

## Future Consideration

- **Re-evaluate `analysis` cache** - May still want summary caching, but can now recompute cheaply from events

## Testing

Verified working:
- Import creates events in DB (3212 events for 22 encounters)
- Death analyzer finds deaths correctly
- Damage analyzer calculates totals correctly
- Events load in chronological order
- No compilation errors

## Notes

- The `extra` map field handles variable data (aura_type for buffs/debuffs, class_id/spec_id for COMBATANT_INFO)
- Events are inserted in batches of 1000 to avoid huge queries
- The encounter list query already excluded `raw_log` for performance, so no change needed there
