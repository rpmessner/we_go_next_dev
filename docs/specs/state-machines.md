# State machines under we_go_next's stateful code

Status: superseded by epic `we-g18` and [`../state-machines/inventory.md`](../state-machines/inventory.md). The 2026-10-18 inventory below is historical; mirror/upload machinery was removed in we-g18.2, not modeled.

## Idea

Put every stateful feature in we_go_next on a declared, compile-checked state machine, the way foreman does: states, events, guards and effects declared as data, a pure step, generated diagrams held to goldens, and the behaviour hung off that skeleton.

## Inventory (2026-10-18)

No state machines today; state lives in process maps and string fields.

| Area | Where | State today |
|---|---|---|
| Combat-log watching | FileWatcher GenServer (562 lines) | polling, sync-in-flight ref, timer, current file, directory in a map |
| Imports | ImportWorker | per-user status :importing, task_ref, progress; task results and DOWN handled ad hoc |
| Warehouse rebuilds | wgn.rebuild_gold, rebuild_documents, sync_raid_rules, Gold.RebuildEncounter | rebuild/sync runs; stale vs fresh status the product wants explained in the UI |
| UI | 8 LiveViews: encounter show (1,885 lines), encounter index (10 events), log index (7), settings (7) | ad hoc assigns and flags |

## Decided

- The FSM DSL is copied in from foreman's `Foreman.Fsm` (user, 2026-10-18: copy, not a shared library).

## Proposed order

1. Copy the DSL in, with its compile checks, docs generation and golden tests.
2. External conversations and resource lifecycles first: import lifecycle and file watcher.
3. Warehouse freshness and rebuilds (fresh, stale, rebuilding, failed) per encounter or layer, driving the UI's empty/stale explanations.
4. Stateful UI: encounter index, log index, settings, encounter show; URL-derived filters stay plain data.
5. A binding review rule in AGENTS.md: new stateful features sit on declared machines.

## Questions for the spec

- Granularity of the freshness machine (per encounter, per layer, per log).
- Order relative to the user's in-flight branch work (codex/we-vw1-shared-cooldown).
