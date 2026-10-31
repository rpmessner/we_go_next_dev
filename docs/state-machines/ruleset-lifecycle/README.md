# Ruleset status

`RulesetLifecycle.tla` models two rulesets and atomic active replacement. The implementation is `Rules.RulesetLifecycle`; `Rules` adapts its effects to database writes.

- Sync never changes status.
- Draft can become active or archived.
- Activating a replacement archives the previous active ruleset in the same transaction.
- Standalone active archival and resetting active/archived to draft are invalid.
- Repeated activation or archival is idempotent; repeated activation preserves `activated_at`.
- Transitions re-read persisted state under a transaction-scoped advisory lock, rather than trusting a caller's stale struct.

Archived → active remains supported, as before. Explicit promotion of draft rulesets also remains supported. Removing either behavior needs an operator decision; this ticket does not silently change them. The model permits zero active rulesets before the first activation, but never loses the active ruleset afterward.

TLC reaches 8 states / 38 steps. `AtMostOneActive`, `NeverLoseActive`, `NoResetToDraft`, `TypeOK` and `NoDeadlock` hold. The chart hides only unchanged displayed states (including rejected requests). Database availability, direct SQL writes outside `Rules`, rule contents and concurrent commands are outside the model.

Random two-ruleset sequences replay these properties through the pure table. Integration tests exercise the database adapter, including stale structs and rollback-safe replacement. Golden table artifacts are checked against `matrix/0` and `diagram/0`.

Regenerate from the repo root into a fresh directory:

```sh
TLA2TOOLS=/tmp/claude-1000/statechart-tools/tla2tools.jar JAVA=/usr/bin/java \
  ~/.claude/skills/statechart/scripts/statechart \
  docs/state-machines/ruleset-lifecycle/RulesetLifecycle.tla \
  --view docs/state-machines/ruleset-lifecycle/view.ts --out /tmp/ruleset-lifecycle-new
```
