# Live log watch

`FileWatcher` runs `FileWatchLifecycle` on `:gen_statem`. The table, generated
[matrix](implementation-matrix.md), and [implementation chart](implementation.mmd)
include explicit ignored pairs. [chart.mmd](chart.mmd) is the TLC projection.

## Model checks

`Watch.tla` bounds the model to two ordered files and two quiet ticks (the idle
deadline). Correct mode reaches 38 states / 233 edges. Agreement, NeverRevert,
Restored, AutoOff and NoDeadlock hold.

`Legacy.cfg` enables unsafe reply acceptance. TLC finds both Agreement and
NeverRevert violations on the same shortest path:

0. idle
1. watch A
2. start syncing A
3. watch B
4. A's reply overwrites B

The regression test replays that path. [legacy.mmd](legacy.mmd) marks the violations.
The model abstracts task references into a pending file; the implementation uses
both reference identity and watch generations. Backoff durations, database IO
failures, file contents and display selection are not modeled. `Done` stutters
are hidden; same-label transitions are collapsed.

## Runtime boundaries

- Importing/viewing selects the displayed log and requests watching. Existing
  newest-live-log eligibility remains; archives and older logs can still display.
- Watch commands persist synchronously. Only one log is watched by this singleton.
  Re-enabling uses `force_change`: a bulk flag reset makes Ecto's loaded value stale.
- Boot restores the durably enabled live file, even if a newer inactive row exists.
  Directory-only discovery has no durable row; it is armed by the dashboard.
- Quiet time starts at watch/boot, not the file's historical mtime. Polls and the
  idle deadline check `{size, mtime, ctime}`; appends renew the clock. Re-viewing the
  same file does not. Filesystem timestamp resolution can miss same-size rewrites
  within one second; WoW's append-only logs change size.
- Default idle timeout: `:file_watcher_idle_timeout_ms = 1_800_000`. Failed syncs,
  task exits, busy claims and pending medallion failures back off exponentially,
  capped at five minutes. Idle expiry remains active during sync/backoff.

## Regenerate

```sh
TLA2TOOLS=/tmp/claude-1000/statechart-tools/tla2tools.jar JAVA=/usr/bin/java \
  ~/.claude/skills/statechart/scripts/statechart \
  docs/state-machines/watch/Watch.tla --view docs/state-machines/watch/view.ts \
  --out /tmp/watch-check-new
```

Add `--config docs/state-machines/watch/Legacy.cfg` for the unsafe model (exit 1
is expected). Pure randomized-prefix tests assert the model rules; adapter tests
cover boot, persistence, timers, stale results, rotation and retry scheduling.
