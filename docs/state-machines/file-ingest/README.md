# Per-file ingest

`FileIngest.Lifecycle` declares the transition table. `FileIngest` runs its claim and release effects around a bounded writer task. Importer, ImportWorker, and FileWatcher use this boundary.

## Checked model

TLC explores 307 states and 1,300 steps. The monotonic-progress, single-writer, failed-pull, replay-bound, replay-recovery, and terminal-or-timeout rules hold. No deadlocks or counterexamples were found. The chart shows five file states and twelve arrows. It hides pull status, replay progress, and deadline ticks; 694 steps stay within a displayed state.

The model bounds progress at two completed boundaries and the deadline at two ticks. `replay = 3` represents no replay cursor. It abstracts database locking, bytes, multiple pulls, task scheduling, and UI delivery. Deadline fairness assumes the runtime and PostgreSQL can execute. Source truncation and force-reimport deletion policy are outside the model.

```sh
TLA2TOOLS=/tmp/claude-1000/statechart-tools/tla2tools.jar JAVA=/usr/bin/java \
  ~/.claude/skills/statechart/scripts/statechart \
  docs/state-machines/file-ingest/FileIngest.tla \
  --view docs/state-machines/file-ingest/view.ts --out /tmp/file-ingest-check
```

`implementation.mmd` and `implementation-matrix.md` come from the executable table. The lifecycle test checks both artifacts and 40,000 seeded event transitions. Context tests check the actual database and task behavior.

## Runtime contract

- `FileIngest.start_sync(file)` returns a monitored `Task`. FileWatcher consumes `{task.ref, result}` and `:DOWN` as before.
- `Importer.sync_log(file_or_path)` blocks until completion or timeout. Success is `{:ok, %{file: file, new_encounters: count, medallion_results: results}}`. Failure is `{:error, reason}`. `:ingest_busy` permits a later retry.
- `Importer.sync_needed?(fresh_file)` includes pending or failed medallion work, even when the file has not grown.
- `FileIngest.run(file, event, callback, opts)` claims one writer. Supported start events are `:import`, `:sync`, and `:reimport`. The callback receives a freshly loaded file under the lock.
- A local process lock prevents duplicate tasks on one node. A pinned PostgreSQL session advisory lock, in namespace `18003`, excludes other nodes. Task death closes the connection. A guardian kills a writer whose caller dies. The default deadline is five minutes; `:timeout` overrides it for imports.
- The adapter does not wrap the whole import in a transaction. Medallion builders own their transactions. Bronze boundaries and their `pending` markers must survive a later builder failure.

`import_operations` stores a receipt per user. The import task writes and broadcasts its result independently of ImportWorker. Restart recovery monitors surviving tasks and re-arms stored deadlines. An orphaned operation expires by its deadline. Tokens prevent a late result from overwriting a newer or timed-out receipt.

`encounters.medallion_state` is `pending`, `failed`, or `complete`. Existing rows migrate to `pending` because historical failures were not recorded. A later sync rebuilds them once. A failed step records its error; an interrupted step remains pending.

`last_parsed_byte` is a high-water mark. Force replay uses `reparse_from_byte` instead of resetting that mark. Replay preparation atomically deletes the public boundaries and records the replay cursor. A later sync resumes an interrupted replay. If the source shrinks below the old high-water mark, the cursor remains set rather than skipping the shortened source.

## Unresolved product decision

Force-reimport retains its existing public-only deletion scope. It reuses matching gold dimensions and rebuilds silver and gold for pulls still present in the source. It does not remove warehouse rows or documents for pulls removed from the source. Choosing between replay, warehouse replacement, and a medallion-only rebuild requires an operator decision. This change does not choose a new deletion policy.

FileWatcher's watch, track, rotate, boot-restore, idle-expiry, and backoff behavior remains owned by we-g18.7.
