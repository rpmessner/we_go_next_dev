# 2026-07-19 — Factory roles buildout + provider/model split

Follow-on from the Gas City setup the same day. Built the four starting roles
and wired the operator's provider split: **Claude Fable 5 for reasoning roles,
Codex (gpt-5.6-sol) for build-out lanes.**

## Roles (all in `.gascity/`, all rig-scoped, all validated)

- **`wgn.triager`** — the spec gate. Labels ready beads `factory-ok` only when
  they carry a measurable done-condition, bounded scope, and (for medallion
  work) a defensible silver grain; otherwise `needs-spec` + a comment naming
  the gap. Max 5 beads/wake; never touches `proposal` beads; never edits
  descriptions. This label is the swarm throughput valve.
- **`wgn.backlog-polecat`** — the dispatcher. Picks exactly ONE highest-priority
  ready `factory-ok` bead per wake (skips claimed/in_progress/epics/proposals
  and beads with open workflows) and runs
  `gc sling <bead> --on quality-loop`. Never implements, labels, or closes
  gates. Empty dispatch is a valid outcome.
- **adversarial review** — not a new agent: a new `quality-loop` step targeting
  the stock `gc.implementation-reviewer` (which owns the claim protocol), with
  the repo-specific instructions in
  `.gascity/assets/workflows/quality-loop/adversarial-review.md`: refute-first
  (concrete failure scenarios), lenses = correctness → medallion boundaries →
  Elixir/OTP house rules → test faithfulness → parser/projector hot paths.
  Verdict `SHIP`/`REFUTE` posted as a bead comment — **advisory input to the
  human gate, never a substitute for it**.
- **`wgn.proposer`** — files ≤3 `proposal`-labeled beads per wake from
  VISION/ROADMAP/initiative docs + coverage audits + backlog gaps, each with
  the raid-lead question it answers and a done-condition sketch. Never
  promotes its own proposals — ratification stays human (`bd promote` /
  relabel is the operator's).

Pipeline is now: implement (codex) → `mix quality` exec check → evidence →
adversarial review (fable) → human gate bead → finalize. 8 compiled steps,
verified via `gc formula show`.

## Provider/model split

- `~/gc/city.toml`: `[providers.claude-fable]` (base builtin:claude,
  `option_defaults = { model = "fable-5" }`) and `[providers.codex-sol]`
  (base builtin:codex, `option_defaults = { model = "" }` — the "" Default
  choice suppresses gc's `--model gpt-5.5` pin so codex falls through to
  `~/.codex/config.toml` = **gpt-5.6-sol, high reasoning effort**; gc 1.3.5's
  codex enum predates Sol, so this is the schema-valid route).
- Rig-level `[[rigs.patches]]`: `implementation-worker` → codex-sol,
  `implementation-reviewer` → claude-fable. City `~/gc/pack.toml`:
  mayor → claude-fable.
- wgn agents (triager/polecat/proposer) set `provider = "claude-fable"`
  directly.

## Orders (`.gascity/orders/`, all `trigger = "manual"`)

`triage-backlog`, `backlog-dispatch`, `propose-features` — each an exec order
slinging a wake-nudge to its agent. Autonomous cadences are written in but
commented (2h cooldown / 45m cooldown / Monday-9am cron); switch after the
first supervised end-to-end run. Fire manually with
`command gc --city ~/gc order run <name>`.

## Gotchas captured

- Pack `[[patches.agent]]` cannot patch agents imported from another pack —
  cross-pack provider patches must be rig-level `[[rigs.patches]]` in
  city.toml.
- `AgentOverride`'s TOML key is **`agent = `**, not `name = `; and it matches
  the **unprefixed** pack agent name (`implementation-worker`, not
  `gc.implementation-worker` — the `gc.` import-key prefix is applied after
  patching). Note asymmetry: formula `run_target`s DO use the prefixed name.
- `[[rigs.patches]]` must sit lexically inside the `[[rigs]]` block (before
  any other top-level table).
- Exec orders cannot declare `pool` — the exec command names its own target.
- Qualified agent names for sling are `we_go_next/wgn.<name>`.
- `AgentOverride` has no `option_defaults` — model pinning for patched agents
  must ride a provider preset.

## Validation evidence

`gc lint .gascity` ok; `gc agent list` shows all 3 wgn agents + both patches
applied; `gc order list` shows the 3 manual orders under rig we_go_next;
`gc formula show quality-loop --rig we_go_next` compiles 8 steps with the
gate; `gc doctor`: 73 passed, 3 advisory warnings (stopped-city artifacts).

## First supervised run (operator)

1. `command gc --city ~/gc start` && `command gc --city ~/gc rig resume we_go_next`
2. Claim your in-flight bead: `bd update we-37 --claim` (branch work in tree!)
3. `command gc --city ~/gc order run triage-backlog` — review its labels
4. `command gc --city ~/gc order run backlog-dispatch` — expect it to pick a
   factory-ok bead (likely we-27/we-28 once triaged)
5. Watch in `mux start` factory window; at the end, review diff + evidence +
   adversarial verdict, close the gate bead, merge manually.
6. When comfortable: uncomment the cooldown/cron triggers in
   `.gascity/orders/*.toml`.
