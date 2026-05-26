# Current-Tier Mechanic Coverage Audit

Date: 2026-05-23

## Scope

This audit covers code-defined raid mechanics for the active live tier:

- The Voidspire
- The Dreamrift
- March on Quel'Danas

It also records PTR reconnaissance for Sporefall. PTR notes are reference-only
until the encounter is stable enough to add to the live catalog.

## Live-Tier Findings

The local `source_data` evidence tables currently contain 135 DBM mechanic
candidates and 81 WowAnalyzer timeline candidates. Every DBM/WowAnalyzer
current-tier raid candidate is represented in the checked-in catalog after this
audit.

Reference metadata tables are currently empty, so this pass relied on:

- Code-defined catalogs under `WeGoNext.GameData.Raids.*`
- Imported-log silver observations in `silver.damage_taken_event` and
  `silver.debuff_application`
- DBM and WowAnalyzer source-data rows

The catalog now exposes 164 current-tier mechanics:

- The Voidspire: 96
- The Dreamrift: 20
- March on Quel'Danas: 48

Thirty current-tier mechanics are fact-eligible today:

- 29 `avoidable` damage criteria
- 1 `targeted_cone` criterion

## Added Live Catalog Coverage

This pass added imported-log damage/debuff outcome rows where the previous
catalog only had a cast/warning spell or no local outcome row.

Failure-eligible additions:

- Imperator Averzian `1260718` `Oblivion's Wrath`: direct observed damage for
  DBM dodge/orb warning `1260712`.
- Vorasius `1275558` `Parasite Expulsion`: direct observed damage for DBM
  movement/add warning `1254199`.
- Crown of the Cosmos `1233826` `Void Expulsion`: direct observed damage for
  WowAnalyzer area-denial spell `1233819`.

Unsupported or not-yet-fact-eligible additions:

- Soak outcome: Imperator Averzian `1249262` `Umbral Collapse`.
- Tank outcomes: Vorasius `1241808`, `1272328`, and `1281954`
  `Shadowclaw Slam`.
- Explicit non-generic observed damage/context rows for Dark Upheaval,
  Lingering Darkness, Primordial Power, Dark Energy, Blisterburst, Midnight
  Manifestation, Dark Radiation, Searing Radiance, Avenger's Shield, Light
  Infusion, Silverstrike Arrow, Cosmic Barrier, Silverstrike Barrage, Void
  Barrage, Void Remnants, Consume, Caustic Phlegm, Cannibalized Essence, and
  Lingering Miasma.

Those unsupported rows are intentionally cataloged as `:unknown`,
`:tank_mechanic`, or `:soak` instead of generic `:avoidable` until their fact
semantics are defensible.

## PTR Sporefall Reconnaissance

Source quality:

- Blizzard preview: high quality for raid existence, location, boss count,
  difficulties, Rotmire name, and Mythic flexible group size.
- Blizzard PTR raid testing posts: high quality for test windows and Mythic
  15-25 experiment.
- Wowhead PTR database and post-test article: useful spell/journal evidence,
  but still PTR and subject to change.

Stable public facts as of 2026-05-23:

- Sporefall is a single-boss raid in Harandar.
- Boss: Rotmire.
- Difficulties: Raid Finder, Normal, Heroic, Mythic.
- Mythic is being tested as flexible 15-25 players.

Draft mechanics/spells to watch:

- `1221622` `Awaken Fungi`: spawns fungal minions and has local 6-yard burst
  damage around growth locations.
- `1221714` `Poison Burst`: Sporecap cast; interrupt candidate with raid-wide
  Nature damage and stacking periodic damage.
- `1222684` `Cross Fertilization`: Mythic positioning rule when Shroomling and
  Fungling corpses are too close.
- `1222495` `Bursting Doom Shroom`: lethal Mythic failure explosion following
  bad corpse positioning.
- `1221637` `Fungal Bloom`: 100-energy raid damage/add check that turns corpses
  into Bursting Shrooms.
- `1221965` `Bursting Shroom`: add-kill check after Fungal Bloom.
- `1221644` `Fungal Frenzy`: failure context when minions survive Bloom.
- Journal-only watch items: `Putrid Fist` tank swap, `Festering Vines` spread
  or heal target, `Writhing Vines` ground denial, `Bursting Pustules` and
  `Rotting Pustules` healing pressure.

Do not add Sporefall to `WeGoNext.GameData.Raids.*` until local source ingestion
or stable live data gives reliable encounter IDs, spell IDs, and event-grain
semantics.

## Sources

- Blizzard: https://news.blizzard.com/en-gb/article/24272110/prepare-to-face-rotmire-in-the-sporefall-raid
- PTR raid testing: https://www.wowhead.com/blue-tracker/topic/us/ptr-raid-testing-mythic-sporefall-15-25-2302398
- Wowhead first look: https://www.wowhead.com/news/a-first-look-into-sporefalls-raid-boss-on-mythic-difficulty-381668
- Wowhead PTR Awaken Fungi: https://www.wowhead.com/ptr-2/spell=1221622/awaken-fungi
- Wowhead PTR Poison Burst: https://www.wowhead.com/ptr-2/spell=1221714/poison-burst
- Wowhead PTR Cross Fertilization: https://www.wowhead.com/ptr-2/spell=1222684/cross-fertilization
- Wowhead PTR Fungal Bloom: https://www.wowhead.com/ptr-2/spell=1221637/fungal-bloom
- Wowhead PTR Fungal Frenzy: https://www.wowhead.com/ptr-2/spell=1221644/fungal-frenzy
- Wowhead PTR Bursting Doom Shroom: https://www.wowhead.com/ptr-2/spell=1222495/bursting-doom-shroom
- Wowhead PTR Bursting Shroom: https://www.wowhead.com/ptr-2/spell=1221965/bursting-shroom
