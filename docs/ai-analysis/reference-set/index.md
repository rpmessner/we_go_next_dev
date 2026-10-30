# Sept 6 phase-1 reference set

Status: revision 2. After the we-6l9 Feign Death fix and the dev rebuild, Q1, Q2, Q4, Q5, Q6, Q10, Q11 and Q12 were recomputed and rewritten. The operator accepted revision 2 on 2026-10-30 (foreman decision on we-xf4.8). Q3, Q7, Q8 and Q9 had no evidence change and stay as accepted. The 2026-10-29 baseline was graded against revision 1 (commit bf6b6be); see its overrides below.

Log `30`, `Archive-WoWCombatLog-090626_103607.txt`. Evidence uses the existing imported silver and gold snapshot plus bronze byte ranges. Query origin is the worktree base `f3b06f29ce314dfa34b372343c6069d4ecb76383`.

| Question | Reference | Concrete choice |
|---|---|---|
| q01 | [Why did Sszorak pull N wipe: what was the first thing that went wrong?](q01.md) | Sszorak pull 5, gold pull 440. It is the longest Sszorak wipe and has the most death events. |
| q02 | [Were we improving across the Sszorak pulls, and on which mechanics?](q02.md) | All Sszorak pulls in log 30, gold pulls 436 through 444, including resets. |
| q03 | [What changed between our last Twin Fangs wipe and the kill?](q03.md) | The last Twin Fangs wipe (pull 7, gold 451) and the kill (pull 8, gold 452). |
| q04 | [Who died first on pull N, to what, and was it avoidable?](q04.md) | Sszorak pull 5, gold pull 440, the same wipe as Q1. |
| q05 | [For each death on the night: defensives on cooldown or sitting unused, and did a healthstone or potion get used?](q05.md) | All 18 encounter pulls in log 30, gold pulls 435 through 452. Exclude trash and events between encounters. |
| q06 | [Did anyone die through a defensive or potion (the damage was simply too much)?](q06.md) | All 18 encounter pulls in log 30, gold pulls 435 through 452. Use a 10-second pre-death cast window and aura evidence. |
| q07 | [Who took avoidable damage on Twin Fangs, which spells, and how many times per pull?](q07.md) | All eight Twin Fangs pulls in log 30, gold pulls 445 through 452. |
| q08 | [Which casts on Sszorak went uninterrupted, and who was assigned or nearby?](q08.md) | All nine Sszorak pulls in log 30, gold pulls 436 through 444. Verify casts and interrupts from bronze, not interrupt silver. |
| q09 | [Is there a spell that keeps hurting people that we haven't marked as a mechanic yet?](q09.md) | All 18 encounter pulls in log 30, gold pulls 435 through 452. Rank repeated unruled damage by total logged amount. |
| q10 | [What is the one thing each player should fix for next week, as a private note per player?](q10.md) | All players in log 30 across gold pulls 435 through 452. Use a repeated killing blow as an investigation priority, not an automatic avoidable failure. |
| q11 | [Which players improved on their worst mechanic over the night?](q11.md) | All log 30 pulls. Separate authored mechanic improvement from observed hit and killing-blow trends. Exclude sub-minute resets from hit comparisons. |
| q12 | [As Wispless, what did I lose on pull N: deaths, downtime, wasted cooldowns?](q12.md) | Sszorak pull 5, gold pull 440. Search for Wispless by exact character identity. |

## Pull catalogue

| Gold pull | Boss | Boss pull number | Outcome | Duration ms | Start byte | End byte |
|---|---|---|---|---|---|---|
| 435 | Nymrissa Wavecaller | 1 | kill | 332108 | 5382296 | 66863953 |
| 436 | Sszorak | 1 | wipe | 4963 | 127740020 | 128833958 |
| 437 | Sszorak | 2 | wipe | 16 | 131938832 | 132007448 |
| 438 | Sszorak | 3 | wipe | 147085 | 132811535 | 161475803 |
| 439 | Sszorak | 4 | wipe | 31371 | 162255809 | 162906162 |
| 440 | Sszorak | 5 | wipe | 411678 | 163524737 | 232589586 |
| 441 | Sszorak | 6 | wipe | 126278 | 233348182 | 258428276 |
| 442 | Sszorak | 7 | wipe | 205423 | 259022251 | 300106410 |
| 443 | Sszorak | 8 | wipe | 44890 | 300881824 | 305356911 |
| 444 | Sszorak | 9 | kill | 402790 | 306878155 | 382126305 |
| 445 | The Twin Fangs | 1 | wipe | 283691 | 385018445 | 443754659 |
| 446 | The Twin Fangs | 2 | wipe | 497468 | 444687382 | 545199126 |
| 447 | The Twin Fangs | 3 | wipe | 462952 | 545792909 | 647491210 |
| 448 | The Twin Fangs | 4 | wipe | 476596 | 649244309 | 743971248 |
| 449 | The Twin Fangs | 5 | wipe | 504056 | 744926036 | 854752540 |
| 450 | The Twin Fangs | 6 | wipe | 467355 | 855518833 | 956693501 |
| 451 | The Twin Fangs | 7 | wipe | 460394 | 957263172 | 1055392145 |
| 452 | The Twin Fangs | 8 | kill | 445659 | 1056119869 | 1167985096 |

## Wipe-cause Promotion (we-sfg.1)

`gold.fact_wipe_cause` version 1 selects up to three player deaths strictly before
pull end minus 30 seconds. Kills and resets under 10 seconds have no rows. A wiped
pull can also have no deciding deaths (439 and 441 in this reference). The new
catalog labels Mutilate `unknown`, Tempest `avoidable`; uncatalogued Fel Armor
remains unknown. The first loss is not proof of the first mistake or wipe causation.

Reproducible checks:
- `FactWipeCauseTest`: all 18 reference pulls, Q1/Q4 operator overrides, unknown
  avoidability, stamped/idempotent rebuilds.
- `WipeCauseWCLTest`: all 16 shared WCL pulls. Fifteen agree after synthetic melee
  normalization (gold 0 / WCL 1); WCL leaves Felthuzad's blow on 440 unnamed.
  On 451 the order/times agree, but WCL names Eternal Venom 1292348 for Jentle,
  Wispless and Provibria where silver records 1290480. These three ID differences
  are reported, not silently aliased. This is the approved fixed cutoff, not
  WCL's full resurrection/first-cluster heuristic.
- `WipeCauseMCPTest`: deterministic built-in binding and MCP evidence, log scope,
  stale/missing states, one recorded Tool call and zero model calls/cost.
- `python3 scripts/verify_wipe_cause_mutations.py --output <artifact-dir>`: removing
  the cutoff fails reference and WCL checks; reversing order also fails AI
  agreement; inventing avoidability fails catalog checks; nonzero model calls
  fails the cost check. Restored production code passes all nine focused tests.

Cost evidence is in [promotion-wipe-cause-cost.json](promotion-wipe-cause-cost.json).
Original Q1: $4.1979124, 75 CLI turns; Q4: $1.1621076, 39 CLI turns. Turns are not
relabeled as model request counts. The deterministic integration path uses one
Tool call, zero model calls and $0. **Post-merge dev Q1/Q4 baseline reruns remain
pending with the coordinator**, along with persisted-gold verification after
migration/rebuild. No paid model call was made for this build. The question picker
and lifecycle UI are still separate work; `Analysis.BuiltInQuestions.answer/2`
is their deterministic binding boundary.

## Known limits

No failure facts exist for this night in the queried snapshot. Missing rules are not clean execution. Cooldown availability and interrupt assignments are not established by raw events. Q12 targets Wispless, the operator's character on this log. These limits are part of the reference answers, not permission to invent details.

The JSON under [evidence/](evidence/) contains exact rows, times, GUIDs, spell IDs, and bronze byte offsets. [questions.json](questions.json) freezes prompts and selections. [survival-catalog.json](survival-catalog.json) freezes the existing `SurvivalActions.all()` metadata; it is not a new coverage claim.

See [README.md](README.md) for recomputation, operator verification, reruns, grading, verdict recording, and export. Record verification here only after the operator checks the references.

## Operator verification record

- Reviewer and date: operator, 2026-10-29 (foreman decision on we-xf4.8: Q1-Q11 accepted as drafted).
- Reference corrections and scope changes: none to Q1-Q11. Q12 retargeted from Mittwoch (absent from the Sept 6 roster) to Wispless, the operator's character that night (foreman decision on we-xf4.8); its evidence was recomputed and its answer redrafted. The operator could not judge Q12 by eye, so it was verified against Warcraft Logs report `aW7mTPNrXwLcM2DR` instead (fight 13 = gold pull 440). The death time and killing blow, all 17 ability cast counts, and every Anti-Magic Shell, Icebound Fortitude, Death Pact and Healthstone time match exactly.
- Baseline run directory and model: [baselines/2026-10-29-opus55](baselines/2026-10-29-opus55/), `claude-opus-5-5` for both run and judge, graded against this revision. Cost: $30.99 for the run (Q3 and Q6 about $6.70 each, 100+ turns) plus $0.76 for the judge.
- Baseline grade counts: 4 correct (Q7, Q9, Q11, Q12), 8 partly, 0 wrong. Advisory 8/12, with partly counting as half; no pass threshold.
- Human overrides (coordinator, from bronze; operator review pending):
  - Q1 and Q4: the model is right and the reference is wrong. Mädz's 0:20.5 and 1:32 deaths on pull 440 are Feign Death: the `UNIT_DIED` `unconsciousOnDeath` flag is 1, and Mädz keeps casting with no resurrection. The first real death is Kahnu at 155.271 s (Mutilate). Read Q1 and Q4 as correct, which makes the overridden score 6 correct, 6 partly. Root cause: silver.death ignores the flag (we-6l9).
  - Q2: the judge's "unverified Feign Death inference" flag is likewise answered by we-6l9; the verdict stays partly for the other omissions.
  - The other partly verdicts stand: each one omits a reference element the judge named.
- Live Q1, persisted verdict, and joined export evidence: Analysis session `3e11529b-7679-446c-9cec-721125402dd2` (Claude Code, Opus 5.5) answered Q1 on Sszorak pull 5 (gold 440). It made 15 Tool calls with 0 errors; `log_events` took 345-462 ms per call. The answer cited Tool evidence for every claim, labelled its inference, and named the same first death as the reference: Mädz at 0:20.5. Export matched all 15 transcript calls to their server rows (0 unmatched either way; 1 unscoped ToolSearch call). The operator recorded a verdict in that session: `wrong`, with the correction that Mädz's 0:20 death was Feign Death and the first real death was Kahnu at 2:35 (Mutilate). It is analysis.verdicts row 1, and the re-export carries it with every call still matched.
- Warcraft Logs death cross-check (report `aW7mTPNrXwLcM2DR`): Warcraft Logs drops the two Sszorak resets (436, 437). On the 16 pulls both sides have, silver.death matches Warcraft Logs player for player except 9 extra Mädz rows, all of them Feign Death (we-6l9). Totals: 322 here, 313 on Warcraft Logs.
- Revision 2 (2026-10-30, after we-6l9): silver deaths now match Warcraft Logs on all 16 shared pulls (313 = 313). The 8 evidence files that changed (Q1, Q2, Q4, Q5, Q6, Q10, Q11, Q12) were recomputed, with a clean diff against a fresh run, and their answers rewritten. Q1 and Q4 now name Kahnu at 155.271 s as the first death. Q5 and Q6 dropped 9 Mädz Feign Death rows, including one on pull 439 that had been counted as a death through Exhilaration and a Healthstone.
