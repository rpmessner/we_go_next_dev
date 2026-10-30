# Sept 6 damage-done evidence

`analysis_damage_done_sept6.txt` contains 139 verbatim direct-player damage lines
and three encounter starts from the Sept 6 retail combat log. It is a bounded
slice, not a complete pull or a DPS/ranking fixture. Select the first damage line
per `(player GUID, target NPC id)` in each of these pulls:

| Encounter | Original timestamp | Hits | Boss damage | Priority damage | Other damage |
|---|---|---:|---:|---:|---:|
| Nymrissa (3379) | 9/6/2026 11:03:00.375-4 | 40 | 516001 | 441162 | 0 |
| Sszorak (3420) | 9/6/2026 11:22:15.759-4 | 35 | 95712 | 0 | 532925 |
| Twin Fangs (3421) | 9/6/2026 12:32:15.482-4 | 64 | 897855 | 447817 | 0 |

The three pulls have disjoint target NPCs. The test splits the parsed slice by
NPC before silver projection and uses the original encounter start timestamps.
PlayerInfo is deliberately absent: the Tool must retain owner GUIDs without a
roster match. Existing silver projection tests cover pet attribution; this Tool
never reattributes pets.

## Independent oracle

`analysis_damage_done_sept6_expected.json` was calculated with Python's `csv`
reader on the raw log text, **not** the NIF, silver projector, or Tool. Strip the
timestamp before the double space. CSV fields are zero-indexed: event type 0,
source GUID 1, target GUID 5, damage amount 28 for SWING_DAMAGE and 31 for
SPELL_DAMAGE / SPELL_PERIODIC_DAMAGE / RANGE_DAMAGE (19-field advanced block).
Use `max(0, int(amount))`, matching silver's raw damage semantics (not WCL
effective damage or an overkill adjustment). Sum by player and target class.
Boss NPCs are 252959, 257347, 257361, 257368; priority NPCs are 253032 and 264023.
All others remain unclassified other, including residual trash on Sszorak:
Venomfang Infuser 261479, Writhing Behemoth 261488, Ravenous Hatchling 261484.
The committed JSON holds exact per-player integer sums; table totals above are
an additional cross-check. No synthetic damage lines were added.

## Target intent

BigWigs supplies boss enable-mob IDs and add annotations, not a ready-made
priority ranking. The catalog authors Bubblefin Shorerunner and Spawn of Vexhul
as priority targets: their real-log casts are Alluring Bubble 1260012 and
Corrosive Spit 1291478 / Eternal Venom 1290336, respectively. Their NPC identities
are verified; priority intent is authored knowledge, not an official WCL exclusion
rule. Other damage is not itself a padding verdict. No time-window inference or
population comparison is supported.
