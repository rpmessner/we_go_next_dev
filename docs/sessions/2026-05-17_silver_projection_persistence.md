# Silver Projection and Persistence

## Date

2026-05-17

## Context

Continued the `Data Warehouse Refactor` task board after the bronze/silver/gold foundation work. The main architectural correction in this session was to keep parser responsibilities and domain projection responsibilities separate.

Earlier task wording expected a Zig `project_silver` NIF. We revised that direction: Zig remains responsible for byte-boundary scanning and normalized event parsing, while Elixir owns medallion projection semantics.

## Architecture Decision

Decision: implement silver projection in Elixir, not Zig.

Reasoning:

- The projection logic is domain logic, not parser logic.
- Existing analyzer code showed that the required behavior is stateful and semantic: death recap windows, debuff open/close tracking, interrupt opportunities, player metadata correlation, and tank inference.
- Moving those semantics into Zig would make iteration and testing harder and would couple product facts to parser internals.
- Silver should define canonical medallion grains going forward, not preserve every legacy UI/cache analyzer shape.

The resulting flow is:

```text
combat log bytes
-> Zig scan_boundaries/2
-> encounter row with byte offsets
-> Zig parse_events/4
-> normalized event maps
-> Elixir Silver.Projector
-> silver.* row groups
-> Silver.project_and_persist/2 transaction
```

## Task Board Updates

Completed in this session:

- #9 Elixir Silver Projection Pipeline
- #10 Silver Persistence API

Board dependency cleanup:

- #10 was unblocked after #9 completed.
- #11 Gold DimPlayer Upsert is now available.
- #16 Silver Round-trip Tests is now available.
- #17 Silver Idempotency Tests is now available.
- #12 Gold FactFailure Builder remains blocked by #11.
- #14 Hook Silver and Gold into Importer remains blocked by #11, #12, and #13.

## Silver Projection Pipeline

Implemented `WeGoNext.Silver.Projector`.

The projector is pure and returns a `%WeGoNext.Silver.Projection{}` with six table-shaped row lists:

- `damage_taken`
- `damage_done`
- `death`
- `interrupt_opportunity`
- `debuff_application`
- `player_info`

Projection behavior:

- damage taken is aggregated by encounter, target GUID, source GUID, and spell ID
- damage done is aggregated by encounter, source GUID, target GUID, and spell ID
- death rows keep a rolling damage recap window
- interrupt rows capture both successful player interrupts and missed NPC cast-success opportunities
- debuff rows track applied and removed debuffs, including duration when removal is observed
- player info rows are encounter-scoped and correlate names/spec/class data from normalized events
- detected roles are conservative: inferred tanks are marked `tank`; other players remain `unknown`
- nil-like natural key values are normalized into sentinel values before persistence

Added `WeGoNext.Silver.Projection` as the result struct.

Added `test/support/fixtures/combat_log_event_fixtures.ex` so future silver/gold tests can compose normalized event maps without embedding large fixture blobs in every test.

Verification:

```text
mix test test/we_go_next/silver/projector_test.exs test/we_go_next/silver/schema_test.exs
5 tests, 0 failures
```

Commit:

```text
2c2b261 Add silver projection pipeline
```

## Silver Persistence API

Implemented `WeGoNext.Silver.project_and_persist/2`.

Default behavior:

- loads the encounter's combat log file
- parses normalized events with `CombatLogParser.parse_events/4`
- calls `WeGoNext.Silver.Projector.project/2`
- persists all six silver row groups inside one `Repo.transaction/1`

Test seam:

- `events: events` may be passed to `project_and_persist/2` to exercise persistence without requiring combat-log text fixtures

Idempotency behavior:

- `Repo.insert_all/3` is used for each silver table
- conflict targets match the natural keys defined by the migrations
- conflicts replace mutable row values while preserving the surrogate `id`
- empty row groups are skipped and return count `0`

The API returns:

```elixir
{:ok, %{projection: projection, counts: counts}}
```

or parser/transaction errors as:

```elixir
{:error, reason}
```

Added `test/we_go_next/silver/persistence_test.exs` to verify:

- all six row groups are inserted
- table counts match the canonical projection fixture
- representative persisted values are correct
- rerunning the same projection does not duplicate rows

Verification:

```text
mix test test/we_go_next/silver/persistence_test.exs test/we_go_next/silver/projector_test.exs test/we_go_next/silver/schema_test.exs
7 tests, 0 failures

mix test test/we_go_next
30 tests, 0 failures
```

Known unrelated suite status:

```text
mix test
4 features, 36 tests, 1 failure, 2 skipped
```

The remaining full-suite failure is the pre-existing Wallaby selector issue in `test/features/encounter_list_test.exs:9`, where the page object looks for `button[type='submit']`.

Commit:

```text
770edce Add silver persistence API
```

## Next Work

Available next tasks:

- #11 Gold DimPlayer Upsert
- #13 Refactor Importer Encounter Insert
- #16 Silver Round-trip Tests
- #17 Silver Idempotency Tests
- #19 Move Detection Tests

Recommended next task on the medallion path: #11, because #12 and #14 depend on it.
