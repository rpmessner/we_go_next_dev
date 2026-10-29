# First-slice question corpus

The questions the first Analysis session slice must answer. Resolves wayfinder ticket we-c5q.1 under the map **AI analysis layer** (we-c5q). The operator reviewed the 12 seed questions on the foreman board on 2026-10-29, kept all 12 unchanged and added none. Grow this list as real sessions surface new questions.

Reference log: `Archive-WoWCombatLog-090626_103607.txt` (Sept 6 2026, 12.1.0). Nymrissa Wavecaller 1 pull, 1 kill; Sszorak 9 pulls, 1 kill; The Twin Fangs 8 pulls, 1 kill. "Pull N" means the operator picks a pull at session time.

The "Today" column is the coordinator's assessment of the local encounter detail page as of 2026-10-29 (tabs: overview, damage, mechanics, failures, deaths, interrupts, personal), not a measured audit.

| # | Family | Question | A good answer | Today |
|---|---|---|---|---|
| 1 | Wipes | Why did Sszorak pull N wipe: what was the first thing that went wrong? | The first causal event (an early death, a missed mechanic, a lost tank), with timestamp and the chain that followed to the wipe | Partial: Pull Signals and Death Recap show the pieces; nothing orders them into a cause |
| 2 | Wipes | Were we improving across the Sszorak pulls, and on which mechanics? | Per-mechanic failure counts and boss % reached, pull by pull, with the trend called out | No: views are per pull; no cross-pull comparison |
| 3 | Wipes | What changed between our last Twin Fangs wipe and the kill? | A diff of two pulls: deaths, failures, defensives and timings that differed | No |
| 4 | Deaths | Who died first on pull N, to what, and was it avoidable? | First death, killing blow and the damage leading up to it, classed as avoidable or not by the mechanic rules | Partial: Deaths tab has recaps; avoidability only where a rule exists |
| 5 | Deaths | For each death on the night: defensives on cooldown or sitting unused, and did a healthstone or potion get used? | Per death: defensives available vs used, rocks/pots used | No: Initiative 7 (we-37, we-38) is not built |
| 6 | Deaths | Did anyone die through a defensive or potion (the damage was simply too much)? | Deaths where a defensive or pot was active or used in the death window, with the damage that still landed | No: depends on Initiative 7 |
| 7 | Mechanics | Who took avoidable damage on Twin Fangs, which spells, and how many times per pull? | Player x spell x pull hit counts for spells ruled avoidable | Partial: Failures tab, only for code-defined mechanics |
| 8 | Mechanics | Which casts on Sszorak went uninterrupted, and who was assigned or nearby? | Uninterrupted kickable casts with time, plus who had a kick available | Partial: Interrupt Coverage exists; silver semantics are overbroad (we-23); no assignment data |
| 9 | Mechanics | Is there a spell that keeps hurting people that we haven't marked as a mechanic yet? | Spells ranked by damage or hit spread across players and pulls with no rule yet | Partial: Spell Coverage lists spells; no "unruled and repeated" ranking |
| 10 | Coaching | What is the one thing each player should fix for next week, as a private note per player? | One prioritised, evidenced fix per player, written for that player | No |
| 11 | Coaching | Which players improved on their worst mechanic over the night? | Per player: worst mechanic and its trend across pulls | No |
| 12 | Own play | As Mittwoch, what did I lose on pull N: deaths, downtime, wasted cooldowns? | Personal deaths, casting gaps and cooldown usage vs availability for one player | Partial: Personal Pull Summary; no downtime or cooldown analysis |

Observations for the starter Tool set:

- A third of the corpus (2, 3, 10, 11) is cross-pull. Single-pull views cannot answer it, so a Tool that compares pulls is likely essential.
- 5 and 6 need the defensives/consumables grain (Initiative 7). Either the first slice waits on it, or a filtered bronze re-parse stands in for it (see `docs/research/tool-read-paths.md`).
- 9 is a discovery question: the agent ranks unruled spells, which feeds mechanic authoring.
