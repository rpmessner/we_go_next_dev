# Stateful feature inventory (2026-10-31)

Input to the state machine refactor pass. Each stateful feature should end up as an explicit transition table: from, event, guard, to and effects, with a pure `step`, built on `WeGoNext.StateTable`. See the `principles` skill's state-machine-skeleton. The inventory comes from a read-only sweep of the app. Items marked **confirmed** were checked against the code by the coordinator; the rest are leads to reproduce before fixing.

Already a machine: `Analysis.QuestionLifecycle`, built on `WeGoNext.StateTable`.

## Ranked by likely bug yield

### 1. Ruleset status and the sync flow (risk high; pure table)

States: `draft`, `active`, `archived`. Set in `Rules.activate_ruleset`, `archive_ruleset` and the seed path. Callers are the mix tasks only.

- **Confirmed:** re-seeding an existing ruleset writes `status: "draft"` by default, so `mix we_go_next.seed_rules`, or `sync_raid_rules` without `--activate`, demotes the active ruleset. It keeps its `activated_at`. Rebuilds then skip with `active_ruleset_not_found` and leave old facts in place.
- None of these transitions are guarded: archived → draft, archived → active, or archiving the active ruleset, which leaves none active.
- Promote can run without activate.
- A retired criterion's gold snapshot is only switched off at promote time.
- Seed, activate, promote and rebuild each run in their own transaction. `rebuild_all` halts on the first error without recording progress.

### 2. Mirror upload outbox (removed in we-g18.2)

The operator chose removal, not a machine. The following findings describe the
retired implementation; no upload lifecycle remains to model.

Former states: `pending`, `stale`, `error`, `published`. Enqueued from the gold rebuild, raid nights, the encounter page's Upload button and the smoke task. Drained by `UploadWorker`, `drain_once`, the smoke task and the mix tasks.

- **Lost update:** no claim or lock. If an enqueue sets a row `stale` while that row is mid-publish, the publish overwrites it with `published`, and the newer document is never uploaded.
- **No in-flight state:** two drainers can publish the same row.
- **Publish-off isn't honoured:** turning `publish_enabled` off doesn't cancel queued rows, and the Upload button on the encounter page has no publish gate.
- **No retry policy:** `error` rows retry every 5 s forever; `attempt_count` is never used.
- **Crash on a hung put:** `Task.async_stream` uses `on_timeout: :exit`, so one hung R2 upload crashes the worker.

### 3. Live log watch and sync: `FileWatcher` (risk high; `:gen_statem`, poll timeout)

Implied states: idle, watching a directory, tracking a file, syncing, rotating, plus a polling-off mode. The `watch_enabled` flag is written from three LiveViews, `claim_watch`, and the `EncounterStore` import/load helpers.

- **Switching mid-sync reverts:** switching to log B while log A is syncing lets A's result reset the tracked file back to A.
- **Not restored on boot:** `watch_enabled` isn't restored when the app starts. The UI still says "watching", but new pulls are never synced.
- **Viewing re-enables watch:** loading or importing a log calls `FileWatcher.watch`, silently undoing "watch off".
- **DB and process can disagree:** the flag is written to the database and the GenServer is updated by cast, so the two can diverge.
- **One field, two meanings:** "current log" (what a page shows) and "watched log" are the same field.
- **No backoff:** a failing sync re-polls every 5 s.

### 4. Import pipeline and per-file parse progress (risk high; one per-file machine with a timeout)

Covers `Importer`, `ImportWorker` and `combat_log_files.last_parsed_byte`.

- **Failed medallion steps are lost:** if silver or gold fails for an inserted encounter, the failure is only logged. The byte offset has already moved past it, so it is never retried.
- **Two writers to `last_parsed_byte`:** `ImportWorker` and the `FileWatcher` sync both write it unconditionally, so progress can go backwards.
- **UI stuck loading:** `ImportWorker` state isn't durable. A restart loses the completion message, and the LiveViews stay loading forever.
- **Watch flag survives archiving:** the reconciler moves a live file to the archive without clearing `watch_enabled`.
- **Uneven force-reimport:** it deletes `public.encounters` but keeps dim, silver and gold rows.
- **Dead state:** `is_complete` is never set true, and the `:saving` progress state is never broadcast.

### 5. Encounter list and Logs pages (risk medium; small LiveView tables)

- **Confirmed:** the admin gear menu crashes. `toggle_menu` and `toggle_reset` call `String.to_integer` on the record id, which is now a document hash key.
- **Dead reset grouping:** the reset toggle and grouping do nothing, because `is_reset` is hard-coded false for document records.
- **Contradictory flags:** `loading`, `import_progress` and `error` are independent and can contradict each other, and `loading` never times out.
- **Duplicated toggle:** the watch toggle is written three times (Encounter list, Logs, Settings).

### 6. `QuestionRunner` adapter (risk medium; the table is done)

- **Process leak:** the runner never stops after a terminal state.
- **Orphaned rows:** there is no recovery at boot, so questions left `thinking`, `calling_tool` or `writing` stay orphaned after a restart.
- **Crashes on a failed write:** `Repo.update!` inside a transition crashes the runner.
- **Verdicts skip the machine:** the MCP `record_verdict` writes a verdict without sending the machine its event.
- A Tool result arriving after Cancel is appended. That is by design per the TLA+ model ("every Tool call is recorded").

### 7. Freshness and staleness classification (risk medium; one pure classifier)

- **Four classifiers disagree:** `Documents.stale?` (which ignores the wipe-cause version), `ReadModel.freshness`, the `wipe_cause` Tool and `FailureSummary`.
- **Missing failure stamp:** there's no per-encounter stamp for failure facts.
- **Partial rebuilds:** `RebuildEncounter`'s steps run in separate transactions, so facts and the document can disagree.

### 8. Encounter detail, Settings and the public viewer (risk low; small tables)

- **Removed in we-g18.2 — upload state mapped twice:** the encounter page maps the raw upload state again and invents a "not_queued" pseudo-state.
- **Stale Settings banner:** Settings' "watching" banner is a snapshot taken at mount.
- **Removed in we-g18.2 — disable doesn't reach open pages:** turning a public report off only takes effect in the plug, so already-connected viewers keep the page.
- **Removed in we-g18.2 — duplicated classification:** the public viewer repeats the document-state classification.

## Dead or legacy code (don't model it)

- **Never set or never called:** `CombatLogFile.is_complete` and its helpers, `Rules.archive_ruleset`, `Rules.operations_status`, `ImportWorker.active_imports`, `FileWatcher.sync_now`, `FileWatcher.watched_directory` and `EncounterStore.sync_log`.
- **Never broadcast:** the `:saving` progress branches.
- **No effect on document records:** the reset grouping.
- **Legacy, per AGENTS.md:** `analyzers/*`, `encounter.ex`, `MythicPlusRun` and `TrashPull`.

Remove dead state only inside the machine ticket that owns its feature. Don't do separate cleanup.

## Operator decisions (foreman, 2026-10-31)

- **Breakdown:** published as proposed (epic below).
- **Watching:** importing or viewing a log turns watching on by default. While the app is running, watching turns itself off when the log hasn't been written to for about 20–30 minutes; the configurable default is 30. That is a timer state in the FileWatcher machine. Watching is restored at boot if it was on.
- **Uploading:** removed. The mirror app has been shut down as too expensive; publishing may return later as a static HTML/JS artifact on a free or cheap host. Item 2 becomes a removal, not a machine: the outbox, upload worker, `publish_enabled`, the public viewer and ingest all go. `Mirror.Keys` stays, because gold uses it for `criterion_key` and `source_encounter_key`.
