# 2026-05-18: Docs Refresh, Event-Grain Silver Guardrails, and Gold Encounter Shell

## Context

This session followed the PR1 medallion backend and first failures UI work. The user wanted the repository documentation brought in line with the current dim/fact/data-warehouse/medallion architecture, then moved into source-data cleanup and the next medallion UI boundary tasks.

The main product direction was clarified: the project is no longer organized around the old Midnight launch framing. The active roadmap is now real-data operability through a medallion-backed frontend, followed by fact/dimension/criterion buildout.

## Task Board Updates

- Created and completed `#55 Reorganize and refresh base documentation`.
- Completed `#47 Define minimal event-grain silver observations`.
- Completed `#48 Key medallion encounter views by gold encounter identity`.

## Documentation Reorganization

Commit: `d3b386d Refresh medallion documentation`

- Rewrote the root `README.md` around the current local-first medallion application.
- Added active docs:
  - `docs/README.md`
  - `docs/ARCHITECTURE.md`
  - `docs/OPERATIONS.md`
- Rewrote:
  - `docs/ROADMAP.md`
  - `docs/VISION.md`
- Moved stale design and planning docs into `docs/historical/`.
- Moved app-local session notes from `we_go_next/docs/sessions/` into repo-level `docs/sessions/`.
- Updated `CLAUDE.md` so durable agent context points to the active docs.
- Removed stale Midnight launch pressure from active project context and replaced it with current board focus: frontend workflows first, then fact/dimension/criterion expansion.

## Obsolete Evidence Cleanup

Commit: `7d5bba9 Prune obsolete local evidence docs`

- Removed `weekly_performance_review.md`.
- Removed the checked-in Warcraft Logs CSV export folder under `data/`.
- Updated active docs and rule-seed notes to avoid pointing at deleted CSV paths.
- Clarified that new external evidence should come through explicit source-data ingestion instead of ad hoc checked-in data files.

## Minimal Event-Grain Silver Observations

Commit: `4bc3b59 Add silver damage taken event grain`

Task `#47` added a deliberately narrow event-grain silver table:

- `silver.damage_taken_event`
- schema module `WeGoNext.Silver.DamageTakenEvent`
- migration `20260518030000_create_silver_damage_taken_event.exs`

The table stores one row per player-targeted damage taken hit for:

- `SPELL_DAMAGE`
- `SPELL_PERIODIC_DAMAGE`
- `SWING_DAMAGE`
- `RANGE_DAMAGE`
- `ENVIRONMENTAL_DAMAGE`

The table keeps:

- `encounter_dim_id`
- combat-log event index
- event type
- timestamp / ms into fight
- source and target GUID/name
- NPC source flag
- spell ID/name/school
- amount and overkill

Existing aggregate silver tables remain intact. `silver.damage_taken` is still the current fact input for avoidable failure counts. The new event table exists for rule review, classifier evidence, candidate matching, and future facts that need individual hit inspection.

The event-grain policy was documented:

- silver must not become a generic raw combat-log event warehouse,
- event-grain rows require a named downstream workflow,
- player damage done, healing, casts, resources, buffs, and generic raw event payloads should not be added without a specific fact/read-model need and a volume plan.

## Gold-Keyed Encounter Detail Boundary

Commit: `7a74cc3 Add gold-keyed encounter detail shell`

Task `#48` hardened the encounter detail boundary before rebuilding the full detail UI.

Added:

- route `/encounters/:id`, where `id` is `gold.dim_encounter.id`,
- `WeGoNext.Gold.EncounterDetail`, a gold/silver read model for the shell,
- `WeGoNext.Gold.EncounterIdentity`, an explicit bridge from transitional `public.encounters` plus `combat_log_files` to `gold.dim_encounter`,
- `WeGoNextWeb.EncounterLive.Show`,
- home-page encounter links for records that have a gold bridge.

The bridge uses the same identity as importer:

- `combat_log_files.head_sha256` plus `start_byte` when a source fingerprint exists,
- otherwise `source_file_path` plus `start_byte`.

`public.encounters` remains an operational/import catalog table. It supports the app's import and reset workflows, but new medallion analysis routes should not key on `public.encounters.id`.

The shell intentionally reads only gold/silver read models and does not call:

- legacy analyzers,
- analyzer JSON cache output,
- `public.mechanic_criteria`.

## Architectural Clarifications

The session clarified schema ownership:

- `public` may hold app infrastructure and operational state such as users, settings, combat-log file tracking, import progress, transitional encounter boundaries, and admin flags like `is_reset`.
- `silver` holds deterministic projections from combat logs.
- `gold` holds analytic dimensions, facts, and read models.
- `rules` holds authored mechanic business configuration.
- `source_data` holds external evidence and inferred candidates.

The important constraint is not that every table must live inside a medallion schema. The constraint is that medallion UI/read models must not treat public operational tables as the analytic source of truth.

## Verification

For `#47`:

```bash
MIX_ENV=test mix ecto.migrate
mix ecto.migrate
mix test test/we_go_next/silver/schema_test.exs test/we_go_next/silver/projector_test.exs test/we_go_next/silver/persistence_test.exs test/we_go_next/silver/round_trip_test.exs test/we_go_next/importer_test.exs
mix test
```

Focused result: `14 tests, 0 failures`.

Full result after `#47`: `5 features, 78 tests, 0 failures, 3 skipped`.

For `#48`:

```bash
mix test test/we_go_next/gold/encounter_identity_test.exs test/we_go_next_web/live/encounter_live_show_test.exs test/we_go_next_web/live/failure_live_test.exs
mix test
```

Focused result: `6 tests, 0 failures`.

Full result after `#48`: `5 features, 82 tests, 0 failures, 3 skipped`.

Browser verification:

- `/` rendered encounter rows with `/encounters/:gold_id` links where a gold bridge exists.
- legacy-only encounter rows remained plain text.
- `/encounters/1` rendered the medallion encounter detail shell keyed by `gold.dim_encounter.id`.

## Next Recommended Work

The immediate roadmap remains:

1. `#52 Add rules status and bootstrap UI`
2. `#53 Add medallion rebuild and recompute controls`
3. `#54 Surface data readiness diagnostics in failures UI`
4. `#51 Fence remaining legacy analyzers behind reference-only boundaries`
5. `#32 Build medallion encounter detail shell`

`#48` created the route/read-model contract that `#32` should build on.
