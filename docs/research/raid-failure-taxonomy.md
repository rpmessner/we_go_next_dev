# Raid failure taxonomy

Research for `we-c5q.14`: *What wipe conditions and mechanic failures recur across raids, and
which can the warehouse detect?* Date: 2026-10-29. Branch: `research/failure-taxonomy` (from
`main` @ `496a008`).

The goal is a library of failure kinds for the medallion analysis engine. For each kind this
note gives the combat-log signature, an example mechanic with its spell ID, how existing tools
detect it, the `rules.mechanic_criterion` type it maps to, and whether today's silver grain can
support a fact.

## Short answer

- There are **16 recurring kinds**: 11 player-level failure kinds and 5 encounter-level wipe
  conditions. The 8 existing criterion types cover 7 of the player kinds. Only `avoidable` and
  `targeted_cone` have fact semantics today.
- **No type exists yet** for dispels, add control, adds reaching the boss, fixates, debuff
  mishandling, positional failures, or any of the encounter-level wipe conditions (berserk,
  DPS check, healing check, death cascade).
- **Silver gaps** block most of the new kinds. Silver has no dispel events, no healing events,
  no NPC deaths or spawns, no boss health, and no positions. The Zig NIF reads the advanced
  block but throws away the position fields (`priv/native/combat_log_parser.zig`,
  `parse_advanced_fields`).
- **Build first:** (1) death-to-mechanic wipe attribution, (2) more avoidable coverage,
  including Midnight Season 2, which the catalog does not cover yet, (3) soak under-fill,
  (4) tank-swap stack thresholds, (5) interrupts once `#61` lands. All five run on silver tables
  that already exist. The full ranking is at the end.

## Evidence base

| Source | What it gave | Trust |
|---|---|---|
| Local real log `Archive-WoWCombatLog-102526_104340.txt` (12.1.5, Mythic Entombed Sentinels and Nek'zali, first 3M lines) | Event-type counts, real line layouts for `SPELL_DISPEL`, `SPELL_INTERRUPT`, `SPELL_HEAL_ABSORBED`, `SPELL_CAST_SUCCESS`, `SPELL_DAMAGE`, `UNIT_DIED`, `ENCOUNTER_END` | Primary, measured |
| BigWigs v427.8 boss modules installed under `_retail_/Interface/AddOns/BigWigs_*` | Spell IDs with role tags (`TANK`, `TANK_HEALER`), soak, spread and taunt annotations, berserk timers, `SPELL_INTERRUPT` and aura listeners for TWW and Midnight raids | Primary (boss-mod source); IDs cited, no code copied |
| WoWAnalyzer checkout `../WoWAnalyzer` @ `0ae77b9e35` (AGPL, evidence only) | Midnight raid timelines in `src/game/raids/vs_dr_mqd/`, deleted Manaforge Omega timelines (last present in `da2a871482^`), shared modules `MitigationCheck`, `DispelTracker`, `DeathTracker`, `DistanceMoved` | Primary (source) |
| Repo catalogs in `we_go_next/lib/we_go_next/game_data/raids/` | Current-tier spell IDs and authored types | Local authored intent |
| [warcraft.wiki.gg COMBAT_LOG_EVENT](https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT) | Advanced parameter order and subevent suffix fields | Community reference for the Blizzard format |
| Warcraft Logs and Wipefest help pages (Archon, warcraftlogs.com) | How those tools represent deaths, wipes, interrupts, soaks and avoidable damage | **Lower confidence:** every page returned HTTP 403 to fetch, so claims come from search-result summaries of the pages linked in Sources |

## How the log encodes the evidence (measured on 12.1.5)

Event volume in the first 3M lines of a Mythic raid night: `SPELL_DAMAGE` 434k,
`SPELL_AURA_APPLIED` 238k, `SPELL_AURA_APPLIED_DOSE` 190k, `SPELL_CAST_SUCCESS` 124k,
`SPELL_CAST_START` 42k, `SPELL_SUMMON` 11k, `UNIT_DIED` 719, `SPELL_HEAL_ABSORBED` 554,
`SPELL_DISPEL` 208, `SPELL_INTERRUPT` 109, `SPELL_AURA_BROKEN_SPELL` 84,
`ENVIRONMENTAL_DAMAGE` 23.

Facts that matter for detection:

- **Advanced block, 19 fields on 12.x.** In a real `SPELL_DAMAGE` line from the Venomfang
  Juggernaut, the block ends `…,65.20,-7.17,2606,2.0761,331`: that is `positionX`,
  `positionY`, `uiMapID`, `facing` and `level`. The wiki lists 17 parameters (`infoGUID`,
  `ownerGUID`, HP, max HP, attack power, spell power, armor, absorb, power fields, `positionX`,
  `positionY`, `uiMapID`, `facing`, `level`). On 12.x there are two more fields before
  position. Count them from the end, not the start. The block describes the **target** on
  spell damage, which gives the hit player's position, and the **source** on
  `SPELL_CAST_SUCCESS`, which gives the casting boss's position and facing (for example
  `Blood Clot … 71.73,-7.64,2606,2.6213`).
- **Single-target and AoE marker.** 12.x `SPELL_DAMAGE` lines end with `ST` or `AOE` (60k `ST`
  and 107k `AOE` in a 1M-line sample). This is a cheap way to tell a soak or spread hit from a
  chain or splash hit. It is not in the wiki and the NIF does not parse it yet.
- **`SPELL_DISPEL`** carries the dispelled spell as `extraSpellId,extraSpellName,school,auraType`.
  Real line: `… 383015,"Poison Cleansing",0x8,1290147,"Poison Bolt",8,DEBUFF`.
- **`SPELL_INTERRUPT`** carries the interrupted spell the same way:
  `47528,"Mind Freeze",0x10,1290147,"Poison Bolt",8`.
- **`UNIT_DIED`** carries `recapID` and `unconsciousOnDeath`
  ([wiki](https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT)). NPC deaths are logged too, which is
  what add-kill timing needs.
- **`ENCOUNTER_END`** carries `success` and `fightTime` (ms): `3470,"Nek'zali the Soulcoiler",16,20,0,13353`.
- **`SPELL_HEAL_ABSORBED`** carries the absorbing aura. Heal-absorb checks need it.
- **Private auras (12.x).** BigWigs declares many Midnight debuffs as private auras
  (`SetPrivateAuraSounds` in `BigWigs_TheVoidspire/Averzian.lua`). Addons cannot see them, but
  the combat-log *file* is written by the client and the repo's catalog already sees debuffs
  such as Void Marked `1280013` in `silver.debuff_application`. Private auras limit boss mods,
  not this tool.

What the NIF and silver keep today: damage events (with `amount`, `overkill`, `absorbed`),
heals (parsed, but only `survival_action` keeps a narrow slice), `SPELL_INTERRUPT` with
`extra_spell_id`, aura applied, removed and dose events with `aura_type`, `ENVIRONMENTAL_DAMAGE`,
`UNIT_DIED`, and `COMBATANT_INFO`. Other `SPELL_*` lines (casts, `SPELL_DISPEL`, `SPELL_SUMMON`)
come through with only the generic spell prefix. `SPELL_DISPEL` has no `extra_spell_id`, and no
event has position.

## How existing tools model failures

- **Wipefest** sits on top of Warcraft Logs and builds per-boss "insights". Its own
  announcements list avoidable damage, debuff durations, dispels, enemy healing, tank swaps,
  soaks and interrupts. It excludes players who cannot avoid a hit, such as the targeted
  players on Ky'veza and tanks on tank mechanics. It lets you ignore events after the first N
  deaths (1-5) so the analysis stops where the wipe started. It scores players relative to
  their raid and ranks mechanics by importance across a large sample of logs. It has bespoke
  rules too: on Undermine it counts only hits where a player was struck more than once at the
  same instant (overlap, a spread failure), and on Gallywix it tracks who soaked which cast.
  ([Archon Wipefest help](https://www.archon.gg/wow/articles/help/how-to-improve-your-raid-with-wipefest),
  [Wipefest: Liberation of Undermine](https://www.archon.gg/wow/articles/news/wipefest-liberation-of-undermine),
  [Wipefest: Manaforge Omega](https://www.archon.gg/wow/articles/news/wipefest-manaforge-omega),
  [Wipefest: Nerub-ar Palace](https://archon.gg/wow/articles/news/wipefest-nerub-ar-palace); 403 on fetch, from search summaries.)
- **Warcraft Logs** is generic. It has Deaths, Interrupts and Dispels tables and an expression
  filter language (`type = 'applydebuff' and ability.id in (...)`) that guilds use as shared
  "pins" for boss mechanics. Its death statistics apply a **wipe cutoff**: deaths stop counting
  from about 30 s before the pull ends, the cutoff moves to a combat resurrection inside that
  window, and the first death cluster after the cutoff still counts.
  ([Death Statistics](https://articles.warcraftlogs.com/help/death-statistics),
  [Pins](https://de.warcraftlogs.com/help/pins),
  [Intro to Expressions](https://www.archon.gg/wow/articles/help/intro-to-expressions); 403 on fetch, from search summaries.)
  Its replay uses the advanced-log positions.
- **WoWAnalyzer** does per-player spec analysis, not boss mechanics. Raid data is limited to
  timelines: `abilities` (`cast`, `begincast` or `summon`) and `debuffs` to draw on the fight
  timeline (`src/game/raids/index.ts`, `EncounterConfig.timeline`). The comments carry useful
  intent labels, for example "Eradicating Salvo (soak target)", "Dark Matter (spread circles)",
  "Supernova (run away)" and "Criticality (p2 spreads)". `EncounterConfig.softMitigationChecks`
  plus `MitigationCheck.jsx` is a tank "was active mitigation up when this hit landed" check.
  `DispelTracker.tsx` counts the dispels a player made by `extraAbility`. `DeathTracker`,
  `DeathRecapTracker` and `DistanceMoved.tsx` cover deaths and movement; the last reads `x/y`
  from damage-taken, heal and cast events where the player is the subject.
- **Boss mods (BigWigs, DBM)** encode *intent*: role tags (`TANK`, `TANK_HEALER`), stack
  thresholds (Ansurek Gorge `minTauntAmount = 4`), soak and spread notes, and berserk timers.
  They are the best primary source for "what is the mechanic and who is it for". The repo
  already imports DBM declarations as source evidence (`docs/OPERATIONS.md`, "Import DBM Source
  Annotations"). BigWigs is not imported yet and has richer annotations.

## Taxonomy

The "Silver today" column uses this scale:

- **Yes:** an existing table holds every input.
- **Partial:** some inputs exist; the named addition completes it.
- **No:** needs new silver or bronze work.

### Player-level failure kinds

| # | Kind | Combat-log signature | Example mechanic (spell ID, source) | How existing tools detect it | Criterion type | Silver today |
|---|---|---|---|---|---|---|
| 1 | **Avoidable damage** (ground effects, dodgeable frontals, lines, waves) | `SPELL_DAMAGE` or `SPELL_PERIODIC_DAMAGE` (also `_MISSED` for absorbed or immune) from an NPC to a player with the mechanic's spell ID. Count hits per player. Exclude the targeted player when the spell is "targeted plus splash" | Vorasius *Void Breath* `1256855`, Chimaerus *Rending Tear* `1272726` (DBM frontal warning), Gallywix *Sabotage Zone* `1215209` (BigWigs listens on `SPELL_PERIODIC_DAMAGE`) | Wipefest per-boss avoidable insights with target exclusions; WCL damage-taken by ability or expression pins | `avoidable` (supported) | **Yes:** `damage_taken`, `damage_taken_event` |
| 2 | **Missed interrupt** | NPC `SPELL_CAST_START` of an interruptible spell, then either `SPELL_INTERRUPT` (`extraSpellId` = that spell) or `SPELL_CAST_SUCCESS` (missed) | Rasha'nan *Acidic Eruption* `452806` (BigWigs `SPELL_INTERRUPT`); Gallywix *Total Destruction* `1214369`; Crown *Interrupting Tremor* `1243743` | Wipefest "who interrupted, were any missed"; WCL Interrupts table | `interrupt` (provisional) | **Yes, with caveat:** `interrupt_opportunity` now pairs `CAST_START` with `SUCCESS` and `INTERRUPT` for catalog spells. Attribution of a miss to a player needs a kick assignment (not in the log) |
| 3 | **Targeted cone, bad aim** | Marker debuff on the aimer, then the boss `SPELL_CAST_SUCCESS` (boss position and facing in the advanced block), then impact `SPELL_DAMAGE` on more players than allowed | Vaelgor & Ezzorak *Dread Breath* `1244221`, marker `1255612`, impact `1244225` | Wipefest bespoke per boss | `targeted_cone` (supported) | **Yes** for hit counting. **No** for geometry (positions dropped) |
| 4 | **Soak failure** (too few soakers, or a player not assigned to soak takes it) | Impact `SPELL_DAMAGE` of the soak spell: distinct targets per cast fewer than required. Often a separate raid-wide *punish* spell fires when under-soaked. A soak debuff such as Execution Sentence "Soaked" `1249008`/`1249024` marks each soaker | Ulgrax *Carnivorous Contest* `434803` (BigWigs "Soak"); Plexus Sentinel *Eradicating Salvo* `1219531`, target `1219607` (WoWAnalyzer "soak target"); Lightblinded Vanguard *Execution Sentence* `1276368`; Chimaerus *Alndust Upheaval* `1262289` | Wipefest "who soaked which instance" on Gallywix | `soak` (observation only; no fact semantics) | **Yes:** `damage_taken_event` groups hits by `spell_id` and timestamp window. `debuff_application` holds soak debuffs. Required-soaker count must be authored per difficulty |
| 5 | **Spread failure** (debuff explosion or circle overlapping others) | The same spell hits one player several times at one timestamp, or one player's debuff expiry damages other players. The 12.x `AOE` marker helps | Dimensius *Dark Matter* `1230979` ("spread circles", WoWAnalyzer); Midnight Falls *Criticality* `1281184` ("p2 spreads"); Bloodbound Horror spread `452237` (BigWigs) | Wipefest Undermine rule: damage only where a player was hit more than once at the exact same time | `spread` (observation only) | **Partial:** `damage_taken_event` has per-hit timestamps but not the source player of a debuff explosion (`source_guid` is usually the NPC). Positions would make it exact |
| 6 | **Stack failure** (split damage not shared, player outside the group) | Shared-damage `SPELL_DAMAGE`: a hit on too few targets (the per-target amount rises), or the player outside the group takes an unsplit hit | Vaelgor & Ezzorak *Gloom* `1245391` (BigWigs "possibly soak", group share) | Wipefest per boss | `stack` (observation only) | **Partial:** `damage_taken_event` (count of targets per cast, amount per target). Needs an authored expected count |
| 7 | **Tank swap / taunt failure** | The tank's stacking debuff from `SPELL_AURA_APPLIED_DOSE` goes past the threshold before the other tank's taunt (`SPELL_CAST_SUCCESS` of a taunt spell, or a boss target change). Often ends in tank death to the next hit | Ansurek *Gorge* `443336` (swap at 4 stacks, BigWigs `minTauntAmount = 4`); Ky'veza *Void Shredders* `440377` (swap each cast); Ulgrax *Brutal Crush* `434697` and *Tenderized* `434705`; Vorasius *Shadowclaw Slam* `1241808` | Wipefest "tank swaps"; BigWigs stack messages | `tank_mechanic` (observation only) | **Yes** for stack count (`debuff_application` dose rows have `stack_count`). **No** for taunt casts (casts not in silver) |
| 8 | **Tank buster without mitigation** | A big tank hit (`SPELL_DAMAGE` with the tank-buster ID) while no active-mitigation or defensive buff is up | Vexie *Tank Buster* `465865`/`459627`; Stix *Demolish* `464112`; Belo'ren *Guardian's Edict* `1260763` | WoWAnalyzer `MitigationCheck` (per-boss physical and magical check list); Wipefest tank insights | `tank_mechanic` (observation only) | **Yes:** `damage_taken_event` plus `defensive_buff_window` (buff windows by category) and `survival_action` |
| 9 | **Dispel failure** (too slow, not done, or dispelled in the wrong place) | `SPELL_AURA_APPLIED` of the dispellable debuff, then `SPELL_DISPEL` (`extraSpellId` = debuff) or `SPELL_AURA_REMOVED` at full duration (not dispelled). Positional dispels need the dispel target's position, or the follow-up effect on the right NPC | Silken Court *Stinging Swarm* `438677` (dispel near Anub'arash for *Stinging Delirium* `456245`); Averzian *Void Marked* `1280013` with *Lingering Darkness* `1280075` after dispel; Gallywix *Lumbering Rage* enrage dispel (BigWigs `Dispeller("enrage")`) | Wipefest "dispels" and "debuff durations"; WCL Dispels table; WoWAnalyzer `DispelTracker` (counts by dispelled spell) | **None** (catalog uses `healer_mechanic` for Void Marked) | **Partial:** `debuff_application.duration_ms` gives time to removal. `SPELL_DISPEL` is not in silver, so who dispelled is unknown |
| 10 | **Fixate failure** (the fixating add catches its target, or is not kited) | `SPELL_AURA_APPLIED` fixate on a player from an add, then damage from that add's spell or `UNIT_DIED` | Ovi'nax *Fixate* `442250` (worms); Mug'Zee *Fixate* `472354` (mines); Vorasius *Fixate* `1254113` | BigWigs say and fixate alerts; Wipefest per boss | **None** (could be an `avoidable` variant scoped to the fixated player) | **Partial:** `debuff_application` plus `damage_taken_event` (source NPC GUID ties the hit to the add) |
| 11 | **Debuff mishandling** (stacks too high, wrong colour or charge, not cleared, wrong side) | Debuff `stack_count` past a threshold, a wrong-polarity debuff paired with a hit, or a debuff held past its safe duration | Belo'ren *Voidlight Convergence* `1242515` (colour swaps) with Light and Void dive debuffs `1241292`/`1241339`; Cauldron high-stack debuffs (BigWigs `HIGH_STACKS`); Araz `highStacks` | Wipefest "debuff durations" | **None** | **Yes:** `debuff_application` (stack, duration). Pairing rules must be authored |
| 12 | **Positional failure** (bad drop location, knocked off the platform, wrong side, too close) | Advanced-block `positionX/Y/uiMapID` on the player at hit or cast time; `ENVIRONMENTAL_DAMAGE` *Falling* and a death (knocked off); distance from the boss's position | Dimensius *Reverse Gravity* `1243577`, *Airborne* `1243609`; Araz *Mark of Power* `1228454` (BigWigs XXX "too close"); Fractillus *Shattershell* wall targets `1227373` | WCL replay; WoWAnalyzer `DistanceMoved`; Wipefest bespoke (Fractillus "Crystal Walls") | **None** (`targeted_cone.position_evidence` reserves it) | **No:** the NIF drops `positionX/Y`. `ENVIRONMENTAL_DAMAGE` is in `damage_taken_event` |

### Encounter-level wipe conditions

| # | Kind | Combat-log signature | Example (spell ID, source) | How existing tools detect it | Criterion type | Silver today |
|---|---|---|---|---|---|---|
| 13 | **Death cascade / wipe trigger** (first deaths decide the pull) | The ordered `UNIT_DIED` list for players; the killing blow and recap per death; `ENCOUNTER_END success=0`. The first 1-3 deaths, joined to the mechanic catalog, name the wipe cause | Any. Real log: player death at 10:47:13 before Nek'zali `ENCOUNTER_END …,0,13353` | WCL wipe cutoff (deaths from about 30 s before the end are ignored); Wipefest "ignore after N deaths" | **None** (encounter-level fact, not a criterion) | **Yes:** `silver.death` (killing blow, `damage_recap`, `window_events`). `dim_encounter` holds the outcome |
| 14 | **Berserk / enrage timer** | `fightTime` reaches the authored berserk time, or the boss casts its enrage spell (`SPELL_CAST_SUCCESS`, `SPELL_AURA_APPLIED` buff on the boss), then a cascade of deaths | Sentinels berserk 540 s / 420 s (BigWigs `Sentinels.lua`); Ovi'nax `Berserk(540)`; Sikran 481/391 s; Coiled Altar *March of the Damned* `1316797` | BigWigs berserk bars; WCL shows boss % at wipe | **None** | **Partial:** `dim_encounter` duration plus outcome. The enrage cast and buff are not in silver |
| 15 | **DPS check** (boss %, shield or intermission not broken, add not killed in time) | Boss HP at `ENCOUNTER_END` (advanced block on the last damage to the boss); a shield aura removed late or not at all; an NPC `UNIT_DIED` missing before the punish cast | Chimaerus *Consume* `1245396` (adds left alive feed the boss: BigWigs "finish adds"; *Cannibalized* `1245844`); Crown *Cosmic Barrier* `1246918` | WCL boss % per pull; Wipefest enemy-healing insight | **None** | **Partial:** `damage_done` aggregates player damage per NPC GUID. No boss-HP, NPC death or spawn rows |
| 16 | **Healing check / heal absorb** | Raid-wide `SPELL_DAMAGE` pulses with `SPELL_HEAL_ABSORBED` against a heal-absorb aura; deaths during a healing window; `absorbed` amounts | Ovi'nax *Experimental Dosage* `442660` ("was rupture/healing absorb"); Ansurek *Liquefy* tank heal absorb (Mythic Trap); Chimaerus *Consuming Miasma* `1257087` | Wipefest per boss; WoWAnalyzer healer modules (per spec) | `healer_mechanic` (observation only) | **No:** heals and heal-absorbed events are not in silver (only `survival_action` heals). `absorbed` is kept on damage hits |

Add control and priority (wrong target, adds alive too long, adds reaching the boss) belongs
across kinds 10 and 15. The evidence is `SPELL_SUMMON` or the first appearance of the add's GUID,
its `UNIT_DIED`, and player damage per NPC. Examples: Belo'ren *Embers of Belo'ren* `1241282`
("adds", BigWigs), Silken Court *Call of the Swarm* `438801`, Naazindhri *Soulweave* add spawn
`1219040` (WoWAnalyzer), and Chimaerus *Consume* `1245396`. Silver has damage per NPC GUID in
`damage_done` but not NPC lifetimes. **Gap:** no type, and no add-lifetime silver.

## Mapping onto `rules.mechanic_criterion`

| Type | Kinds it covers | State | Gap |
|---|---|---|---|
| `avoidable` | 1, and 10 when scoped to the fixated player | Supported | Fixate scoping needs a "target has debuff X" guard |
| `interrupt` | 2 | Provisional (`#61`) | Missed-kick attribution without assignments is group-level only |
| `targeted_cone` | 3 | Supported | Geometry wants positions |
| `soak` | 4 | No semantics | Threshold proposal: `required_targets`, `impact_spell_ids`, optional `punish_spell_id`, `soak_debuff_spell_ids`, `window_ms` |
| `spread` | 5 | No semantics | `max_targets_per_hit` (simultaneous hits); later `min_distance` with positions |
| `stack` | 6 | No semantics | `min_targets` per cast |
| `tank_mechanic` | 7, 8 | No semantics | Two sub-shapes: `swap_debuff_spell_id` + `max_stacks`, and buster + `requires_mitigation` |
| `healer_mechanic` | 9 (misused), 16 | No semantics | Covers too much: dispel is its own kind |
| **missing: `dispel`** | 9 | — | `debuff_spell_id`, `max_ms_to_dispel`, optional `dispel_near_npc_id` |
| **missing: `debuff_threshold`** | 11 | — | `max_stacks` or `max_duration_ms` |
| **missing: `positional`** | 12 | — | Needs position silver first |
| **missing: `add_control`** | 10, add priority, 15 (adds part) | — | NPC lifetime and spawn silver |
| **not a criterion** | 13, 14, 15, 16 at encounter grain | — | Separate gold fact: `fact_wipe_cause` (encounter grain, ordered first deaths, berserk flag, boss % at end) |

## Silver grain gaps (what to add, smallest first)

1. **`SPELL_DISPEL` with `extraSpellId`** (the NIF already does the same for `SPELL_INTERRUPT`).
   Store one `dispel` row per event (dispeller, target, dispelled spell, time). Volume is tiny:
   208 events in 3M lines.
2. **Taunt and selected NPC casts.** A catalog-gated `cast` event table, like the
   `interrupt_opportunity` gating, for taunts, boss enrage casts and add spawns. The catalog
   already has an `:cast` evidence family with nothing behind it.
3. **NPC lifetime.** First seen, `SPELL_SUMMON`, `UNIT_DIED` for NPCs (`silver.death` filters
   to players), and boss HP at the end from the last advanced block where the boss is the
   target.
4. **Healing.** At least `SPELL_HEAL_ABSORBED` and raid-healing totals over a window, for
   healing checks.
5. **Positions.** Emit `position_x`, `position_y`, `ui_map_id` and `facing` from the advanced
   block (counted from the end of the block). Store them on `damage_taken_event` rows (the
   target's position) and on catalog-gated cast rows (the caster's position and facing). This
   is the costliest change and unlocks kind 12, spread geometry and cone geometry.

## Priority: what to build first

Ranked by how often the kind decides a pull, weighed against detection cost. Frequency is
judged from how many tracked mechanics fall in each kind across the BigWigs modules and the
current catalog: 29 of 30 fact-eligible current-tier criteria are avoidable, and every
Midnight boss carries tank, soak and avoidable mechanics.

1. **Death cascade / wipe attribution (13).** The highest-value question between pulls is
   "why did we wipe". It needs only `silver.death` plus the catalog: join each early death's
   killing blow and `damage_recap` spells to criteria, and apply a WCL-style cutoff. No new
   silver. Gives a new encounter-grain gold fact.
2. **Avoidable damage coverage (1).** The builder exists. The cheap win is catalog breadth:
   real logs are now 12.1.5 Midnight Season 2 (*The Venomous Abyss*: Entombed Sentinels,
   Nek'zali, Twin Fangs and others), and the catalog only covers Season 1. BigWigs modules for
   Venomous Abyss, Sporefall and Kithix are installed locally as source evidence.
3. **Soak under-fill (4).** It is a common wipe cause on every tier (Ulgrax, Plexus Sentinel,
   Gallywix, Vanguard, Chimaerus, Belo'ren), and `damage_taken_event` already supports it.
   Needs `soak` threshold semantics and a builder.
4. **Tank swap stack threshold (7).** `debuff_application` dose rows already hold
   `stack_count`. One builder, with thresholds authored from boss-mod values such as Ansurek
   Gorge 4. A missed swap usually ends in a tank death and a wipe.
5. **Missed interrupts (2).** Finish `#61` semantics. Present the result group-level ("N casts
   of X went through") until kick assignments exist.
6. Spread overlap (5), on the Wipefest "hit more than once at the same time" rule, using
   `damage_taken_event`.
7. Dispel (9). Needs the small `SPELL_DISPEL` silver and a new `dispel` type.
8. Tank buster without mitigation (8). Silver exists; mitigation-spell catalogs per class are
   the cost.
9. Debuff thresholds (11) and fixate (10). Both are authoring-heavy.
10. Berserk and DPS checks (14, 15). Need NPC-lifetime and boss-HP silver.
11. Healing checks (16). Need heal silver.
12. Positional (12). Needs NIF position output and storage. The highest cost, and it also
    upgrades 3 and 5.

## Gaps and caveats

- Wipefest and Warcraft Logs pages could not be fetched (HTTP 403). Their behaviour above is
  taken from search-result summaries of the linked pages. Confirm it against the live pages
  before relying on exact rules (for example the 30 s cutoff).
- The 19-versus-17 advanced-field difference is observed, not documented. Index position fields
  from the end of the block and confirm on one log before shipping.
- BigWigs and the repo disagree on Belo'ren dives: BigWigs labels *Light/Void Dive* `1241292`
  as **soaks**, but `march_on_quel_danas.ex` authors `1241291`, `1241292`, `1241339` and
  `1241340` as `avoidable`. Worth a check against real logs before those criteria emit facts.
- Spell IDs for TWW examples come from BigWigs v427.8 modules. Where BigWigs and Warcraft Logs
  differ by difficulty or ID variant, the log is authoritative.

## Sources

- Blizzard combat-log format: <https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT>
- Wipefest: <https://www.archon.gg/wow/articles/help/how-to-improve-your-raid-with-wipefest>,
  <https://www.archon.gg/wow/articles/news/wipefest-liberation-of-undermine>,
  <https://www.archon.gg/wow/articles/news/wipefest-manaforge-omega>,
  <https://archon.gg/wow/articles/news/wipefest-nerub-ar-palace>
- Warcraft Logs: <https://articles.warcraftlogs.com/help/death-statistics>,
  <https://de.warcraftlogs.com/help/pins>,
  <https://www.archon.gg/wow/articles/help/intro-to-expressions>,
  <https://www.archon.gg/wow/articles/help/practical-expression-examples>
- Tank-swap context: <https://www.icy-veins.com/wow/nexus-princess-ky-veza-raid-guide-in-nerub-ar-palace>,
  <https://www.mythictrap.com/en/nerubar-palace/queen-ansurek/heroic>
- Local: BigWigs v427.8 `BigWigs_TheWarWithin/{NerubarPalace,LiberationOfUndermine,ManaforgeOmega}/*.lua`,
  `BigWigs_TheVoidspire/*.lua`, `BigWigs_TheDreamrift/Chimaerus.lua`,
  `BigWigs_MarchOnQuelDanas/{Beloren,MidnightFalls}.lua`, `BigWigs_TheVenomousAbyss/Sentinels.lua`;
  WoWAnalyzer `0ae77b9e35` `src/game/raids/`, `src/parser/shared/modules/{MitigationCheck.jsx,DispelTracker.tsx,DistanceMoved.tsx}`,
  deleted `src/game/raids/manaforge-omega/*.ts` at `da2a871482^`;
  real log `warcraftlogsarchive/Archive-WoWCombatLog-102526_104340.txt`.
