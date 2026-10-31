# Ruleset sync flow

`RulesetFlow.tla` checks the staged operation implemented by `Rules.SyncFlow` and the adapter in `Rules.sync_raid_mechanics/2`. The [status machine](../ruleset-lifecycle/README.md) owns activation and archival.

## Contract

- Sync preserves an existing ruleset's status. Seed payload status applies only on creation.
- `--rebuild` implies activation and promotion, in that order. Other flags retain their existing opt-in behavior.
- Success returns `completed`, plus the existing `ruleset`, `criteria`, `promoted` and `rebuild` fields.
- Failure returns `stage`, `completed`, `reason` and `result` (the successful stages' output). Earlier stages stay committed. The CLI names the failed stage and committed stages.
- Rebuild uses the selected ruleset ID, not a fresh lookup of whichever ruleset is active later.
- Batch rebuild failures include `completed_encounter_ids`, the failed `encounter_id`, `remaining_encounter_ids` and successful-prefix `totals`. A failed encounter can itself have partial writes: wipe-cause, failure facts and document generation are separate operations. Retry the same command after fixing the cause.

This is one command with ordered, separately committed stages, not one all-or-nothing transaction. Progress is returned to the caller; it is not a durable job/checkpoint system.

## TLC evidence

The fixed model reaches 118 states / 169 steps. `AtMostOneActive`, `SyncNeverDemotes`, `RebuildAfterPromotion`, `FailureIsExplicit`, `CompletedPrefix` and `NoDeadlock` hold.

`Legacy.cfg` enables the old default-to-draft write and restricts the initial state to an active ruleset with no optional flags. TLC finds `SyncNeverDemotes` broken in one step:

0. Active ruleset, before sync.
1. Re-seed writes draft; the command finishes without activation.

The CLI regression in `test/mix/tasks/we_go_next_seed_rules_test.exs` replays this path. See [legacy chart](legacy/chart.mmd) and [TLC report](legacy/report.md).

The chart hides only steps staying in the same displayed state. The model abstracts criteria/fact contents, SQL failures as nondeterministic failed stages, filesystem writes, crashes and concurrent commands. Lifecycle writes are serialized by a transaction-scoped advisory lock; the whole multi-stage command is not globally locked. Random-prefix tests assert the model's rules for every flag combination; integration tests cover repeated rebuilds, catalog retirement and snapshot reuse.

## Regenerate

From the repo root (use a fresh output directory):

```sh
TLA2TOOLS=/tmp/claude-1000/statechart-tools/tla2tools.jar JAVA=/usr/bin/java \
  ~/.claude/skills/statechart/scripts/statechart \
  docs/state-machines/ruleset-flow/RulesetFlow.tla \
  --view docs/state-machines/ruleset-flow/view.ts --out /tmp/ruleset-flow-new
```

For the bug, add `--config docs/state-machines/ruleset-flow/Legacy.cfg`, use `legacy-view.ts` and a different output directory. Exit 1 is expected for that counterexample.

`implementation-matrix.md` and `implementation.mmd` come from `Rules.SyncFlow.matrix/0` and `diagram/0`; tests compare them byte-for-byte.
