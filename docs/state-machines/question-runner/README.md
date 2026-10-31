# Question runner

`QuestionLifecycle.tla` extends the original question lifecycle with a runner that is up, down, or lost. The old `docs/ai-analysis/statecharts/question-lifecycle/` model/chart paths are compatibility symlinks here. The generated implementation matrix stays beside the lifecycle documentation.

- Terminal runners stop only after an outstanding Tool result is appended.
- Retry, Continue, and verdict events restart from the stored snapshot, without adding another initial user message.
- Boot recovery changes interrupted thinking/calling_tool/writing questions to failed. Retry is explicit; boot never calls the model.
- Recovery records an interrupted Tool as an error with unknown outcome, unless its result is already present. Cancelled/limited questions keep their state.

[TLC report](tlc-report.md): 271 states, 669 steps; all six invariants and NoDeadlock hold. [Chart](chart.mmd), [SVG](chart.svg). The view hides only Done stutters; same-label steps are also omitted from the drawing.

The model abstracts database writes as atomic and counts completed model turns, not failed HTTP attempts or dollars. It does not model provider bodies, stream deltas, built-in computation crashes, database outages, or simultaneous commands. Integration tests inject failed writes and verify transaction rollback. Property tests check the lifecycle rules, snapshot round trips, and recovery without paid effects.

Use `Registry.whereis_name/1` for runner discovery. `Registry.lookup/2` can return a dead pid until the Registry partition handles its exit. A deterministic test holds that cleanup and verifies on-demand restart.

Regenerate from the repo root, using a fresh output directory:

```sh
TLA2TOOLS=/tmp/claude-1000/statechart-tools/tla2tools.jar JAVA=/usr/bin/java \
  ~/.claude/skills/statechart/scripts/statechart \
  docs/state-machines/question-runner/QuestionLifecycle.tla \
  --view docs/state-machines/question-runner/view.ts \
  --out /tmp/question-runner-new
```

Copy the new chart/report here. Render `chart.mmd` with Pele 1.9.0 using the statechart skill's render instructions.
