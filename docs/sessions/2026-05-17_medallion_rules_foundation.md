# Medallion Rules Foundation

## Date

2026-05-17

## Context

Continued the `Data Warehouse Refactor` task board after the first gold failure fact work. The main architectural concern was keeping the new bronze -> silver -> gold flow independent from legacy app-domain tables and from the existing frontend import flow.

The key user direction was:

- existing data is disposable or transitional
- most analytics can be rebuilt from logs
- bronze -> gold should remain independent from legacy tables for now
- mechanic criteria are business rules and need their own abstraction
- the current goal is a solid foundation that can accept more rules and future patch data later

## Completed Tasks

Completed during this phase:

- #12 Gold FactFailure Builder
- #13 Refactor Importer Encounter Insert
- #24 Rebaseline medallion schema from logs
- #25 Rules Layer Foundation
- #26 Rules Validation and Seed Path

The rules refactor sidebar is now intentionally placed between #13 and #14. Task #13 can stand alone because it only changes importer insertion semantics. Task #14 is blocked on #28 because it is the first point where imported encounters would automatically trigger silver/gold fact rebuilds, and those rebuilds should use rules-backed criterion snapshots.

## Medallion Rebaseline

Task #12 was reworked from a bridge over legacy domain tables into a clean medallion path.

Current shape:

- `gold.dim_encounter` is the analytics encounter grain.
- Silver tables use `encounter_dim_id`.
- `gold.dim_player` is conformed from `silver.player_info`.
- `gold.dim_mechanic_criterion` stores the criterion rows used by gold facts.
- `gold.fact_failure` rebuilds from `gold.dim_encounter`, `gold.dim_mechanic_criterion`, `gold.dim_player`, and `silver.*`.
- `FactFailure.rebuild_for_encounter/1` operates on a gold encounter dimension id.

The medallion production path should not read from:

- `public.encounters`
- `public.mechanic_criteria`
- old frontend/import criteria behavior

Legacy UI and JSON analysis cache may remain during transition, but they are not the target architecture for new read models.

## Importer Insert Refactor

Task #13 changed importer encounter insertion semantics.

Before:

- `insert_all(..., on_conflict: :nothing)` skipped duplicates silently.
- Every scanned boundary was counted as a new encounter.
- Analysis could be scheduled even when the boundary already existed.

Now:

- scanned boundaries go through `insert_or_fetch_encounter_from_boundary/2`
- the helper returns inserted/existing semantics internally
- duplicate `(combat_log_file_id, start_time)` rows fetch the existing encounter
- only inserted rows count as `new_encounters`
- downstream analysis/rebuild scheduling only runs when something new was inserted

This is the right foundation for #14 because the importer can later run silver/gold only for new encounters by default.

## Rules Layer

Created a dedicated `rules` schema and Ecto context.

Tables:

- `rules.ruleset`
- `rules.mechanic_criterion`

Ruleset decisions:

- first implementation supports one globally active ruleset
- status is `draft`, `active`, or `archived`
- `activated_at` and `archived_at` are audit fields
- partial unique index enforces at most one active ruleset
- unique `(name, version)` supports idempotent static seed loading

Mechanic criterion decisions:

- rules are authored business configuration
- rules are not silver event data
- rules are not gold fact snapshots until promoted
- matching keys remain `spell_id`, optional `boss_encounter_id`, and optional `difficulty_id`
- display names are curated labels copied into later snapshots
- nullable boss/difficulty scope uniqueness is enforced with a PostgreSQL expression unique index

Threshold validation:

- `avoidable`: requires only `threshold["max_hits"]` as a non-negative integer
- `interrupt`: omitted/empty threshold defaults to `%{"must_interrupt" => true}` and requires a boolean
- `soak`, `spread`, `stack`, `tank_mechanic`, `healer_mechanic`: require `{}` until a fact implementation defines their semantics

## Seed Path

Added a static JSON seed path:

```text
we_go_next/priv/rules/initial_mechanic_rules.json
```

Added:

```text
mix we_go_next.seed_rules
```

The seed path goes through `WeGoNext.Rules`, so normal changesets and validations apply. Seeds are intentionally not stored in migrations because mechanic rules are mutable business configuration.

Current bundled seed rows are limited to local evidence with confident spell ID resolution:

- `1214081` / `Arcane Expulsion` as `avoidable`
- `1269183` / `Void Burst` as `avoidable`

Evidence sources:

- `data/naazindhri_mythic/mittwoch_damage_taken.csv`
- `docs/sessions/2025-11-28_pull_summary_and_integration_planning.md`
- `tools/spell_names.json`

Names from CSV exports without reliable local spell ID mappings were not seeded.

## Rules Refactor Plan

Created:

```text
docs/rules_layer_refactor.md
```

Important plan decisions:

- `rules.*` is the source of truth for authored rules.
- `gold.dim_mechanic_criterion` is the fact-facing snapshot table.
- Facts should use `criterion_dim_id` as rule identity.
- Do not store `ruleset_id` directly on `gold.fact_failure` in this phase.
- Rebuilds should support `ruleset: :active` and explicit `ruleset_id`.
- Point-in-time rule selection by encounter timestamp is deferred until season/patch policy exists.

## Future Patch Data

Created #29 for future patch-aware rule source ingestion.

Intent:

- later, ingest or refresh spell/encounter/mechanic source data as patches change
- use that source data to support curated rules and seed/promotion workflows
- keep this out of PR1 and out of the current local seed foundation

## Verification

Focused checks run during this work:

```text
mix test test/we_go_next/importer_test.exs
mix test test/we_go_next/importer_test.exs test/we_go_next/bronze/combat_log_reconciler_test.exs
mix test test/we_go_next/rules_test.exs
MIX_ENV=test mix we_go_next.seed_rules
mix test test/we_go_next
mix ecto.migrate
```

At the end of this session, `mix test test/we_go_next` passed with backend tests green.

## Remaining Task Order

Immediate rules sidebar:

- #27 Promote Rules to Gold Criterion Snapshots
- #28 Make FactFailure Ruleset-Aware

Then PR1 path:

- #14 Hook Silver and Gold into Importer
- #16 Silver Round-trip Tests
- #17 Silver Idempotency Tests
- #19 Move Detection Tests
- #22 PR 1 Acceptance Gate

PR2/UI work remains blocked until the PR1 gate:

- #15 Failures LiveView
- #20 Gold Rebuild Task
- #21 End-to-end Failures Feature Test
- #23 Plan Next Medallion-Backed Views

Future/non-blocking:

- #29 Add Patch-Aware Rule Source Ingestion
