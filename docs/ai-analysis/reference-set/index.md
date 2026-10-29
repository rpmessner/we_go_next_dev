# Sept 6 phase-1 reference set

Status: all answers are drafts. Operator verification and the paid baseline are pending. No baseline score or live acceptance check is claimed.

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
| q12 | [As Mittwoch, what did I lose on pull N: deaths, downtime, wasted cooldowns?](q12.md) | Sszorak pull 5, gold pull 440. Search for Mittwoch by exact character identity; do not guess an alias. |

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

## Known limits

No failure facts exist for this night in the queried snapshot. Missing rules are not clean execution. Cooldown availability and interrupt assignments are not established by raw events. Mittwoch is absent from the imported names. These limits are part of the reference answers, not permission to invent details.

The JSON under [evidence/](evidence/) contains exact rows, times, GUIDs, spell IDs, and bronze byte offsets. [questions.json](questions.json) freezes prompts and selections. [survival-catalog.json](survival-catalog.json) freezes the existing `SurvivalActions.all()` metadata; it is not a new coverage claim.

See [README.md](README.md) for recomputation, operator verification, reruns, grading, verdict recording, and export. Record verification here only after the operator checks the references.

## Operator verification record

- Reviewer and date: pending.
- Reference corrections and scope changes: pending.
- Baseline run directory and model: pending.
- Baseline grade counts and human overrides: pending.
- Live Q1, persisted verdict, and joined export evidence: pending.
