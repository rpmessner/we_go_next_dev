# Product Vision

WeGoNext is a local-first WoW combat-log diagnostic tool for raid progression and Mythic+ review. It runs next to the game and answers what happened on the last pull while the information is still actionable.

It is not a damage meter. WoW already has aggregate damage, healing, and interrupt views. WeGoNext focuses on the context those views leave out:

- what killed a player,
- which mechanics became failures,
- whether the group is improving across pulls,
- which deaths or missed interrupts matter,
- what a player or raid lead should adjust before the next pull.

## Primary User

The first user is Mittwoch, Warlock for Hand of Algalon on Wyrmrest Accord US, dogfooding during raid progression and Mythic+.

The product should work as a local second-monitor tool before it tries to become a hosted service or in-game addon ecosystem.

## Priority Stack

1. Raid and Mythic+ diagnostic loop after a pull or dungeon segment.
2. Personal improvement over repeated attempts.
3. Raid-lead review of mechanic failures and group trends.
4. Shareable or private reports for guild use.
5. Optional in-game addon distribution.

## Between-Pull Model

WoW buffers combat log writes during combat. WeGoNext should optimize for the moment after an encounter or pull ends, when the log flushes and feedback is useful during runback, rebuff, or dungeon downtime.

The app should make the current state obvious:

- which log is loaded,
- whether the medallion data is ready,
- whether rules exist and are active,
- what needs to be rebuilt when logic changes.

## Product Direction

The original app proved the parsing and analyzer ideas with direct LiveView tabs and cached analyzer output. The current product direction is a medallion-backed analytics application:

- import logs once,
- project stable silver rows,
- rebuild gold facts from silver and rules,
- build UI views from silver/gold read models,
- infer future mechanics from source data without making inferred evidence active truth.

## Non-Goals

- Do not become a replacement for Warcraft Logs.
- Do not warehouse every WoW data table before a downstream workflow needs it.
- Do not require manual tagging of every mechanic forever.
- Do not treat DBM, Warcraft Logs, or datamined sources as unreviewable active truth.
- Do not optimize for true in-combat real-time alerts; the game client and in-game addons own that space.
