# Initiative 7 — Defensives & Consumables (Raid-Lead Questions)

Status: **Active, highest priority.** Linear: WE / 7. Defensives & Consumables.

## Goal

Answer the raid lead's #1 requested question set, verbatim: **"Defensives. And
rocks/pots. For sure those."** Concretely, per pull and per player:

1. **What was used** — personal defensives, healthstones ("rocks"), and health
   potions, with timestamps.
2. **What was talented** — which defensives the player actually had available
   this pull (from `COMBATANT_INFO`).
3. **Rocks/pots** — healthstone and health potion usage (and non-usage).
4. **At each death** — were their defensives on cooldown, or sitting available?
5. **Death window** — what did they use in the seconds before dying; did they
   die *through* a pot or defensive (used it and died anyway)?

## Existing groundwork

- `WeGoNext.GameData.DefensiveBuffs` — hand-authored aura-ID catalog
  (personal/external/immunity), no cooldowns, no talent mapping, no consumables.
- `silver.defensive_buff_window` — aura windows projected from
  `SPELL_AURA_APPLIED`/`REMOVED`, gated by the catalog.
- Per-player **Defensive Coverage** panel in encounter detail (windows vs
  dangerous damage events, covered/uncovered).
- `COMBATANT_INFO` parsing extracts class/spec only; the talent payload is
  dropped.

## Retail-only constraint

Catalog entries must be **current retail (Midnight 12.x)**. Spell IDs verified
against observed events in our own imported retail logs — never taken from
multi-flavor sources (DBM ships Pandaria/Classic mods; MoP Classic IDs drift,
see the workspace AGENTS.md power-type scars). When an ID can't be confirmed
from a real local log or a retail-only reference, it stays out of the catalog
rather than guessed in.

## Layering (medallion)

```text
game-data catalog (casts, auras, cooldowns, charges, talent gates, consumables)
  -> silver usage grain (one row per defensive/healthstone/potion use)
     + talent loadout on player info
  -> death-window analysis (used / died-through / available-but-unused / on-CD)
  -> encounter document section + local detail UI + public mirror
```

Cooldown availability is an **inference** (last use + base cooldown; encounter
start state unknown) and must be labeled as such in read models and UI.

## Tickets

1. **Retail-current defensive & consumable catalog** — expand game data with
   cast IDs, aura IDs, base cooldowns/charges, class/spec/talent association,
   plus healthstone and current-tier health potions (shared potion cooldown
   modeled). IDs verified against real imported logs.
2. **Silver usage grain** — project defensive casts and healthstone/potion
   usage (with heal amount/overheal) into a catalog-gated silver projection;
   not a generic cast warehouse.
3. **Talent loadout from COMBATANT_INFO** — persist the talent payload at
   encounter grain and resolve a per-player "available defensives" set.
4. **Death-window survival analysis** — per death: actions used in the death
   window, active-at-death ("died through"), talented + off-cooldown but unused,
   rock/pot availability.
5. **Surface it** — encounter document section, extend the Defensive Coverage
   panel and death rows locally, and render the same section on the hosted
   public mirror.

## Acceptance

Over a real imported current-tier raid night, the local encounter detail page
and the public mirror can show, without SQL/IEx: per-player defensive and
rock/pot usage for a pull, and for each death whether the player used something
in the death window, died through it, or died with talented defensives and/or a
rock/pot available. Unknown talent data and un-cataloged classes degrade to
explicit "unknown" states, not silent zeros.
