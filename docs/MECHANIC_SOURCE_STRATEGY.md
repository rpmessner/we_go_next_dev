# Mechanic Source Strategy

## Decision

Use imported combat logs as the primary source of truth for what matters to this
raid team, then enrich observed spells with external source annotations and
commit curated mechanics as code. Do not build a separate source-row review
product. The product loop should be:

```text
Observed spells in current logs
  -> source annotations from journal, boss mods, guide/reminder sources
  -> code-defined raid mechanic catalogs
  -> synced editable rules for supported semantics
  -> gold rebuild
  -> real failures in encounter preview and failures views
```

The old source-row review language should be treated as an implementation
artifact while it exists. New UI and roadmap language should be "observed
mechanics", "source annotations", and "rules".

## Curated Mechanics as Code

Raid mechanics should be defined in code, similar to the existing
`WeGoNext.GameData.Dungeons.*` modules for M+ dungeons. The first raid catalog
entry point is:

- `WeGoNext.GameData.Raids`
- `WeGoNext.GameData.Raids.Voidspire`
- `WeGoNext.GameData.Raids.Dreamrift`
- `WeGoNext.GameData.Raids.MarchOnQuelDanas`
- `WeGoNext.GameData.Raids.MidnightSeason1`

These modules are the curated source for raid mechanics. AI-assisted research,
DBM/WowAnalyzer parsers, Encounter Journal metadata, and observed-log queries
can all help scaffold and validate entries, but the checked-in code is where
manual corrections and overrides should live.

Code-defined mechanics should include:

- encounter id/name and raid context,
- spell id/name,
- mechanic type,
- supporting event family such as `:damage_taken` or `:interrupt_opportunity`,
- source annotations such as `:dbm`, `:wowanalyzer`, `:journal`, or
  `:local_logs`,
- rule threshold where supported,
- `track: false` for known mechanics that are useful context but should not yet
  become failure rules.

`WeGoNext.Rules.sync_raid_mechanics/2` mirrors syncable code-defined mechanics
into editable `rules.mechanic_criterion` rows. Use the database rules as the
editable operational copy, but prefer code changes for durable curated
corrections.

## Source Ranking

### 1. Local Combat Logs

Combat logs are the ground truth for the local analysis loop. If a spell does
not appear in the imported logs, it should not block preview or rule creation.

Primary uses:

- discover spells that actually hit, debuff, kill, or cast in current data,
- rank mechanics by observed count, affected player count, damage, and deaths,
- verify that imported rules produce facts after rebuild.

Limitations:

- logs show what happened, not always what was intended,
- cast spell IDs often differ from damage or debuff spell IDs,
- some mechanics require multiple event families to understand.

### 2. Blizzard Encounter Journal and Game Data

Blizzard journal data is useful for canonical encounter structure, role sections,
tactical text, spell IDs, and names. It is not enough to generate failure rules
on its own.

Evidence:

- The Battle.net developer docs are the official home for WoW game data APIs:
  <https://community.developer.battle.net/documentation/world-of-warcraft/game-data-apis>
- Blizzard's old API docs repository now points developers to the developer
  site: <https://github.com/Blizzard/api-wow-docs>
- Community API discussion notes that journal encounter endpoints expose boss
  names, section structure, tactical `body_text`, and referenced spell IDs, but
  boss mechanic spell details such as precise damage, duration, cooldown,
  targeting, and range are not generally available through the Spell API:
  <https://us.forums.blizzard.com/en/blizzard/t/request-for-dungeon-boss-spell-data-in-battlenet-api/56597>

Primary uses:

- encounter and spell reference metadata,
- role hints from Tank/Healer/DPS/Overview sections,
- localized names and build-scoped references where available.

Limitations:

- official journal data is descriptive, not a full mechanic/failure model,
- boss mechanic spells may not resolve through the normal Spell API,
- text still needs interpretation.

### 3. Boss Mods: DBM and BigWigs

Boss mods are strong reaction sources. They encode what players are expected to
notice: warnings, bars, yells, sounds, target scans, role filters, and timers.
They should annotate observed spells and seed rules only when the observed log
data supports the same semantic.

Sources:

- DBM repository: <https://github.com/DeadlyBossMods/DeadlyBossMods>
- BigWigs repository: <https://github.com/BigWigsMods/BigWigs>

Primary uses:

- high-confidence hints for interrupt, dodge/frontal/move, soak, dispel, tank,
  and role-scoped mechanics,
- encounter and spell IDs for current raid modules,
- timers and warning text as context for preview rows.

Limitations:

- a warning is not always a failure rule,
- warning spell IDs may be cast IDs while failure facts need damage/debuff IDs,
- DBM is all rights reserved, so keep imported data as local metadata and avoid
  copying addon code into the application,
- BigWigs licensing should be verified before storing anything beyond local
  source-derived metadata and provenance.

### 4. WowAnalyzer

WowAnalyzer is useful as a fight-analysis and timeline source, especially for
raid boss spell context. It should not be copied into the runtime path.

Source:

- WowAnalyzer repository: <https://github.com/WoWAnalyzer/WoWAnalyzer>
- The current local checkout is AGPL-3.0-or-later, so keep imports as
  provenance-tracked source metadata and do not reuse runtime code.

Primary uses:

- timeline spell references,
- comments and modules that imply mechanic categories,
- cross-checking source spell IDs against observed logs.

Limitations:

- timelines say an ability happens, not that taking it is a failure,
- AGPL licensing makes direct code reuse undesirable for this project,
- current parser only reads a narrow timeline subset.

### 5. Warcraft Logs

Warcraft Logs is valuable for validation and discovery across reports, but it
should not be required for local operation. The local raw combat log already
contains the event data needed for the core loop.

Source:

- API docs entry point: <https://www.warcraftlogs.com/api/docs>

Primary uses:

- validating spell relationships against uploaded reports,
- comparing whether other groups see the same child damage/debuff spell IDs,
- future optional enrichment when credentials and report access are available.

Limitations:

- requires API credentials and report access,
- does not replace local parsing,
- API access and GraphQL shape are external operational dependencies.

### 6. Guides, MRT Reminders, WeakAuras, and Notes

Human strategy sources are closest to "what should players do", but they are
messy. Use them as optional annotations or manually curated rule input, not as
automatic rule authority.

MRT Reminders are especially relevant because they encode boss, difficulty,
spell IDs, aura triggers, combat-log event triggers, BigWigs/DBM timer triggers,
roles, and player load conditions. Method's guide describes reminders as a way
to create text, bars, raidframe glows, boss-timer triggers, aura triggers, and
combat-log-event triggers:
<https://www.method.gg/method-raid-tools-reminders>

Primary uses:

- manual or guild-specific rule import later,
- source hints for aura/debuff/assignment mechanics,
- validating strategy-specific classifications.

Limitations:

- community packs are user-authored and inconsistent,
- licensing and redistribution vary,
- many reminders encode strategy, not universal failure semantics.

## Near-Term Product Shape

### Observed Mechanics Preview

Build the next UI around observed spells and curated raid mechanics.

For each encounter and spell, show:

- event families: damage taken, damage events, debuff applications, interrupt
  opportunities, deaths nearby,
- observed hit/application/cast counts,
- affected player count,
- total damage and death proximity where available,
- source annotations from Blizzard, DBM, BigWigs, WowAnalyzer, and manual notes,
- current rule status: untracked, tracked, ignored, unsupported.

### Direct Rule Creation

Supported one-click rules:

- Track as avoidable: spell appears in damage taken and source annotations
  strongly indicate dodge, move, frontal, GTFO, or avoid.
- Track as interrupt: spell appears in trustworthy interrupt observations and
  source annotations strongly indicate interrupt.
- Ignore: spell is observed but intentionally not a failure.

Unsupported mechanic types should remain visible as observed/annotated rows
until silver and gold semantics exist.

### Rebuild Behavior

When rules change:

1. update `rules.mechanic_criterion`,
2. promote active rules into `gold.dim_mechanic_criterion`,
3. rebuild `gold.fact_failure`,
4. show updated facts in preview and `/failures`.

Historical immutable rule archaeology is not a near-term requirement. If rules
were improved, recomputing old pulls with better rules is acceptable for this
local coaching tool.

## Implementation Guidance

### Replace Source-Row Workflow

Remove source-row review/override terminology from new UI. Existing source-data
tables can remain temporarily as parsed source rows, but product code should
treat them as source annotations.

Prefer new names like:

- `observed_mechanic`
- `source_annotation`
- `source_mechanic_annotation`
- `observed_spell_rule_status`

### Rule Import Filter

Only auto-create rules when all are true:

1. the spell appears in local silver observations,
2. at least one source annotation supports the mechanic type,
3. gold has fact semantics for that mechanic type,
4. the rule can be deduped by active ruleset, spell, encounter scope,
   difficulty scope, and mechanic type.

Everything else should be shown for manual inspection, not hidden.

### Known Mismatches

- Source cast IDs often differ from damage/debuff IDs. Add spell relationship
  discovery instead of assuming one spell ID is enough.
- Boss mods encode warnings and timers, not universal failure facts.
- Journal data contains tactical text and role sections, not complete spell
  mechanics.
- WowAnalyzer timelines encode encounter chronology, not player failure logic.
- Soak, spread, stack, tank, healer, dispel, and defensive mechanics need
  additional silver/fact semantics before auto-failure.

## Next Board Direction

The immediate implementation should be:

1. Build an observed mechanics read model over current silver tables.
2. Attach source annotations from DBM/WowAnalyzer/reference metadata.
3. Add code-defined raid mechanics and sync observed avoidable damage first.
4. Rebuild facts and show real failures on encounter detail and `/failures`.
5. Add interrupt only after `silver.interrupt_opportunity` semantics are honest.
