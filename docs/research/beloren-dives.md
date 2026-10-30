# Belo'ren Dive classification (we-sja)

## Decision

Light/Void Dive is a **soak**, not generic avoidable damage. Keep `1241291`
(Light impact) and `1241340` (Void impact) as `soak` / `damage_taken` observations.
`1241292` and `1241339` are the corresponding target-marker debuffs in these logs;
keep them as `soak` / `debuff_application`. None should seed failure criteria
until soak semantics exist (`we-1xz`). Do not blame every participant for soaking.

Evidence: installed BigWigs `BigWigs_MarchOnQuelDanas/Beloren.lua` labels
`1241292` Light/Void Dive as Soaks. Only IDs/annotations were used; no code copied.
The real Heroic kills show repeated impacts on groups, not isolated avoidable hits.
All 119 player Dive damage hits and 8 player Dive misses have the `AOE` suffix;
none have `ST`. AOE alone does not prove a soak; the boss-mod annotation and
repeated group participation supply the interpretation.

Expected required-soaker count is **not established** by these logs. Observed
successful-pull groups range from 6–9 including misses. Do not infer a minimum
or diagnose under-fill from this sample; difficulty and colour/assignment
semantics still need authoring. Pull 141's two-target impact is not evidence
that those two players failed by taking damage.

Separate Light Patch `1241840` / Void Patch `1241841` are periodic ground-effect
hazards (BigWigs marks both `underyou`), observed seconds after impact and later
in irregular per-player ticks. These are the defensible avoidable components,
not any of the four Dive IDs. There is no separately observed Dive punish damage
ID in this sample. Patch coverage is not added by this narrowly scoped correction;
Incubation of Flames `1242792` and Death Drop `1246709` remain unchanged.

## Real-log provenance

Warehouse encounter IDs below are `gold.dim_encounter.id`, all Heroic (15).
Read byte ranges from `gold.dim_encounter` using `BEGIN READ ONLY`; read raw data
from the archive copies of combat-log files 12 and 13:

- `Archive-WoWCombatLog-052326_105407.txt`: pull 123 bytes
  `190406831..190458445`, pull 124 `190922824..220846219`.
- `Archive-WoWCombatLog-053026_111917.txt`: pull 140
  `151102640..151172658`, 141 `151416258..151704619`, 142
  `152438560..181104622`, 143 `181714394..214252469`.

`we_go_next/test/fixtures/beloren_dives_<id>.txt` retains verbatim encounter
boundaries, COMBATANT_INFO, and all events for the six Dive/Patch IDs. Other
combat events are omitted, not rewritten. Counts were independently obtained
with Python CSV parsing; the regression tests replay through the production NIF,
silver projector, rule sync and gold fact builder.

## Per-cast evidence

Cast = `SPELL_CAST_SUCCESS`, grouped by impact spell and casting Ember GUID;
player hits/misses within 100 ms are distinct participants. `SPELL_ABSORBED` is
not counted again (it can duplicate a damage event's absorption evidence).
`targets` includes `SPELL_MISSED`; `hits` counts only `SPELL_DAMAGE`.

| Pull | Cast time (local) | Impact ID | Targets | Hits | Suffix |
|---|---|---|---:|---:|---|
| 123 | none (25 ms aborted pull) | — | 0 | 0 | — |
| 124 | 12:00:51.841 | 1241291 | 8 | 8 | AOE |
| 124 | 12:01:41.920 | 1241340 | 8 | 8 | AOE |
| 124 | 12:02:51.716 | 1241340 | 8 | 8 | AOE |
| 124 | 12:02:51.716 | 1241291 | 7 | 7 | AOE |
| 124 | 12:03:41.756 | 1241340 | 7 | 7 | AOE |
| 124 | 12:03:41.756 | 1241291 | 7 | 7 | AOE |
| 140 | none (836 ms aborted pull) | — | 0 | 0 | — |
| 141 | 11:56:17.252 | 1241340 | 2 | 1 | AOE |
| 142 | 11:59:38.384 | 1241291 | 7 | 6 | AOE |
| 142 | 12:01:30.314 | 1241291 | 7 | 6 | AOE |
| 142 | 12:01:30.314 | 1241340 | 7 | 7 | AOE |
| 142 | 12:02:20.413 | 1241291 | 8 | 7 | AOE |
| 142 | 12:02:20.413 | 1241340 | 7 | 7 | AOE |
| 143 | 12:06:04.824 | 1241340 | 8 | 8 | AOE |
| 143 | 12:06:54.829 | 1241291 | 9 | 7 | AOE |
| 143 | 12:08:34.747 | 1241291 | 7 | 7 | AOE |
| 143 | 12:08:34.747 | 1241340 | 6 | 4 | AOE |
| 143 | 12:09:24.726 | 1241291 | 8 | 8 | AOE |
| 143 | 12:09:24.738 | 1241340 | 6 | 6 | AOE |

## Current false facts and coordinator rebuild

Read-only warehouse snapshot, before correction:

| Pull | Criterion ID | Spell | Player/criterion rows | Failure count |
|---|---:|---:|---:|---:|
| 124 | 41 | 1241291 | 15 | 22 |
| 124 | 44 | 1241340 | 15 | 23 |
| 141 | 44 | 1241340 | 1 | 1 |
| 142 | 41 | 1241291 | 10 | 19 |
| 142 | 44 | 1241340 | 10 | 14 |
| 143 | 41 | 1241291 | 15 | 22 |
| 143 | 44 | 1241340 | 11 | 18 |

Total: **77 fact rows, 119 blamed hits**. No other failure facts existed for
these six pulls. No facts existed for the marker aura IDs. A fresh-version
replacement emits zero current facts, but retains the 77 old facts as archived
ruleset history. To physically remove those 77 rows, retire the old Dive rules
and promote/rebuild that same ruleset (see below).

**Important:** sync is additive; omitted catalog criteria are not deactivated.
A default same-version sync/rebuild alone retains the old false positives.
The coordinator must select a fresh current-tier ruleset version (e.g. `version: 2`
if unused), activating/promoting it before rebuilding, or explicitly retire the
old Dive rules/snapshots. The fixture regression proves fresh-version replacement
emits zero current facts while retaining old history. Do not report same-version
sync alone as sufficient, or fresh-version replacement as physical deletion.

For physical removal within the existing ruleset: after sync, use
`Rules.list_mechanic_criteria(ruleset)` to select ONLY boss `3182` / spell IDs
`1241291`, `1241292`, `1241339`, `1241340`; call
`Rules.update_mechanic_criterion(criterion, %{active: false})` on those entries,
then `Rules.promote_ruleset_to_gold(ruleset)` and rebuild the encounters against
that ruleset. Its rebuild deletes existing facts before inserting new ones.
This retirement is an explicit coordinator operation, not a catalog-sync feature.
No shared dev database mutations were performed in this build session.
