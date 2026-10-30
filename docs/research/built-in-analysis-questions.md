# Built-in Analysis questions

Research for `we-c5q.13`: *Which questions do raiders answer with Warcraft Logs and similar tools, and which should be built-in Analysis questions?*
Date: 2026-10-29. Branch: `research/built-in-questions` (from `main` @ `7c70e5f`).

Inputs: `docs/ai-analysis/question-corpus.md` (the 12 questions in use, "Q1"–"Q12" below), `docs/ai-analysis/session-screen-design.md`, and the Tool modules in `we_go_next/lib/we_go_next/analysis/tools/`.

## Short answer

- Raiders use log tools for six recurring jobs: explain a wipe, explain each death, count mechanic failures per player, rank throughput against peers, separate useful damage from padding, and review their own play (active time, cooldowns, consumables). Each job is a named feature in Warcraft Logs (WCL), Wipefest or WoWAnalyzer, cited below.
- The catalog below has **34 candidate questions in 6 families**. 13 of them overlap the existing 12, so the 12 already sit well inside common practice. Most of the new ones are in the **performance** family, which the corpus does not touch at all.
- Today's 7 Tools answer the wipe, death and mechanic families partly. They **cannot answer the performance family**: no Tool exposes damage done, healing, or damage by target. The data is partly in silver already (`silver.damage_done` is source × target × spell per pull; the encounter document holds per-player damage and `low_dps`). Only `log_events`, one pull at a time, reaches it today.
- Padding is judged in practice by **damage to the boss versus total damage**, **damage to a specific target**, and **per-encounter exclusion of irrelevant adds**. Our warehouse can do the first two once it knows which NPCs are bosses and which adds are priorities. It cannot do "damage in a key window" until damage done gets a time grain.

## What the tools do, from their sources

### Warcraft Logs

- **Rankings and parses.** Rankings compare a player's metric against everyone of the same spec on the same encounter and difficulty, as a percentile. Historical percentiles are cached at fixed marks once a day and interpolated. "Rankings" are a player's best scores across the tier; "Parses" compare against all parses from the last two weeks (moderator answer). All Star points score performance across a whole zone. Sources: [WCL ranks guide](https://www.warcraftlogs.com/help/ranks/) (403 to automated fetch; content via search excerpt), [WCL forum: how do the new percentages work](https://forums.combatlogforums.com/t/how-do-the-new-percentages-work/5491), [WCL forum: rankings vs analyze](https://forums.combatlogforums.com/t/please-explain-diffrence-between-rankings-tab-and-performance-under-analyze-tab/127).
- **Boss damage as a separate metric.** WCL ranks "Damage Done" and "Damage to Bosses" separately. Kihra (WCL founder): *"You have 'Damage to Bosses' selected, which is damage done only to boss mobs. You want 'Damage Done', which will also include the boss fight adds."* ([forum t/8719](https://forums.combatlogforums.com/t/previous-2-weeks-of-logs-not-showing-up-on-rank/8719)). Users ask for boss damage as an All Star metric because it is "a useful metric to consider when checking logs" ([t/2963](https://forums.combatlogforums.com/t/any-plan-to-support-player-damage-to-bosses-as-all-star-ranking/2963)).
- **Irrelevant-add exclusion and weighted damage.** WCL removes damage to specific adds from rankings, per encounter. Kihra: *"This isn't so much about removing 'padding' as it is about removing damage that is completely irrelevant to killing the encounter."* Only damage is filtered: casts, debuffs, the events view, timeline, replay and "Damage Taken by Enemies" stay unfiltered for analysis ([t/2698](https://forums.combatlogforums.com/t/removing-padding-from-combat-log-rankings/2698)). WCL also had per-add "weighted damage" (high, normal or low priority burn) ([t/1176](https://forums.combatlogforums.com/t/weighted-damage-in-emerald-nightmare/1176)). On Hivemind (Ny'alotha) only adds that "die to passive cleave" and never need a target switch were removed. Adds that need a switch stayed counted, and the report has a filtered/unfiltered toggle ([t/9966](https://forums.combatlogforums.com/t/hivemind-drone-damage-removed/9966)). Per-boss "parsing rules" pages list the excluded adds ([example](https://www.archon.gg/classic-mop/articles/help/dragon-soul-parsing-rules), via search excerpt). In Dragonflight 10.0.7, WCL made boss-specific changes after players padded damage on Thunder Caller adds while the raid finished the boss ([WCL news](https://articles.warcraftlogs.com/news/dragonflight-patch-10-0-7-partition-and-updates), via search excerpt).
- **Target-specific damage.** Damage Done can be narrowed to a specific target, and WCL's filter expressions can express things like "damage to actor 1 while actor 2 is alive" ([t/8235](https://forums.combatlogforums.com/t/help-filter-damage-to-actor1-while-actor2-is-alive/8235)). Raiders use this to check "who is doing priority damage to the boss, reaver or darters" ([t/9966](https://forums.combatlogforums.com/t/hivemind-drone-damage-removed/9966)).
- **Deaths and the wipe cutoff.** Death Statistics shows wipes, kills, or both. For wipes, a cutoff starts 30 s before the pull ends; a combat rez in that window moves it. The first death cluster after the cutoff counts, and later deaths are dropped *"on the assumption that the wipe has been called"*. Kills count every death. The uploader also has a "Call a Wipe" keybind that marks the point to filter from ([WCL help: death statistics](https://articles.warcraftlogs.com/help/death-statistics), via search excerpt).
- **Pins.** Saved filters that total, for example, hits from avoidable abilities, potion and healthstone use, dispels and interrupts. They also add aura badges in the Deaths pane, to see whether a defensive was up when a hit landed ([WCL help: pins](https://www.warcraftlogs.com/help/pins), via search excerpt). A live Midnight-era guild page titled "Avoidable Damage Progress (Heroic VS / DR / MQD)" shows guilds tracking avoidable damage across this tier with this feature ([example](https://www.warcraftlogs.com/guild/progress/132303)).
- **Analyze (Multiple Report Analysis).** A guild's Analyze tab merges several raid nights into one report, so all pulls of a boss can be reviewed together ([WCL news: multiple report analysis](https://www.archon.gg/wow/articles/news/multiple-report-analysis), via search excerpt).

### Wipefest

Wipefest is a mechanics-first summary of a WCL report ([wipefest.gg](https://www.wipefest.gg/): "Raid summaries based on Warcraft Logs"). It now lives under WCL/Archon. Sources: [How to improve your raid with Wipefest](https://www.archon.gg/wow/articles/help/how-to-improve-your-raid-with-wipefest), [Wipefest FAQ](https://www.archon.gg/wow/articles/help/wipefest-frequently-asked-questions), [Wipefest: Voidspire and Dreamrift](https://www.archon.gg/wow/articles/news/wipefest-voidspire-and-dreamrift), all via search excerpt.

- **Raid Score per mechanic (0–100):** how the raid did on a mechanic compared with a week's sample of kills. Mechanics are ordered by importance, and *"if your raid is scoring low on them, they are often a good point of focus for your next pull."*
- **Player Score:** *"what would the Raid Score be if everyone in the raid performed the same as this player did on this mechanic?"*, weighted by the mechanic's importance. Deaths lower it more the earlier they happen.
- **Fairness:** interrupts, dispels and soaks feed only a bonus score, because *"not everyone gets an equal opportunity"*. Tank swaps are shown but not scored. Avoidable damage excludes the targeted player for mechanics that always hit that player.
- **Wipes:** reviews of wipes ignore events after N deaths (3 in the example), so deliberate wipe-deaths aren't scored.
- **Multi-pull analysis:** mechanics across up to 50–150 pulls, with improvement pull by pull, plus a beta "player contributions" view.
- It covers the current tier: Voidspire and Dreamrift have an announcement post; Manaforge Omega and Liberation of Undermine had ones in The War Within.

### WoWAnalyzer

WoWAnalyzer is open source ([repo](https://github.com/WoWAnalyzer/WoWAnalyzer), local checkout at `0ae77b9e35`, May 2026). It is a per-player, per-spec review: *"analyze and improve your World of Warcraft raiding performance through various relevant metrics and gameplay suggestions"* (README). The shared modules show what every spec gets:

- Active time and downtime: [`AlwaysBeCasting.tsx`](https://github.com/WoWAnalyzer/WoWAnalyzer/blob/0ae77b9e35/src/parser/shared/modules/AlwaysBeCasting.tsx) ("You spent X% of your time casting"). [`FilteredActiveTime.tsx`](https://github.com/WoWAnalyzer/WoWAnalyzer/blob/0ae77b9e35/src/parser/shared/modules/FilteredActiveTime.tsx) and `FightDowntimeToggle` subtract boss-untargetable time.
- Cooldown and cast use: [`CastEfficiency.tsx`](https://github.com/WoWAnalyzer/WoWAnalyzer/blob/0ae77b9e35/src/parser/shared/modules/CastEfficiency.tsx), `CancelledCasts`, `SpellUsable`, `CooldownThroughputTracker`.
- Deaths: `DeathRecap`, `DeathTracker`, and `DEFENSIVE_BUFFS.ts`/`MitigationCheck` (was a defensive up for a hit).
- Preparation: `items/FlaskChecker`, `FoodChecker`, `EnchantChecker`, `GemChecker`, `WeaponEnhancementChecker`.
- Debuff uptime and dispels: `DebuffUptime`, `DispelTracker`.

### Raid-leading practice

Secondary guides agree on a review order: deaths first, then damage taken in the moments before each death, then assignments and planned cooldowns. Damage taken shows whether a death came from an avoidable mechanic or from unavoidable damage that wasn't healed through. Between pulls, keep the call to one sentence of cause and one of correction. Sources: [Midnight beginner's guide to reading WCL](https://raidmemegen.vercel.app/blog/how-to-read-warcraft-logs-beginner-s-guide-to-improving-raid-performance-in-wow-midnight-2026), [raid-lead communication](https://raids-com.pages.dev/how-to-lead-raid-group/), [Wowhead: How to use Warcraft Logs](https://www.wowhead.com/guide/how-to-use-warcraft-logs-6341) (user-submitted; the body did not render for fetch). These are low-trust and used only to corroborate the order; no Method or Raider.IO raid-leading article turned up.

## How padding is judged in practice

1. **Boss damage vs total damage.** This is the first cut, and WCL ranks both ([t/8719](https://forums.combatlogforums.com/t/previous-2-weeks-of-logs-not-showing-up-on-rank/8719)). A large gap between a player's total and their boss damage means damage went to adds. That is padding only if those adds didn't need to die.
2. **Which adds matter is per encounter.** WCL's line is "completely irrelevant to killing the encounter": adds that die to passive cleave, adds that never need a switch, adds kept alive or deliberately spawned to cleave ([t/2698](https://forums.combatlogforums.com/t/removing-padding-from-combat-log-rankings/2698), [t/9966](https://forums.combatlogforums.com/t/hivemind-drone-damage-removed/9966), [t/6797](https://forums.combatlogforums.com/t/removing-adds-from-several-fights-and-keeping-boss-damage-only/6797)). The same thread shows the counterpoint: lower-ranked guilds do need to kill some of those adds, so "boss only" can punish correct play. A third-party analysis makes the same point: boss damage alone fails on fights where adds must be focused over the boss ([bolas substack](https://bolas.substack.com/p/differences-between-crusader-strike), low trust).
3. **Priority-target damage.** This is damage to named priority adds, usually while they are alive or during their spawn window ([t/8235](https://forums.combatlogforums.com/t/help-filter-damage-to-actor1-while-actor2-is-alive/8235)). On progression it often matters more than overall damage. It needs the encounter's priority-add list, which is authored knowledge in the same way avoidable spells are.
4. **Damage during key windows.** Examples are damage during an intermission when the boss should not be hit ([t/10898](https://forums.combatlogforums.com/t/suggestion-dont-include-dmg-to-boss-during-stone-legion-generals-intermission/10898)) or burn phases. This needs time-bucketed damage done.
5. **Damage done vs damage taken.** Wipefest's Player Score puts throughput aside and scores mechanics and deaths. Healers have padded by standing in fire to heal themselves ([t/13653](https://forums.combatlogforums.com/t/healers-padding-to-parse-well/13653)). A "padder" in raid-lead language is someone high on the meter who is also high on avoidable damage or low on priority damage.

For this tool: rankings and percentiles need a population we don't have. Built-in performance questions should compare within the raid, within the spec where there is more than one, and against the player's own earlier pulls. The existing `low_dps` read model already does a within-raid version: under 70% of the median for DPS and healers, excluding early deaths (`gold/encounter_detail.ex`, `@low_damage_warning_median_ratio 0.7`).

## What today's Tools can reach

| Tool | Reads | Relevant limits |
|---|---|---|
| `list_pulls` | gold pulls: boss, start, success, fight time | No boss HP % at wipe, no phase reached |
| `pull_summary` | encounter document overview, signals, roster | Signals give only a *count* of low-damage players. The document's `pull_review.damage_done` and `low_dps` lists are not exposed. |
| `deaths` | `silver.death` recaps, killing blow | The read model computes `survival` (defensives/healthstones/potions from `silver.survival_action` and `silver.defensive_buff_window`), but the Tool drops it (`Map.take` in `deaths.ex`) |
| `failures` | `gold.fact_failure` | Code-defined mechanics only; aggregate per pull, no hit times |
| `damage_taken` | `silver.damage_taken` player × spell × pull | No source/NPC split, no timing (the event-grain `silver.damage_taken_event` has both but no Tool) |
| `interrupts` | `silver.interrupt_opportunity` | Overbroad (we-23); no assignment or kick availability |
| `log_events` | bronze, one pull, filtered | The only path to damage done by target, healing, casts, buffs, resources; slow per pull and raw |

Ratings below: **Yes** (Tools answer it directly), **Partial** (Tools give the pieces; the agent must assemble or verify with `log_events`, or coverage is limited), **No** (the data isn't reachable at practical cost).

## Catalog

"Overlap" names the corpus question it duplicates or contains. **Bold** questions are the recommended first built-ins.

### Wipes (7)

| # | Question | A good answer contains | Data needed | Today | Overlap |
|---|---|---|---|---|---|
| W1 | **Why did this pull wipe?** | The first causal event (early death, missed mechanic, tank loss, enrage, DPS check), the chain to the wipe, and when the wipe was effectively called (WCL cutoff logic) | Deaths ordered by time, failures with times, boss HP % at end, `ENCOUNTER_END` | Partial: `deaths` + `failures` + `log_events`; no wipe-cutoff or boss % | Q1 |
| W2 | **What is our most common wipe cause on this boss tonight?** | Wipe causes classified per pull and counted, e.g. "Eternal Venom was top killing blow on 7/7 Twin Fangs wipes" | W1 for every pull, plus a cause taxonomy (we-c5q.14) | Partial: `deaths` across pulls gives killing-blow counts; no classifier | — |
| W3 | **Are we improving across pulls, and on what?** | Per pull: boss % or phase reached, deaths, failures per mechanic, with the trend called out | Boss HP % / phase per pull, failures per pull | Partial: failures and deaths per pull; no boss % or phase | Q2 |
| W4 | **What changed between our last wipe and the kill?** | A diff of two pulls: deaths, failures, defensives, cooldown timings, damage profile | Two-pull comparison over all of the above | Partial: costly; no diff Tool | Q3 |
| W5 | Did we hit the DPS check / enrage, or die before it? | Boss HP vs time against enrage or phase timer; which phase transitions were late | Boss HP over time (target advanced block on damage events), phase events | No: needs `log_events` boss-HP reconstruction per pull | — |
| W6 | Which phase do we wipe in, and how long does each phase take? | Phase reached per pull, phase durations, and where time is lost | Phase boundaries per boss (authored), boss HP | No: no phase model | — |
| W7 | How much time did we lose between pulls? | Pull count, total time in combat vs reset time per boss | `gold.dim_encounter` start/end times | Yes: `list_pulls` | — |

### Deaths (6)

| # | Question | A good answer contains | Data needed | Today | Overlap |
|---|---|---|---|---|---|
| D1 | **Who died first on each pull, to what, and was it avoidable?** | First death, killing blow, recap, and an avoidable/unavoidable call backed by a rule | `silver.death`, mechanic rules | Partial: `deaths`; avoidability only where a rule exists | Q4 |
| D2 | **Which deaths were preventable: defensive, healthstone or potion unused?** | Per death: defensives on cooldown vs available, consumables used, external cooldowns received | `silver.survival_action`, `silver.defensive_buff_window`, cooldown availability | Partial: data is in silver but the `deaths` Tool drops `survival`; availability is not modelled | Q5 |
| D3 | Who died *through* a defensive or potion (damage simply too much)? | Deaths with an active defensive or consumable use in the window, with the damage that still landed | As D2 | Partial: as D2 | Q6 |
| D4 | What are the top killing blows on this boss across the night? | Spell × count × pulls, split by avoidable or not | `silver.death` across pulls | Yes: `deaths` (paging-heavy) | — |
| D5 | Who dies most often, and do they die early? | Per player: deaths, average time of death as % of the fight, repeat killing blows | `silver.death`, fight time | Yes: `deaths` + `list_pulls` | — |
| D6 | Which deaths happened after the wipe was called? | Deaths after a WCL-style cutoff, so they're excluded from blame | Wipe-cutoff rule over deaths and combat rezzes | Partial: deaths yes; rezzes need `log_events` | — |

### Mechanics (7)

| # | Question | A good answer contains | Data needed | Today | Overlap |
|---|---|---|---|---|---|
| M1 | **Who took avoidable damage, from which spells, how often per pull?** | Player × spell × pull hit counts, excluding the targeted player where the mechanic always hits them (Wipefest rule) | `gold.fact_failure`, `silver.damage_taken_event` | Partial: `failures` for code-defined mechanics; `damage_taken` lacks timing and source | Q7 |
| M2 | **Which mechanic is costing us the most?** | Mechanics ordered by impact (deaths caused, damage, players affected) with per-pull counts. This is the Wipefest "focus" list. | Failures plus deaths linked to mechanics, importance weights | Partial: `failures` + `deaths`; no importance ordering | — |
| M3 | Which casts went uninterrupted, and who had a kick? | Uninterrupted kickable casts with time, kickers in range with kick ready | Tightened interrupt silver, kick cooldown availability | Partial: `interrupts` is overbroad (we-23) | Q8 |
| M4 | **Is there a spell hurting people that we haven't marked as a mechanic?** | Unruled spells ranked by damage, hit spread and pulls, as authoring candidates | `silver.damage_taken` minus ruled spells | Partial: `damage_taken` + `failures`, manual set difference | Q9 |
| M5 | Were debuffs dispelled in time, and by whom? | Dispellable debuffs with application → removal latency and dispeller | `SPELL_DISPEL`, aura removal events | No: `log_events` per pull only; no dispel silver | — |
| M6 | Did soaks, spreads and stacks happen correctly? | Per occurrence: who soaked, missing soakers, overlaps | Rule types `soak`/`spread`/`stack` (empty thresholds today), positions | No: fact semantics don't exist | — |
| M7 | Was the targeted mechanic aimed right (e.g. Dread Breath)? | Aiming player, players clipped, collateral within policy | `targeted_cone` rule type | Partial: depends on targeted-cone facts being built | — |

### Performance (8)

| # | Question | A good answer contains | Data needed | Today | Overlap |
|---|---|---|---|---|---|
| P1 | **Who are our low performers on this boss?** | Players well below the raid median for their role (and below same-spec peers where there are any), with early deaths, active time and assignments shown as context so a low number is explained before it is judged | Per-player damage/healing, fight time, deaths, active time | Partial: `pull_summary` gives a count only; the list is in the encounter document but not exposed | — |
| P2 | **Who are our all-stars?** | Top performers by role, combining throughput with clean mechanics (Wipefest Player Score idea), not throughput alone | P1 data plus failures and deaths | No: no damage-done Tool | — |
| P3 | **Who is padding: high on the meter, low on damage that mattered?** | Per player: total damage vs boss damage vs priority-add damage, with the share each makes up and the ranking change when only useful damage counts | `silver.damage_done` by target, a boss/priority NPC catalog per encounter | No: `silver.damage_done` has the target grain, but no Tool and no NPC catalog | — |
| P4 | Who switched to priority adds, and how fast? | Per priority add spawn: time to first damage, share of damage per player, time to kill | Time-grain damage done to NPCs, add spawn/death times | No: needs `log_events` per pull | — |
| P5 | Who did damage in the key window (burn phase, intermission, Bloodlust)? | Damage per player inside named windows vs outside | Time-bucketed damage done, window definitions | No: damage done has no time grain | — |
| P6 | Who is high on damage *and* high on avoidable damage taken? | Players in the top meter third who also lead avoidable hits | P3 + M1 | No: needs damage done | — |
| P7 | How does each player compare with their own earlier pulls or nights? | Per player: throughput trend, deaths, failures over pulls | Per-pull damage done, deaths, failures | Partial: failures and deaths only | Q11 (partly) |
| P8 | Are healers' numbers real (overheal, self-heal padding)? | Effective healing, overheal %, healing to self vs raid, healing while standing in avoidable damage | Healing events, `silver.damage_taken_event` | No: no healing silver | — |

### Coaching (3)

| # | Question | A good answer contains | Data needed | Today | Overlap |
|---|---|---|---|---|---|
| C1 | **What is the one thing each player should fix next week, as a private note?** | One prioritised, evidenced fix per player | Everything above, ranked per player | Partial: deaths and failures only; no throughput or cooldown evidence | Q10 |
| C2 | Which players improved on their worst mechanic over the night? | Per player: worst mechanic and its trend | Failures across pulls | Partial: `failures` across pulls | Q11 |
| C3 | Who keeps making the same mistake (repeat offenders)? | Players with the same failure or killing blow in ≥ N pulls | Failures and deaths across pulls | Yes: `failures` + `deaths` | — |

### Own play (3)

| # | Question | A good answer contains | Data needed | Today | Overlap |
|---|---|---|---|---|---|
| O1 | **What did I lose this pull: deaths, downtime, wasted cooldowns?** | Personal deaths, active time (WoWAnalyzer ABC), major cooldowns used vs available | Casts and auras for one player, cooldown catalog | Partial: deaths yes; casts via `log_events`; no availability model | Q12 |
| O2 | Was I prepared (flask, food, weapon oil, augment rune, potion use)? | Missing consumables per pull (WoWAnalyzer checkers) | `COMBATANT_INFO` auras, `SPELL_AURA_*` at pull start | No: needs `log_events`; no consumable catalog beyond survival actions | — |
| O3 | Did I use my defensives and personals at the right times? | Defensives used against heavy-damage moments, and unused defensives on deaths | `silver.survival_action`, damage taken over time | Partial: silver has it, no Tool exposes it | — |

## Counts and overlap

| Family | Questions | Overlap with the 12 | Yes | Partial | No |
|---|---|---|---|---|---|
| Wipes | 7 | Q1, Q2, Q3 | 1 | 4 | 2 |
| Deaths | 6 | Q4, Q5, Q6 | 2 | 4 | 0 |
| Mechanics | 7 | Q7, Q8, Q9 | 0 | 5 | 2 |
| Performance | 8 | Q11 (partly) | 0 | 2 | 6 |
| Coaching | 3 | Q10, Q11 | 1 | 2 | 0 |
| Own play | 3 | Q12 | 0 | 2 | 1 |
| **Total** | **34** | **13 rows; all 12 covered** | **4** | **19** | **11** |

## Recommended first built-ins

These are ordered by how often raiders reach for them (from the sources above) and by how close the data is.

1. W1 Why did this pull wipe? (Q1)
2. D1 Who died first, to what, avoidable? (Q4)
3. M1 Who took avoidable damage, which spells, how often? (Q7)
4. W2 Most common wipe cause on this boss tonight
5. D2 Which deaths were preventable (defensive, healthstone, potion unused)? (Q5)
6. P1 Low performers on this boss
7. P3 Who is padding: total vs boss vs priority damage
8. M2 Which mechanic is costing us the most?

Then P2 all-stars, C1 one fix per player (Q10), W3 improvement across pulls (Q2) and O1 own pull (Q12).

## Biggest data gaps

1. **No damage-done or healing Tool.** It blocks the whole performance family. `silver.damage_done` (source × target × spell) and the document's `pull_review.damage_done`/`low_dps` exist. The smallest step is a `damage_done` Tool over silver plus exposing the `low_dps` list in `pull_summary`.
2. **No boss / priority-add catalog per encounter.** Without it, "boss damage" and "priority damage" can't be told from padding. This is authored knowledge, the same kind as the mechanic rules in `WeGoNext.GameData.Raids.*`, and it should live there (NPC id → `boss | priority | ignorable`).
3. **No time grain on damage done.** It blocks key-window damage (P5) and target-switch speed (P4).
4. **No boss HP % or phase per pull.** It blocks "how far did we get" (W3, W5, W6). Boss HP is in the target advanced block on damage lines (see AGENTS.md "Advanced-block semantics"); phases need authored boundaries.
5. **The survival data is hidden.** `silver.survival_action` and `silver.defensive_buff_window` exist and the deaths read model already analyses them, but the `deaths` Tool drops `survival`. Exposing it moves D2, D3 and O3 most of the way. Cooldown *availability* is still unmodelled.
6. **No wipe-cutoff rule.** Blame questions (W1, D5, C3) need WCL-style exclusion of deaths after the wipe is called.
7. **No dispel, soak, spread or stack semantics** (M5, M6), and interrupt silver is still overbroad (M3, we-23).
8. **No population for percentiles.** Performance must be judged within the raid, within spec, and against the player's own history, never as WCL-style percentiles.

## Source trust notes

- WCL's own pages (`warcraftlogs.com`, `articles.warcraftlogs.com`, `archon.gg`) return HTTP 403 to automated fetches (Cloudflare). Claims marked "via search excerpt" come from search-engine extracts of those pages, not a full read. Check them in a browser before quoting them as product copy.
- The highest-trust WCL statements here are Kihra's (WCL founder) posts on WCL's official forum, read in full through the forum's JSON API. Several are from 2016–2020. The mechanisms they describe (boss-damage metric, per-encounter exclusions, unfiltered analysis views) still exist; the specific encounters are old.
- WoWAnalyzer claims come from its source code (local checkout `0ae77b9e35`).
- Reddit (r/CompetitiveWoW) could not be fetched (403). Community practice is taken from WCL forum threads instead.
