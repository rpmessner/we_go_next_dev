---
name: promote-analysis
description: Use when promoting a repeated, operator-confirmed Analysis session method into deterministic medallion output or a Tool in we_go_next.
---

# Promote an analysis method

1. **Find the confirmed method.** Read recorded Analysis session exports, the Retro, reference answers and operator verdicts. Separate the confirmed operation from the AI's causal guesses. Done when the ticket cites the repeated method, accepted answers, corrections and a must-not-repeat case.

2. **Define the rules and gold output.** Use `GLOSSARY.md` vocabulary. Write a spec naming grain, inputs, ordering, thresholds, unknowns, exclusions, derivation stamp and observable expected rows. Resolve product choices with the operator before implementation. Done when the operator approves the spec and every acceptance check has a planned test or script.

3. **Implement the deterministic path.** Follow existing medallion boundaries. Reuse silver observations, build stamped gold rows, make rebuilds idempotent, and expose a bounded, session-scoped Tool with pull/time evidence. Test empty and stale states as well as populated rows. Done when the production rebuild and Tool pass their integration tests in an isolated test database.

4. **Run all four verification checks.** Compare against (a) the full applicable reference evidence, (b) the external metric, such as Warcraft Logs, (c) verdict-correct AI answers plus operator overrides, and (d) model-call and cost measurements. For each verifier, run a deliberately broken production variant, observe a behavioral failure, restore the source, and rerun successfully. Record every external mismatch and reason rather than silently aliasing data. Done when each check has reproducible red/green evidence; unavailable live checks remain explicitly pending.

5. **Bind the built-in question.** Register its deterministic Tool in `Analysis.BuiltInQuestions` and the MCP Tool registry. Exercise the direct binding and MCP with no model, checking evidence and recorded Tool calls. Done when tests demonstrate the built-in uses gold, respects the session log, and makes no model calls.

6. **Record before/after cost.** Preserve the old baseline, rerun only the approved question subset, and record model requests, Tool calls, cost and factual agreement in the reference-set index. Distinguish a free deterministic test from a paid baseline rerun. When the operator reserves the rerun for the coordinator, hand off the exact commands and leave that measurement pending. Done when measurements are recorded or the outstanding run has a named owner and no completion claim.

## First promotion

The wipe-cause worked example is `docs/specs/promotion-wipe-cause.md` (we-sfg.1).
Its repeated Q1/Q4 operation became `Gold.FactWipeCause` and the `wipe_cause` Tool.
`scripts/verify_wipe_cause_mutations.py` proves the reference, WCL, AI-agreement and deterministic-cost verifiers reject broken variants. The reference-set index records external differences and the coordinator-owned baseline rerun.
