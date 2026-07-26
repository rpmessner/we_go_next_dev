# Initiative 7 — Defensives & Consumables (Raid-Lead Questions)

Status: **Active, highest priority.** Beads: `we-i7` (we-37…41, we-n7p, we-qop,
we-aub).

## Goal

Answer the raid lead's #1 requested question set, verbatim: **"Defensives. And
rocks/pots. For sure those."** Concretely, per pull and per player:

1. **What was used** — personal defensives, healthstones ("rocks"), and health
   potions, with timestamps.
2. **What was talented** — which defensives the player actually had available
   this pull (from `COMBATANT_INFO`), and which catalog defensives they chose
   *not* to talent.
3. **Rocks/pots** — healthstone and health potion usage (and non-usage).
4. **At each death** — were their defensives on cooldown, or sitting available?
5. **Death window** — what did they use in the seconds before dying; did they
   die *through* a pot or defensive (used it and died anyway)?

## Existing groundwork

- `WeGoNext.GameData.SurvivalActions` — retail-12.x catalog with distinct
  cast/aura IDs, base cooldowns/charges, class/spec and talent association,
  externals, healthstones, and current-tier healing potions. It gates defensive
  aura projection today and is the cast gate for the upcoming usage grain.
- `silver.defensive_buff_window` — aura windows projected from
  `SPELL_AURA_APPLIED`/`REMOVED`, gated by the catalog.
- `silver.death.damage_recap` — currently the last **10 damage events** before
  each death (event-count buffer; replaced by the time-bounded window below).
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

## Death recap design (decided 2026-07-25)

Prior art surveyed: Details! death log (event-count buffer, HP annotated per
row, damage/heal/cooldown-use rows interleaved, `last_cooldown` first-class),
Blizzard native `C_DeathRecap` (last events with hpPercent), WarcraftLogs death
view (fixed-seconds analysis window). Decisions:

### Window

One **fixed-seconds window** (default **10s** before death, configurable, hard
event cap for burst windows with truncation flagged) bounds **both** the recap
event table and the survival-state analysis. Event-count buffers (Details) and
stable-HP anchors were considered and rejected — one window, one mental model.
HP%-per-row annotation (the Details signature) is **deferred** until
advanced-params HP parsing exists (`we-aub`).

### Defensive strip

On each death card, between the player name (left) and killing blow (right):
the character's survival kit as grouped entries.

- **Talented** defensives, each with a state.
- **Untalented** — separate heading listing spec-relevant catalog defensives
  the player did not talent (loadout coaching at a glance; requires `we-39`).
  Unknown talent data renders an explicit *unknown* treatment — never
  fake-untalented, never silent zeros.
- **Rocks/pots** — healthstone and potion entries, same state model, shared
  potion cooldown modeled.
- **Externals received** — external defensives cast *on* the player during the
  window, display-only (availability belongs to the caster, not the deceased).

States: **used/active in window** (rendered per effect kind — see below),
**on cooldown** (always labeled as inference), **available but unused**,
**unknown**. A duration effect still active when the window ends at death reads
as **"died through X"** — the marquee answer.

### Effect kinds

The catalog gains an effect-kind dimension: `:instant_heal`, `:hot`,
`:damage_reduction`, `:absorb`, `:immunity`. Instant effects are point events
("used"); duration effects have active spans and support died-through.

### Window event table

The recap table interleaves, time-ordered within the window:

- **damage taken** rows (current shape),
- **survival-action usage** rows (defensives, rocks/pots, externals received) —
  visually distinct, so the sequence "big hit → pressed Barkskin → bigger hit →
  died" is legible (Details precedent),
- **incoming heal** rows (spell, source, amount, overheal) — behind a checkbox,
  **default off**; captured per-death alongside the recap, *not* a general heal
  warehouse. A window heal total may sit in the table footer.

### Surfaces

**Operator-first.** The document-contract section is designed complete for both
surfaces in `we-41` (per-death survival states + interleaved window events);
the public mirror pass (`we-qop`) is render + real-R2 verification only, no
contract changes. The deaths half of `we-27` is absorbed by this work; that
bead re-scopes to damage-taken summaries.

## Layering (medallion)

```text
game-data catalog (casts, auras, cooldowns, charges, talent gates, effect kinds,
                   externals, consumables)
  -> silver usage grain (one row per use, target-aware for externals)
     + talent loadout on player info
     + time-bounded death window capture (damage + heals + usages per death)
  -> death-window analysis (used/active per effect kind / died-through /
     available-but-unused / on-CD / untalented / unknown)
  -> encounter document section -> local detail UI -> public mirror
```

Cooldown availability is an **inference** (last use + base cooldown; encounter
start state unknown) and must be labeled as such in read models and UI.

## Tickets

1. **`we-37` — Retail-current defensive & consumable catalog** — cast IDs, aura
   IDs, base cooldowns/charges, class/spec/talent association, externals,
   healthstone + current-tier health potions (shared potion cooldown), **plus
   effect-kind dimension**. Implementation largely exists as WIP
   (`survival_actions.ex`); bead closes when it lands with effect kinds.
2. **`we-38` — Silver usage grain** — project defensive casts and
   healthstone/potion usage (with heal amount/overheal) into a catalog-gated
   silver projection; **target-aware** so externals cast on players are rows;
   not a generic cast warehouse.
3. **`we-39` — Talent loadout from COMBATANT_INFO** — persist the talent
   payload at encounter grain and resolve per-player "available defensives"
   (and, by complement against the catalog, untalented ones).
4. **`we-n7p` — Time-bounded death window capture** — replace the last-10-events
   recap with the fixed-seconds window; interleave incoming heals and
   survival-action usages per death. Depends on `we-38`.
5. **`we-40` — Death-window survival analysis** — per death: the full state
   model above, evaluated over the same window. Depends on `we-38`, `we-39`,
   `we-n7p`.
6. **`we-41` — Surface it (operator)** — complete document-contract section +
   operator death-card strip, interleaved table, heal checkbox (default off).
   Depends on `we-40`.
7. **`we-qop` — Public mirror parity** — render the same section on `/r` pages;
   deployed-page verification over a real uploaded raid night. Depends on
   `we-41`.
8. **`we-aub` — Advanced-params HP (deferred)** — Zig parser + bronze fields for
   unit HP; HP% annotation on window rows. Depends on `we-n7p`.

## Acceptance

Over a real imported current-tier raid night, the local encounter detail page
can show, without SQL/IEx: per-player defensive and rock/pot usage for a pull,
and for each death a strip + window table answering — did they use something in
the death window, die through it, have talented defensives and/or a rock/pot
sitting available, or lack the defensive untalented entirely. Externals
received in the window are visible; heal rows toggle on demand. Unknown talent
data and un-cataloged classes degrade to explicit "unknown" states, not silent
zeros. The public mirror reaches parity in `we-qop` with no contract rework.
