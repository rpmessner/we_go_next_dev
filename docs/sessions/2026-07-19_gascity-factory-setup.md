# 2026-07-19 — Gas City factory setup (gc, rig, pack, airmux)

Follow-on from the Linear→beads migration the same day. Decision: adopt
**Gas City** (`gastownhall/gascity`, the primitive-first successor to Gas Town)
as the factory layer, keep we_go_next pure, tailor via an in-repo pack.
`~/gt` (Gas Town) left untouched as legacy.

## What was done

- Installed `gc` v1.3.5 via `go install github.com/gastownhall/gascity/cmd/gc@v1.3.5`
  (asdf golang shim, same as `bd`/`gt`).
- `gc init --template gascity --providers claude --no-start ~/gc` — new city at
  `~/gc`, default gascity roles pack imported, nothing auto-started.
- `gc rig add --adopt --start-suspended --name we_go_next --prefix we <repo>` —
  repo adopted as a suspended rig (agents won't spawn until `gc rig resume`).
- Authored the repo-tailored pack at **`.gascity/`** (versioned with the app):
  - `formulas/quality-loop.formula.toml` — implement → exec check
    (`.gascity/checks/quality.sh` = `mix quality`, 30m timeout) → evidence
    comment → **human gate bead** (`[steps.gate] type = "human"`; the approve
    step stays blocked until the operator closes the gate bead) → finalize.
    The factory never merges; merging stays an operator action after the gate.
  - Wired into the city via `[rigs.imports.wgn]` in `~/gc/city.toml`.
  - Verified: `gc lint .gascity` ok; `gc formula show quality-loop --rig
    we_go_next` compiles 7 steps with the synthesized gate bead.
- Added **`.airmux.yml`** — `mux start` from the repo root builds tmux session
  `we_go_next`: window *factory* (mayor chat pane, `gc status` watch, `bd ready`
  watch, `gc events --follow` with retry loop, control shell) + window *vim*
  (nvim). Verified live: session builds, status/ready panes render, mayor pane
  materializes a live chat session.

## Gotchas captured

- **`gc rig add --adopt` switched beads storage from embedded Dolt to the
  city-managed Dolt server WITHOUT migrating data** — `bd status` dropped to 0
  issues. Recovered by re-running `bd import` of the migration JSONL (45 beads
  verified back: 26 closed / 4 blocked / 10 ready). The old embedded data is
  still at `.beads/embeddeddolt/`. After any rig adoption, check `bd status`.
- rig add also set `export.auto: false`, `backup.enabled: false`,
  `dolt.disable-event-flush: true` in `.beads/config.yaml` (city policy); a
  manual `bd export -o .beads/issues.jsonl` snapshot was taken after reimport.
- `--adopt` requires `issue_prefix` (underscore spelling) as an explicit key in
  `.beads/config.yaml`; bd itself doesn't write it (`bd config set issue-prefix`
  refuses — rename-only). Added by hand.
- bd's init-safety guard blocks gc's internal `bd init` while `sync.remote` is
  configured but never pushed. Workaround: `bd config unset sync.remote`, rig
  add, then restore. **First `bd dolt push` to origin is still pending** (the
  remote has no Dolt refs yet) — operator action.
- **The interactive-zsh alias `gc` (= `git commit --verbose`) shadows the Gas
  City CLI** — use `command gc` (or unalias). All `.airmux.yml` panes account
  for this; `watch` panes are immune (watch execs via sh).
- gc commands run from the repo need `--city /home/rpmessner/gc` — the repo is
  a rig; city discovery only walks *up* from cwd.
- The mayor chat session runs the claude provider with **bypass permissions**
  by default (gc builtin provider config) — acceptable while the rig is
  suspended and merges are gate-protected, but worth revisiting before
  autonomous work.

## Current state / next steps

City registered but **stopped**; rig **suspended**; no agent has done any work.
To go live (operator, deliberately):

1. `command gc --city ~/gc start`
2. `command gc --city ~/gc rig resume we_go_next`
3. Dogfood: sling `we-37` through `quality-loop`, watch in the mux factory
   window, review diff + evidence, close the gate bead to approve, merge
   manually.

Also pending: first `bd dolt push`; decide the agent-hub (`utils/agent-hub`)
question — gascity overlaps its kernel charter (separate decision, deliberately
not made here).
