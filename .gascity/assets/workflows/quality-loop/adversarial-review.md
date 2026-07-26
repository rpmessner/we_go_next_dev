Adversarially review the implementation for the target bead. Your job is to
**refute** the work, not to bless it: for each concern, name a concrete
failure scenario — specific inputs or state leading to a wrong output, crash,
or violated contract. A vague "consider improving X" is not a finding.

Find the target bead first, deterministically: this step bead's metadata
carries `gc.root_bead_id` — `bd show` that root, read its
`gc.input_convoy_id` metadata, then `bd show` that convoy; the bead the
convoy depends on (its tracked member) is the target bead. Its comments
carry the evidence and branch name. Do not guess the target from branch
names or step prose.

Read the repo root `AGENTS.md` first. Then review the feature branch diff for
the target bead (branch name is in the bead comments/evidence) against these
lenses, in order of severity:

1. **Correctness.** Does the change do what the bead's done-condition says,
   for real inputs? Would the stated evidence actually catch the failure
   modes you can construct?
2. **Medallion boundaries.** Silver stays deterministic and unopinionated
   (event-grain rows only for named downstream needs); gold facts only where
   the silver grain is defensible; no reintroduction of legacy surfaces
   (`public.mechanic_criteria`, analyzer-cache); fact-semantic changes must
   bump the derivation stamp so stale rows are detectable; rules/promotion
   plumbing stays hidden behind sync/rebuild commands.
3. **Elixir/OTP/Ecto house rules.** Zero compile warnings; no
   `String.to_atom` on external input; no `Process.sleep` in tests (use
   `start_supervised!` + monitors/synchronous calls); no new dep a
   transitive one already provides; changesets validate at the boundary;
   no ETS caching where a cheap rescan suffices.
4. **Test faithfulness.** Each test at the lowest layer that can faithfully
   assert the behavior (unit → DataCase → ConnCase/LiveViewTest → Wallaby);
   Wallaby features must use page objects; tests must assert the
   rebuild/read-model output, not internals; no fake-outs of behavior only
   the full stack exercises.
5. **Hot paths.** Parser/LogReader and silver projectors are the measured
   hot paths — flag O(n²) scans, per-event allocations, or unbatched DB
   writes there; demand a benchmark for anything plausibly regressive.

Output — a single comment on the **target bead** titled `## Adversarial
review`, containing:

- findings ranked most-severe first, each with its concrete failure
  scenario and file:line;
- explicitly, anything you tried to refute and could not (so the operator
  knows what was checked, not just what failed);
- a final line `Verdict: SHIP` or `Verdict: REFUTE — <one-line reason>`.

Your verdict is **advisory input to the human gate** — you do not close or
open gate beads, you do not edit code, you do not re-run the implementation,
and you do not merge. If the diff or evidence is missing/unfindable, that is
itself a REFUTE finding.
