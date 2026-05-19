# 2026-05-19: Rules Operations, Medallion Recompute, and WowAnalyzer Source Discovery

## Context

This session continued the medallion frontend and operations work over real local combat-log data. The main goals were to make ruleset state visible from the home page, give the operator explicit controls for rebuilding gold facts and reimporting logs, reassess stale task-board blockers, and investigate whether current encounter detail counts and route wiring were trustworthy.

The session also revisited WowAnalyzer as a possible external source of mechanic evidence after the repository was recloned locally.

## Task Board Updates

- Completed `#52 Add rules status and bootstrap UI`.
- Completed `#53 Add medallion rebuild and recompute controls`.
- Cleared stale completed blockers from several pending tasks:
  - `#32` no longer blocks on completed rules/bootstrap tasks, but remains pending because the encounter detail shell still needs roster basics, failures navigation, and empty slots/tabs.
  - `#38` still blocks on `#36` and `#37`.
  - `#40` still blocks on `#38`.
  - `#44` still blocks on `#42`.
  - `#54` is now unblocked.
- Created `#58 Add WowAnalyzer timeline source import`.

Current unblocked pending work at the end of the session:

- `#32 Build medallion encounter detail shell`
- `#36 Add DBM Bulk Source Import`
- `#37 Ingest Spell and Encounter Reference Metadata`
- `#54 Surface data readiness diagnostics in failures UI`
- `#58 Add WowAnalyzer timeline source import`

`#54` remains the most direct next operator-facing task because it explains empty, stale, and missing medallion states without requiring SQL.

## Rules Operations UI

Task `#52` added a rules operations surface to the home page.

Code changes:

- Added `WeGoNext.Rules.operations_status/0` in `we_go_next/lib/we_go_next/rules.ex`.
- Added a "Rules Operations" panel to `WeGoNextWeb.EncounterLive.Index`.
- Added UI actions to:
  - seed bundled initial rules,
  - activate a ruleset,
  - promote active rules into gold criterion snapshots.

Tests:

- Updated `we_go_next/test/we_go_next/rules_test.exs`.
- Updated `we_go_next/test/we_go_next_web/live/encounter_live_index_test.exs`.

Browser verification exercised the seed, activate, and promote flow. The development page ended with `Initial Mechanic Rules v1` active and two promoted gold criterion snapshots.

## Medallion Recompute Controls

Task `#53` added explicit gold rebuild and force-reimport controls.

Code changes:

- Added `WeGoNext.Gold.Rebuilds` in `we_go_next/lib/we_go_next/gold/rebuilds.ex`.
  - `status/0` reports current gold encounter and failure fact counts.
  - `rebuild_all/1` and `rebuild_encounters/2` share rebuild behavior around `WeGoNext.Gold.FactFailure.RebuildEncounter`.
- Updated `we_go_next/lib/mix/tasks/wgn.rebuild_gold.ex` to use the shared rebuild module while preserving CLI output.
- Added a "Medallion Recompute" panel to the home page.
  - Shows gold encounter and failure fact counts.
  - Shows selected/current log context.
  - Provides a `Rebuild Gold Facts` async action.
  - Enables `Force Reimport Log` when a selected/current log is available.
  - Documents the operational distinction:
    - rebuild gold after rules, promotions, or gold fact logic changes,
    - force reimport after parser or silver projection changes.

Tests:

- Added `we_go_next/test/we_go_next/gold/rebuilds_test.exs`.
- Extended the home LiveView render test to cover the new controls and guidance.

Browser verification confirmed that the panel rendered, `Rebuild Gold Facts` ran across 48 encounters with no row churn, and selecting a log enabled `Force Reimport Log`.

## Commit

The staged implementation changes were committed as:

```text
5914cb2 Add rules and medallion operations controls
```

Commit body:

```text
Add operator UI for rules bootstrap, gold fact rebuilds, and force reimport guidance. Share gold rebuild logic between the CLI task and LiveView controls.

Assisted-by: GPT-5 Tidewave
```

The app worktree was clean after the commit.

## Encounter Detail Route Investigation

The user noticed an active route for `/encounters/:id` and asked whether the encounter list should link to it or whether the show page was vestigial.

Findings:

- `we_go_next/lib/we_go_next_web/router.ex` has `live("/encounters/:id", EncounterLive.Show, :show)`.
- `WeGoNext.EncounterStore` calls `WeGoNext.Gold.EncounterIdentity.attach_dim_encounter_ids/2`.
- `WeGoNext.Gold.EncounterIdentity` bridges transitional public encounter records to `gold.dim_encounter.id` by source fingerprint/file path plus encounter `start_byte`.
- `WeGoNextWeb.Components.EncounterList` renders a link only when an encounter has `dim_encounter_id`; otherwise it renders plain text.

Browser verification on the home page showed current encounter rows linked to detail pages, including `/encounters/36`, `/encounters/37`, `/encounters/38`, and `/encounters/39`.

Conclusion: the route is not vestigial. Links are conditional. If a row is not linked, that indicates the transitional public encounter record did not bridge to a gold encounter dimension row.

## Suspicious Interrupt Count Investigation

The user selected the interrupt count on `/encounters/39`; the displayed value was `4357`, which was implausibly high for a single encounter if interpreted as actual player interrupts.

Source inspection:

- `we_go_next/lib/we_go_next/gold/encounter_detail.ex` counts rows in `WeGoNext.Silver.InterruptOpportunity`.
- `we_go_next/lib/we_go_next/silver/projector.ex` currently projects interrupt opportunities as:
  - `success = true` for player `SPELL_INTERRUPT` events,
  - `success = false` for every NPC `SPELL_CAST_SUCCESS` event.

Database checks for `encounter_dim_id = 39` showed:

- `4349` failed rows,
- `8` successful rows,
- `48` distinct spell IDs among failed rows,
- no duplicate natural-key rows.

Conclusion: the count is not caused by duplicate persistence. It is caused by overbroad silver semantics. The current "Interrupts" label is misleading because failed interrupt opportunities currently mean "NPC cast succeeded", not "a known interruptible cast was missed".

Follow-up needed: task `#34` or an earlier data-readiness step should tighten missed-interrupt semantics so failed rows come from defensible interruptible evidence, such as source-data candidates, observed interrupted spells, or reviewed rules, rather than every NPC `SPELL_CAST_SUCCESS`.

## Rules Discovery and Fact Path Explanation

The user asked what the stored "rules" are and how they are discovered, stored, promoted, and checked against log data.

Current meaning:

- Rules are authored mechanic criteria, not code.
- The seed file `we_go_next/priv/rules/initial_mechanic_rules.json` currently contains curated avoidable-damage rules for:
  - `Arcane Expulsion` spell `1214081`,
  - `Void Burst` spell `1269183`.
- These use `threshold: {"max_hits": 0}`.

Storage path:

- Authored rules live in the `rules` schema:
  - `rules.ruleset`
  - `rules.mechanic_criterion`
- Promotion snapshots active rules into `gold.dim_mechanic_criterion` via `WeGoNext.Rules.promote_ruleset_to_gold/1`.
- Gold facts reference the promoted criterion dimension, not mutable authored rows.

Fact rebuild path:

- `WeGoNext.Gold.FactFailure.Rebuilder` resolves the active ruleset and selected criteria.
- `WeGoNext.Gold.FactFailure.RuleSelector` selects criteria relevant to the encounter.
- Builders derive facts from silver observations:
  - `Builders.AvoidableDamage` joins `silver.damage_taken` to promoted criteria by spell ID and fails players whose hit counts exceed `threshold.max_hits`.
  - `Builders.MissedInterrupt` joins `silver.interrupt_opportunity` rows with `success = false` to interrupt criteria and currently assigns missed-interrupt failures to the raid sentinel player.

The interrupt path is structurally in place, but its silver input currently needs the semantic tightening noted above.

## WowAnalyzer Source Discovery

The user recloned WowAnalyzer for reference. The local repository was found at:

```text
/home/rpmessner/dev/games/wow-addons/WoWAnalyzer
```

The path is capitalized differently from the initially mentioned `~/dev/games/wow-addons/wowanalyzer`.

Important finding:

- WowAnalyzer is licensed `AGPL-3.0-or-later`.

Useful local data was found under:

```text
/home/rpmessner/dev/games/wow-addons/WoWAnalyzer/src/game/raids/vs_dr_mqd
```

Examples:

- `ImperatorAverzian.ts`
  - boss id `3176`
  - timeline abilities and comments for mechanics such as Shadow's Advance, Umbral Collapse, and Void Marked.
- `Chimaerus.ts`
  - boss id `3306`
  - timeline abilities/debuffs including Alndust Upheaval and Consuming Miasma.
- `src/game/raids/index.ts`
  - defines timeline metadata shapes such as `EncounterTimelineAbility` and `EncounterTimelineDebuff`.

Conclusion: WowAnalyzer can be a source-data evidence input for candidate rules, not a direct source of runtime rule logic. A future importer should capture boss IDs, encounter names, spell IDs, event type, comments, source file/line, repository revision, and license/provenance metadata, then map comments and timeline type to tentative mechanic types with confidence for review/promotion.

Because of the AGPL license, avoid copying analyzer runtime code into the medallion fact path. Imported artifacts should be provenance-tracked and reviewed before becoming draft rules.

## Verification

Implementation verification during the session:

```bash
mix test
```

Result after the operations UI and rebuild controls:

```text
93 tests, 5 feature tests, 0 failures, 3 skipped
```

Additional targeted LiveView/browser checks verified the rules operations panel, medallion recompute panel, rebuild action, selected-log reimport enablement, encounter-detail links, and the suspicious interrupt count behavior.

## Follow-Up

- Work `#54` next to surface data readiness diagnostics in the failures UI.
- Continue `#32` for the medallion encounter detail shell, but treat interrupt counts carefully until missed-interrupt semantics are tightened.
- Use `#58` to evaluate WowAnalyzer timeline metadata as a provenance-tracked source-data input.
- Do not promote broad NPC cast-success rows into missed-interrupt failures without stronger evidence that the spell was actually interruptible and assigned.
