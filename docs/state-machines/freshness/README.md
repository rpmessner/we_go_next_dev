# Pull freshness

`WeGoNext.Freshness` is a pure classifier, not a lifecycle. Its ordered table applies to each stamp:

| Input | State |
|---|---|
| `-1` | `partial` |
| `nil` | `missing` |
| Current version | `current` |
| Anything else | `stale` |

Components: silver deaths, failure facts, wipe-cause facts, and document derivation.
The document's existing `derivation_version` remains its logic version. Schema versions retain their existing graceful-degradation contract.
A failure stamp belongs to the pull, not a fact row: zero rows can be current or stale.
Legacy pulls start unstamped; the migration does not infer freshness from existing facts.

## Rebuild consistency

`RebuildEncounter` holds a per-pull session advisory lock across two database commits:

1. Persist `failure_derivation_version = -1`.
2. In one transaction, rebuild both facts, stamp the pull, and write the document/index.

Failure rolls back step 2, leaving the partial marker. A file already written during the failed transaction can remain on disk. `Documents.stale?` checks the live dimension as well as document stamps, so that file cannot masquerade as current. Lookup uses the stable source encounter key, never a stored surrogate id that another database may reuse. Standalone documents without a matching dimension still use their own stamps.

A skipped failure builder or disabled document generation leaves the marker partial. Recover with a complete `RebuildEncounter.rebuild/2`, not a document-only rewrite. Low-level `FactFailure.rebuild_for_encounter/2` stamps successful failure derivation, including zero rows, in its own transaction.

## Model and tests

`Spec.tla` abstracts one serialized rebuild, with faults before and after file writes. It omits rule selection, silver projection, multiple documents/index concurrency, and low-level builders invoked outside the coordinator.

TLC checked 7 states and 10 steps: type safety, current implies consistent facts/document, visible partial failure, and no deadlock all hold. Terminal self-loops are hidden in `chart.mmd`.

`legacy.cfg` reproduces the old independent commits (8 states, 11 steps):

- `CurrentMeansConsistent`: start → build facts; current facts differ from the document.
- `FailureIsVisible`: start → build facts → failure; the disagreement is still marked current.

The index-write regression replays the legacy fault using a real filesystem error, checks rollback and live partial classification, then retries successfully. Classifier tests exhaust all 625 combinations of missing, partial, old, current, and future stamps.

From the repo root, use a new output directory for each run:

```sh
TLA2TOOLS=/tmp/claude-1000/statechart-tools/tla2tools.jar JAVA=/usr/bin/java \
  ~/.claude/skills/statechart/scripts/statechart \
  docs/state-machines/freshness/Spec.tla \
  --view docs/state-machines/freshness/view.ts --out /tmp/wgn-fresh-model-check
```

Add `--config docs/state-machines/freshness/legacy.cfg` to reproduce the violations (expected exit 1).
