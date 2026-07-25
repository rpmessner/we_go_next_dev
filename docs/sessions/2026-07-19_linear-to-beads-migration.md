# 2026-07-19 — Linear → beads migration (hard cutover)

Moved issue tracking from Linear (workspace `we-go-next`, team `WE`) into in-repo
beads (`bd`), matching the ui-o-matic cutover earlier the same day. First step
toward incorporating Gas Town (`gt`).

## What was done

- `bd init -p we --skip-agents` at the repo root (Dolt-backed, embedded engine).
  `--skip-agents` because `AGENTS.md` is the curated canonical file here.
  Config: `export.auto: true`, `sync.remote: git+https://github.com/rpmessner/we_go_next_dev.git`
  (same shape as ui-o-matic). bd init auto-committed its scaffold
  (`7f9413b`, beads files only) on `rpmessner/defensives-and-consumables`.
- Exported all 37 WE issues via `scripts/linear.sh` (GraphQL; the comments/relations
  query had to be split — Linear caps query complexity at 10k) and imported them as
  `we-5`…`we-41` (ids preserved 1:1 from `WE-###`). Each bead carries:
  - Linear URL as `external_ref`,
  - migration provenance + Linear status/priority/project/branch in `notes`,
  - all Linear comments (44 total, including agentic closeout blocks) as bd comments,
  - status map Done/Canceled→closed (canceled also labeled `canceled`),
    In Progress→in_progress, Backlog→open; priority map Urgent→0, High→1,
    Medium/None→2, Low→3.
- Created 8 initiative epics `we-i0`…`we-i7` (one per Linear project / initiative
  doc): `we-i0` Public Gold Mirror (closed, superseded), `we-i1` Real-Data Failure
  Loop (closed, absorbed), `we-i2`…`we-i7` for initiatives 2–7. All issues linked
  to their epic via parent-child deps; the WE-37→38/39→40→41 `blocks` chain from
  Linear carried over, so `bd ready` correctly surfaces `we-37` as the P0 next item.
- Docs cutover: `AGENTS.md` §Project Tracking rewritten for beads (Linear = frozen
  archive, read-only via `scripts/linear.sh`); `docs/ROADMAP.md`,
  `docs/initiatives/README.md` + all 7 initiative doc status lines,
  `ENCOUNTER_DOCUMENTS_DESIGN.md` phasing header, and `PUBLIC_MIRROR_DESIGN.md`
  tracking line now point at `we-i*` epics / `we-##` beads.

## Resulting state

45 beads: 26 closed, 14 open, 5 in progress, 4 blocked, 10 ready.
Verified via `bd status`, `bd ready`, `bd children we-i7`, `bd graph we-41`,
`bd comments we-34` (agentic provenance intact).

## Gotchas captured

- Linear GraphQL complexity cap (10k) forces splitting issue-body and
  comments/relations queries; keep `comments(first: 10)` with `issues(first: 50)`.
- bd JSONL import: a `blocks` dependency row must live on the *dependent* issue's
  record (`{issue_id: dependent, depends_on_id: blocker, type: "blocks"}`).
- `bd init` auto-commits its scaffold to git — be aware of which branch you're on.

## Follow-ups

- Sessions in this repo still reference `WE-###`; those map 1:1 to `we-###` and
  session logs are immutable — no rewrite.
- Linear team WE left as-is (frozen archive); no issues deleted or archived there.
- Gas Town integration itself (enrolling this repo in `~/gt`) is a future step.
