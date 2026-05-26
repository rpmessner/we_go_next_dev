# WeGoNext

WeGoNext is a local-first WoW combat-log diagnostic tool for raid progression and Mythic+ review. It runs beside the game and turns combat logs into between-pull analysis: failures, deaths, missed interrupts, and eventually personal and group trends.

It is not a damage meter. WoW and Warcraft Logs already answer aggregate throughput questions. WeGoNext is focused on the next question: what happened, why it mattered, and what should change on the next pull.

## Current Architecture

The project is moving onto a medallion-style analytics backend:

```text
WoW combat logs
  -> Bronze operational catalog
  -> Silver encounter-grain projections
  -> Gold dimensions and facts
  -> Rules-backed LiveView read models
```

Current working pieces:

- Zig NIF combat-log parser for encounter boundary scanning and event parsing.
- Incremental import from live logs and Warcraft Logs archive files.
- Bronze provenance via `combat_log_files` and transitional `public.encounters`.
- Silver tables for damage, deaths, interrupts, debuffs, and player info.
- Gold dimensions for encounters, players, and mechanic criteria.
- `gold.fact_failure` for avoidable and missed-interrupt failures.
- Rules schema with draft/active/archived rulesets and promoted gold snapshots.
- DBM source-data ingestion groundwork for inferred mechanic candidates.
- LiveView pages for encounter import/listing, settings, and failures.

Legacy analyzer-cache pages and `public.mechanic_criteria` are no longer active architecture. New UI work should use silver/gold/rules read models.

## Quick Start

```bash
cd we_go_next
mix setup
mix ecto.setup
mix phx.server
```

Open `http://localhost:4000`.

Set your WoW logs directory in `/settings`, then import a log from `/`.

Typical WSL path:

```text
/mnt/e/World of Warcraft/_retail_/Logs
```

## Rules Bootstrap

Failures require an active ruleset and promoted gold criterion snapshots. Until the rules UI exists, use:

```bash
cd we_go_next
mix run -e 'alias WeGoNext.Rules; {:ok, %{ruleset: rs}} = Rules.seed_initial_rules(); {:ok, active} = Rules.activate_ruleset(rs); {:ok, _} = Rules.promote_ruleset_to_gold(active)'
mix wgn.rebuild_gold
```

## Rebuilds

Use the smallest rebuild that matches the change:

- Rules changed: promote rules, then `mix wgn.rebuild_gold`.
- Gold fact logic changed: `mix wgn.rebuild_gold`.
- Silver projection or parser logic changed: force reimport affected logs from the UI.

The gold rebuild boundary is `WeGoNext.Gold.RebuildEncounter`.

## Project Layout

```text
we_go_next_dev/
├── we_go_next/                  # Phoenix app
│   ├── lib/we_go_next/          # contexts, parser surface, medallion modules
│   ├── lib/we_go_next_web/      # LiveViews and components
│   ├── priv/native/             # Zig combat-log parser
│   └── priv/repo/migrations/    # public/silver/gold/rules/source_data migrations
├── docs/                        # active durable documentation
│   ├── sessions/                # immutable session logs
│   └── historical/              # archived plans and research
├── tools/                       # local extraction/reference tools
├── CLAUDE.md                    # durable AI-agent project context
└── AGENTS.md                    # agent instructions
```

## Tests

```bash
cd we_go_next
mix quality
mix test
mix test test/features/
mix credo --only warning
```

`mix quality` is the local CI gate. It checks formatting for active hand-written
Elixir files, treats compiler warnings as errors, runs Credo warning checks,
prepares the test database, and runs the test suite.

Feature tests use page objects from `test/support/pages/`.

## Docs

Start with [`docs/README.md`](docs/README.md).

Active docs:

- [`docs/VISION.md`](docs/VISION.md)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/OPERATIONS.md`](docs/OPERATIONS.md)
- [`docs/ROADMAP.md`](docs/ROADMAP.md)

Historical docs and research live in [`docs/historical/`](docs/historical/). Session notes live in [`docs/sessions/`](docs/sessions/).
