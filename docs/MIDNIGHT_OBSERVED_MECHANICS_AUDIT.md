# Midnight Observed Mechanics Audit

Date: 2026-05-25

## Scope

This audit reviews imported Midnight Season 1 raid pulls currently present in
the local medallion warehouse and compares observed silver/gold evidence against
the code-defined raid catalogs under `WeGoNext.GameData.Raids.*`.

Current imported coverage:

| Encounter | Difficulty | Pulls | Pull window |
| --- | ---: | ---: | --- |
| Imperator Averzian | 15 | 2 | 2026-04-12 to 2026-04-12 |
| Imperator Averzian | 16 | 22 | 2026-05-03 to 2026-05-17 |
| Vorasius | 15 | 4 | 2026-04-12 to 2026-04-12 |
| Vorasius | 16 | 16 | 2026-05-09 to 2026-05-17 |
| Vaelgor & Ezzorak | 15 | 4 | 2026-04-12 to 2026-05-23 |
| Fallen-King Salhadaar | 15 | 2 | 2026-04-12 to 2026-04-12 |
| Lightblinded Vanguard | 15 | 7 | 2026-04-12 to 2026-05-23 |
| Crown of the Cosmos | 15 | 18 | 2026-04-12 to 2026-05-23 |
| Belo'ren, Child of Al'ar | 15 | 2 | 2026-05-23 to 2026-05-23 |
| Midnight Falls | 15 | 12 | 2026-05-23 to 2026-05-23 |
| Chimaerus the Undreamt God | 15 | 2 | 2026-05-12 to 2026-05-23 |
| Chimaerus the Undreamt God | 16 | 13 | 2026-05-03 to 2026-05-09 |

The current catalog has 164 Midnight mechanics and 30 fact-eligible rule
criteria. Source-data evidence tables remain scaffolding only: DBM/WowAnalyzer
rows help author code-defined catalog entries, but do not directly define active
rules or facts.

## Method

Evidence used:

- `gold.dim_encounter` for current-tier pull coverage.
- `silver.damage_taken_event` for observed player-targeted damage spell IDs.
- `silver.debuff_application` for observed aura spell IDs.
- `silver.death` for killing blow spell IDs.
- `silver.interrupt_opportunity` only for known code-defined interrupt spell IDs;
  the broader interrupt table still includes noisy player spell rows.
- DBM and WowAnalyzer source-data candidates for source annotations.
- Current code-defined catalog mechanics for coverage and fact eligibility.

## High-Priority Tracking Candidates

These are observed spell IDs that are not currently cataloged for their
encounter and are worth reviewing before implementing task #84.

| Priority | Encounter | Spell | Evidence | Proposed type | Rationale |
| ---: | --- | --- | --- | --- | --- |
| 1 | Midnight Falls | `1254076` Heaven's Glaives | 807 hits, 11 pulls, 21 players, 49.7M damage, 10 killing blows | `avoidable` damage outcome | Catalog tracks cast `1253915` as avoidable from DBM/WowAnalyzer. This looks like the observed damage outcome needed for actual failures. |
| 2 | Midnight Falls | `1282458` Radiance | 1,034 hits, 9 pulls, 21 players, 77.6M damage, 75 killing blows | needs source review; likely phase or soak/fail damage | Very death-heavy and currently uncataloged. Likely tied to a major Midnight Falls phase/mechanic rather than generic ambient damage. |
| 3 | Midnight Falls | `1254256` Naaru's Lament | 273 hits, 8 pulls, 21 players, 32.5M damage, 42 killing blows | needs source review | Death-heavy and appears across most Midnight Falls pulls. Candidate for explicit catalog row even if fact semantics remain unsupported. |
| 4 | Midnight Falls | `1249797` Shattered Sky | 39,383 hits, 12 pulls, 21 players, 584.9M damage, 8 killing blows | `unknown` damage outcome | Catalog has DBM cast `1249796` with `aesoon`; observed outcome is massive raid damage. Add as a non-failure catalog row unless review proves player-failure semantics. |
| 5 | Crown of the Cosmos | `1281707` Echoing Darkness | 35,580 hits, 18 pulls, 57 players, 447.7M damage, 93 killing blows | needs source review | Highest uncataloged death source in Crown logs. No DBM/WowAnalyzer source row matched this exact ID; investigate relationship to existing Crown mechanics. |
| 6 | Crown of the Cosmos | `1237040` Voidstalker Sting | 17,353 hits, 10 pulls, 56 players, 339.5M damage, 48 killing blows | needs source review | High-volume and death-heavy. Not in DBM/WowAnalyzer source candidates by exact spell ID. |
| 7 | Crown of the Cosmos | `1232470` Grasp of Emptiness | 1,196 hits, 18 pulls, 48 players, 44.6M damage | likely `unknown` or positional/debuff mechanic | WowAnalyzer has related debuff evidence `1260027` for Grasp of Emptiness obelisks. Needs mapping from observed outcome to source/cast context. |
| 8 | Chimaerus the Undreamt God | `1262305` Alndust Upheaval | 209 hits, 14 pulls, 33 players, 25.3M damage | `soak` damage outcome | Catalog tracks Alndust Upheaval cast IDs `1246149` and `1262289` as soak. Add observed damage outcome and keep non-fact-eligible until soak semantics exist. |
| 9 | Vorasius | `1241807` Shadowclaw Slam | 57 hits, 5 pulls, 31 players, 28.2M damage, 41 killing blows | `tank_mechanic` damage outcome variant | Catalog already has related Shadowclaw Slam damage variants `1241808`, `1272328`, and `1281954`. This is likely another observed outcome variant. |
| 10 | Vorasius | `1258968` Focused Aggression | 71 hits, 6 pulls, 20 players, 79.4M damage, 55 killing blows | tank/fixate mechanic review | Death-heavy and high individual hit size. Needs source context before deciding failure semantics. |
| 11 | Vaelgor & Ezzorak | `1245302` Void Howl | 392 hits, 3 pulls, 35 players, 41.0M damage, 13 killing blows | `unknown` damage outcome | Catalog has DBM/WowAnalyzer cast `1244917` Void Howl. Add observed outcome as non-failure unless source review proves avoidable/failure behavior. |
| 12 | Vaelgor & Ezzorak | `1285954` Nullzone Implosion | 2,324 hits, 3 pulls, 35 players, 23.8M damage | needs source review | Likely tied to Nullzone state; catalog has `1244672` Nullzone debuff but not this observed outcome. |

## Midnight Falls Notes

Midnight Falls is the most immediate gap because recent imported pulls are
concentrated there and several observed spell IDs are uncataloged.

Important exact-ID source annotations:

- DBM marks `1253915` Heaven's Glaives as movement/avoidable, while logs show
  `1254076` as the observed damage outcome. This is the clearest next
  fact-eligible addition.
- DBM marks `1266388` Dark Constellation and `1279420` Dark Quasar as
  movement/avoidable. Neither appeared in the top observed damage rows by exact
  ID, so outcome mapping still needs review.
- WowAnalyzer marks `1251331` Dark Archangel, `1276525` Heaven & Hell, and
  `1284528` Galvanize as movement/avoidable source abilities. Observed damage
  IDs include `1282458` Radiance, `1251649` Disintegration, `1254398`
  Glimmering, and `1285827` Overkill Current; those need mapping before they
  become facts.
- Existing spread candidate `1281184` Criticality is cataloged as `:spread`;
  fact semantics are not implemented yet.

## Already Cataloged But Unsupported

These observed rows are already in the catalog but are intentionally not
fact-eligible because their semantics are not implemented or not defensible as
generic avoidable damage.

| Encounter | Spell | Current type | Evidence |
| --- | --- | --- | --- |
| Imperator Averzian | `1259903` Dark Upheaval | `unknown` | 99,124 hits, 23 pulls, 2.19B damage |
| Vorasius | `1272950` Primordial Power | `unknown` | 58,109 hits, 17 pulls, 641.4M damage |
| Chimaerus the Undreamt God | `1246653` Caustic Phlegm | `unknown` | 17,158 hits, 14 pulls, 405.9M damage |
| Vorasius | `1280101` Dark Energy | `unknown` | 15,112 hits, 15 pulls, 323.3M damage |
| Vorasius | `1259186` Blisterburst | `unknown` | 4,076 hits, 15 pulls, 294.1M damage |
| Vorasius | `1241808` Shadowclaw Slam | `tank_mechanic` | 1,442 hits, 16 pulls, 250.9M damage |
| Vorasius | `1272328` Shadowclaw Slam | `tank_mechanic` | 2,553 hits, 16 pulls, 230.2M damage |
| Chimaerus the Undreamt God | `1273112` Consume | `unknown` | 1,768 hits, 12 pulls, 211.4M damage |
| Imperator Averzian | `1249262` Umbral Collapse | `soak` | 2,364 hits, 21 pulls, 134.9M damage |
| Crown of the Cosmos | `1246925` Cosmic Barrier | `unknown` | 9,671 hits, 10 pulls, 125.8M damage |

These should feed task #86 rather than task #84 unless a narrow existing fact
builder can support them.

## Current Fact-Ready Observations

These observed damage rows already map to fact-eligible mechanics and can be
used as regression checks when expanding coverage:

| Encounter | Spell | Type | Evidence |
| --- | --- | --- | --- |
| Vorasius | `1275558` Parasite Expulsion | `avoidable` | 3,609 hits, 15 pulls, 224.6M damage |
| Crown of the Cosmos | `1233826` Void Expulsion | `avoidable` | 4,763 hits, 16 pulls, 175.8M damage |
| Imperator Averzian | `1260718` Oblivion's Wrath | `avoidable` | 210 hits, 19 pulls, 59.1M damage |
| Lightblinded Vanguard | `1246765` Divine Storm | `avoidable` | 337 hits, 7 pulls, 24.3M damage |
| Lightblinded Vanguard | `1248652` Divine Toll | `avoidable` | 70 hits, 6 pulls, 11.6M damage |

Known interrupt observations for cataloged interrupt spells:

| Encounter | Spell | Opportunities | Missed | Successful |
| --- | --- | ---: | ---: | ---: |
| Crown of the Cosmos | `1243743` Interrupting Tremor | 48 | 48 | 0 |
| Chimaerus the Undreamt God | `1249017` Fearsome Cry | 38 | 25 | 13 |
| Imperator Averzian | `1255702` Pitch Bulwark | 120 | 16 | 104 |

## Recommended Task #84 Slice

For the next implementation task, keep the first slice narrow:

1. Add observed outcome catalog rows for the clearest mapped spell pairs:
   `1254076` Heaven's Glaives, `1262305` Alndust Upheaval, `1245302` Void
   Howl, and `1241807` Shadowclaw Slam.
2. Make only `1254076` failure-eligible as `:avoidable` if source review
   confirms player hits are personal failures.
3. Keep soak/tank/unknown rows non-fact-eligible until task #86 defines the
   fact semantics.
4. Review Midnight Falls death-heavy uncataloged rows `1282458`, `1254256`,
   `1251649`, `1254398`, and `1285827` against source annotations and encounter
   detail evidence before promoting any of them to fact-eligible mechanics.

