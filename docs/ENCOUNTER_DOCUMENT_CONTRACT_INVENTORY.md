# Encounter Document Contract Inventory

Status: WE-25 inventory, docs-only. This records the current contract exposed by
`WeGoNext.Gold.EncounterDetail.get/2`, `WeGoNext.Gold.ObservedMechanics.for_encounter/1`,
and `WeGoNextWeb.EncounterLive.Show`.

The future JSON document should keep public and operator-only values explicitly
marked. Public renderers may read the same document as parser mode, but must hide
operator-only fields.

## Fixture

Chosen real-encounter regression fixture:

| Field | Value |
|---|---|
| `gold.dim_encounter.id` | `124` |
| `source_encounter_key` | `3f43295262920476219423b916e6343cb4b366f271773d6df01995343977ea36` |
| Encounter | `Belo'ren, Child of Al'ar` |
| WoW encounter id | `3182` |
| Difficulty | `Heroic` |
| Start time | `2026-05-23T12:00:31.022000Z` |
| Players | `20` |
| Failure facts | `30` |
| Deaths | `2` |
| Observed spells | `41` |
| Damage taken events | `2910` |

Why this fixture: it is an imported real-log encounter with the highest current
`gold.fact_failure` row count in the local database at inventory time, so it
exercises roster, deaths, failure preview, observed mechanics, damage/debuff
sections, personal summaries, and same-boss personal history.

Serialized size measurement:

- Probe command shape: `mix run` loaded `Gold.EncounterDetail.get(124)` and
  `Gold.ObservedMechanics.for_encounter(124)`, stripped raw source identity from
  the encounter struct, set `personal_pull_summary.selected_player_guid` to
  `nil` to match the character-agnostic document decision, converted structs and
  atoms to JSON-compatible values, and encoded the proposed single encounter
  document with `Jason.encode!/1`.
- Measured size: `129,773` bytes, `126.7 KiB`.
- Assumption: this is an uncompressed minified JSON document containing the full
  detail payload plus observed mechanics. It does not include per-field scope
  wrapper objects, which would increase size; it also excludes raw
  `source_file_path`, `source_head_sha256`, byte offsets, `public_report_id`,
  and Ecto metadata.

## Scope Legend

| Scope | Meaning |
|---|---|
| Public | Safe for the report viewer behind `/r/:slug`; part of the product analysis surface. |
| Operator-only | Useful locally for rebuilding, diagnosing stale/empty states, or authoring rules; public renderer must hide it. |
| Excluded | Returned by the current Ecto struct but should not be serialized into the encounter document. |

## Top-Level Document

The document generator should produce a versioned envelope plus the read-model
payload.

| Field | Scope | Notes |
|---|---|---|
| `schema_version` | Public | Required for renderer compatibility. |
| `generated_at` | Public | Required for stale-document diagnostics. |
| `derivation_version` | Public | Existing failure derivation stamp; needed to detect stale failure facts. |
| `source_encounter_key` | Public | Stable encounter identity and URL key. |
| `encounter` | Mixed | Serialized public subset of `Gold.DimEncounter`; see below. |
| `counts` | Mixed | Current detail counters; see below. |
| `roster` | Public | Encounter-scoped player roster. |
| `deaths` | Public | Death recap rows. |
| `pull_review` | Public | Damage, debuff, and low-damage summaries. |
| `failure_preview` | Mixed | Failure facts are public; readiness diagnostics are operator-only. |
| `interrupt_coverage` | Public | Current interrupt/cast summary, with known silver semantics caveat. |
| `personal_pull_summary` | Public | Per-player summaries for all players; selected player is a UI choice. |
| `observed_mechanics` | Mixed | Observation rows are public enough locally, but rule internals/diagnostics are operator-only. |

## Encounter Metadata

`EncounterDetail.get/2` and `ObservedMechanics.for_encounter/1` both return a
`Gold.DimEncounter` struct today. The document should serialize one canonical
`encounter` object and avoid duplicating it inside `observed_mechanics`.

| Current field | Scope | Notes |
|---|---|---|
| `id` | Operator-only | Local database id. Current local UI displays it as Pull ID; public URLs must use `source_encounter_key`. |
| `source_encounter_key` | Public | Stable document identity. |
| `wow_encounter_id` | Public | Needed for display/debugging and catalog matching context. |
| `name` | Public | Boss/encounter name. |
| `difficulty_id` | Public | Useful structured difficulty value. |
| `difficulty_name` | Public | Rendered in overview. |
| `group_size` | Public | Rendered in overview and roster signal. |
| `instance_id` | Public | Rendered in overview; not operator-local. |
| `start_time` | Public | Rendered in header/overview and used by personal history. |
| `end_time` | Public | Needed for duration and chronology. |
| `success` | Public | Kill/wipe result. |
| `fight_time_ms` | Public | Duration and DPS denominator. |
| `public_report_id` | Excluded | Public app metadata, not encounter analysis. |
| `source_file_path` | Excluded | Local filesystem path. |
| `source_head_sha256` | Excluded | Raw source identity; folded into `source_encounter_key`. |
| `start_byte` | Excluded | Raw parser byte offset; folded into `source_encounter_key`. |
| `end_byte` | Excluded | Raw parser byte offset; folded into `source_encounter_key`. |
| `inserted_at` | Operator-only | Local warehouse metadata. Not needed by renderer. |
| `updated_at` | Operator-only | Local warehouse metadata. Not needed by renderer. |

## Counts

`detail.counts` currently returns:

| Field | Scope | Notes |
|---|---|---|
| `damage_taken_groups` | Operator-only | Warehouse readiness/debug counter. |
| `damage_taken_events` | Operator-only | Warehouse readiness/debug counter; public UI does not render directly. |
| `damage_done_groups` | Operator-only | Warehouse readiness/debug counter. |
| `deaths` | Public | Rendered in stat strip, overview, and Death Recap tab count. |
| `interrupt_opportunities` | Public | Rendered as Interrupt Coverage tab count. |
| `debuff_applications` | Operator-only | Readiness/debug counter; public UI uses debuff rows. |
| `defensive_buff_windows` | Operator-only | Readiness/debug counter; personal defensive summary renders public totals. |
| `players` | Public | Rendered in overview and roster signal. |
| `failure_facts` | Operator-only | Warehouse readiness/debug counter; public UI uses failure preview counts. |

## Roster

Rows are `silver.player_info` structs sorted by role/name.

| Field | Scope | Notes |
|---|---|---|
| `player_guid` | Public | Current UI displays it; report viewers are the intended group audience. |
| `player_name` | Public | Rendered. |
| `class_id` | Public | Rendered as class label/color. |
| `spec_id` | Public | Rendered as spec/role. |
| `item_level` | Public | Rendered in roster. |
| `detected_role` | Public | Rendered. |
| `encounter_dim_id` | Operator-only | Local DB foreign key. |
| `id` | Operator-only | Local DB row id. |
| `inserted_at` | Operator-only | Warehouse metadata. |

## Deaths

`detail.deaths` rows are maps joined from `silver.death`,
`silver.player_info`, and `gold.dim_encounter`.

| Field | Scope | Notes |
|---|---|---|
| `id` | Operator-only | Local death row id. |
| `target_guid` | Public | Rendered. |
| `player_name` | Public | Rendered. |
| `class_id` | Public | Rendered. |
| `spec_id` | Public | Rendered. |
| `detected_role` | Public | Rendered. |
| `died_at_ms_into_fight` | Public | Rendered as fight timestamp. |
| `killing_blow_spell_id` | Public | Used for killing blow display/link. |
| `killing_blow_source_guid` | Public | Current UI renders source identifier. |
| `damage_recap` | Public | Compact damage recap, not raw log lines. |
| `damage_recap[].ms_into_fight` | Public | Rendered. |
| `damage_recap[].spell_id` | Public | Rendered/link target. |
| `damage_recap[].spell_name` | Public | Rendered. |
| `damage_recap[].source_guid` | Public | Rendered fallback/source detail. |
| `damage_recap[].source_name` | Public | Rendered. |
| `damage_recap[].amount` | Public | Rendered. |
| `damage_recap[].overkill` | Public | Rendered. |
| `encounter_name` | Public | Redundant but harmless; can be dropped if top-level encounter is present. |
| `killing_blow` | Public | First recap event or `nil`; renderer convenience. |

## Pull Review

### Damage Done

`detail.pull_review.damage_done` rows:

| Field | Scope | Notes |
|---|---|---|
| `player_guid` | Public | Player identity. |
| `player_name` | Public | Rendered. |
| `class_id` | Public | Rendered as class color. |
| `spec_id` | Public | Rendered. |
| `detected_role` | Public | Rendered. |
| `total_damage` | Public | Rendered. |
| `dps` | Public | Rendered. |
| `hit_count` | Public | Used in personal raw totals and can remain available. |
| `max_hit` | Public | Used in personal raw totals and can remain available. |
| `death_count` | Public | Used for status/eligibility context. |
| `first_death_ms` | Public | Used for status/eligibility context. |
| `early_death` | Public | Explains low-damage warning eligibility. |

`detail.pull_review.low_dps` contains the same fields plus:

| Field | Scope | Notes |
|---|---|---|
| `percent_of_median` | Public | Rendered as Median Share. |

### Damage Taken Spells

`detail.pull_review.damage_taken_spells` rows:

| Field | Scope | Notes |
|---|---|---|
| `spell_id` | Public | Rendered/link target. |
| `spell_name` | Public | Rendered. |
| `total_damage` | Public | Rendered. |
| `hits` | Public | Rendered. |
| `players_hit` | Public | Rendered. |
| `max_hit` | Public | Rendered. |
| `first_seen_ms` | Public | Not currently rendered, but useful for ordering/context. |

### Debuffs

`detail.pull_review.debuffs` has `all`, `boss`, and `player` lists. Each row:

| Field | Scope | Notes |
|---|---|---|
| `spell_id` | Public | Rendered/link target. |
| `spell_name` | Public | Rendered. |
| `source_guid` | Public | Current UI classifies source; acceptable for report viewers. |
| `source_type` | Public | `encounter` or `player`; used by filter/display. |
| `applications` | Public | Rendered. |
| `players_hit` | Public | Rendered. |
| `max_stack_count` | Public | Rendered. |
| `first_seen_ms` | Public | Not currently rendered, but useful for ordering/context. |

## Failure Preview

`detail.failure_preview`:

| Field | Scope | Notes |
|---|---|---|
| `counts.mechanics` | Public | Rendered. |
| `counts.players` | Public | Rendered. |
| `counts.failures` | Public | Rendered in stat strip/overview/failure tab. |
| `counts.damage` | Public | Rendered. |
| `mechanics` | Public | Failure facts and targeted cone context. |
| `diagnostics` | Operator-only | Readiness/stale/empty-state explanation for parser mode. Public renderer should hide or replace with generic empty state. |

`failure_preview.mechanics[]`:

| Field | Scope | Notes |
|---|---|---|
| `criterion_dim_id` | Operator-only | Local/internal fact key. |
| `spell_id` | Public | Rendered/link target. |
| `spell_name` | Public | Rendered. |
| `mechanic_type` | Public | Rendered as human label. |
| `boss_name` | Public | Rendered. |
| `failure_count` | Public | Rendered. |
| `total_damage` | Public | Rendered. |
| `player_count` | Public | Summary. |
| `players` | Public | Per-player failure rows. |
| `targeted_cone_events` | Public | Present only for `targeted_cone`; rendered under the mechanic. |

`failure_preview.mechanics[].players[]`:

| Field | Scope | Notes |
|---|---|---|
| `player_dim_id` | Operator-only | Local gold dimension id. |
| `player_guid` | Public | Rendered. |
| `player_name` | Public | Rendered. |
| `class_id` | Public | Rendered as class color. |
| `spec_id` | Public | Rendered. |
| `detected_role` | Public | Rendered. |
| `failure_count` | Public | Rendered. |
| `total_damage` | Public | Rendered. |

`targeted_cone_events[]`:

| Field | Scope | Notes |
|---|---|---|
| `criterion_dim_id` | Operator-only | Internal join key. |
| `target_guid` | Public | Rendered. |
| `target_name` | Public | Rendered. |
| `marker_ms` | Public | Not currently rendered, but important event timing context. |
| `hit_count` | Public | Rendered. |
| `collateral_count` | Public | Rendered. |
| `total_damage` | Public | Available for detail. |
| `confidence` | Public | Rendered. |
| `hit_players[].player_guid` | Public | Rendered fallback. |
| `hit_players[].player_name` | Public | Rendered. |
| `hit_players[].detected_role` | Public | Rendered. |
| `hit_players[].total_damage` | Public | Rendered when present. |

`failure_preview.diagnostics[]`:

| Field | Scope | Notes |
|---|---|---|
| `severity` | Operator-only | Parser readiness state. |
| `title` | Operator-only | Parser readiness state. |
| `body` | Operator-only | May reveal catalog/rule/rebuild internals. |

## Interrupt Coverage

`detail.interrupt_coverage.spell_coverage[]`:

| Field | Scope | Notes |
|---|---|---|
| `spell_id` | Public | Rendered/link target. |
| `spell_name` | Public | Rendered. |
| `total_opportunities` | Public | Rendered. |
| `successful_interrupts` | Public | Rendered. |
| `missed_casts` | Public | Rendered as cast successes/misses. |
| `target_count` | Public | Rendered. |
| `required_failure_count` | Public | Rendered when the missed interrupt is a tracked failure. |
| `criterion_dim_ids` | Operator-only | Internal fact key ids. |

`detail.interrupt_coverage.player_contributions[]`:

| Field | Scope | Notes |
|---|---|---|
| `interrupter_guid` | Public | Rendered. |
| `player_name` | Public | Rendered. |
| `class_id` | Public | Rendered as class color. |
| `spec_id` | Public | Rendered. |
| `detected_role` | Public | Available for grouping/display. |
| `total_interrupts` | Public | Rendered. |
| `interrupted_spell_count` | Public | Rendered. |
| `by_spell[].spell_id` | Public | Rendered summary. |
| `by_spell[].spell_name` | Public | Rendered summary. |
| `by_spell[].count` | Public | Rendered summary. |

## Personal Pull Summary

The document is character-agnostic: it should include all `players` and set
`selected_player_guid` to `nil` or omit it. Parser mode can preselect from
`Accounts`; public mode defaults to no preselection or first player.

`detail.personal_pull_summary`:

| Field | Scope | Notes |
|---|---|---|
| `selected_player_guid` | Operator-only | Parser-local account preference output; not document data. |
| `players` | Public | Per-player summary rows. |

`players[]`:

| Field | Scope | Notes |
|---|---|---|
| `player_guid` | Public | Rendered. |
| `player_name` | Public | Rendered. |
| `class_id` | Public | Rendered. |
| `spec_id` | Public | Rendered. |
| `detected_role` | Public | Rendered. |
| `damage_done` | Public | Rendered. |
| `damage_done_hits` | Public | Rendered. |
| `max_damage_done_hit` | Public | Rendered. |
| `damage_taken` | Public | Rendered. |
| `damage_taken_hits` | Public | Rendered. |
| `max_damage_taken_hit` | Public | Rendered. |
| `overkill_total` | Public | Useful detail, not currently rendered. |
| `successful_interrupts` | Public | Rendered. |
| `interrupted_spell_count` | Public | Available. |
| `death_count` | Public | Rendered. |
| `first_death_ms` | Public | Rendered. |
| `mechanic_failures` | Public | Rendered. |
| `failure_damage` | Public | Rendered. |
| `failed_mechanic_count` | Public | Available. |
| `performance` | Public | Same-boss recent-pull history. |
| `defensive_analysis` | Public | Defensive coverage around failures/deaths. |

`performance.summary`:

| Field | Scope | Notes |
|---|---|---|
| `pull_count` | Public | Rendered. |
| `kill_count` | Public | Available. |
| `wipe_count` | Public | Available. |
| `total_mechanic_failures` | Public | Available. |
| `total_deaths` | Public | Available. |
| `total_damage_taken` | Public | Available. |
| `avg_failures_per_pull` | Public | Rendered. |
| `avg_damage_taken` | Public | Available. |
| `current_failure_delta` | Public | Rendered. |
| `current_death_delta` | Public | Available. |
| `current_damage_taken_delta` | Public | Rendered. |

`performance.pulls[]`:

| Field | Scope | Notes |
|---|---|---|
| `encounter_dim_id` | Operator-only | Local DB id. Document renderer should use `source_encounter_key` once history rows carry it. |
| `encounter_name` | Public | Available. |
| `difficulty_name` | Public | Available. |
| `start_time` | Public | Rendered. |
| `success` | Public | Rendered. |
| `fight_time_ms` | Public | Available. |
| `player_name` | Public | Available. |
| `class_id` | Public | Available. |
| `spec_id` | Public | Available. |
| `detected_role` | Public | Available. |
| `current` | Public | Rendered. |
| `damage_done` and related totals | Public | Same fields as player totals. |
| `damage_taken` and related totals | Public | Same fields as player totals. |
| `successful_interrupts` / `interrupted_spell_count` | Public | Rendered/available. |
| `death_count` / `first_death_ms` | Public | Rendered/available. |
| `mechanic_failures` / `failure_damage` / `failed_mechanic_count` | Public | Rendered/available. |

`defensive_analysis`:

| Field | Scope | Notes |
|---|---|---|
| `summary.windows_count` | Public | Rendered. |
| `summary.dangerous_events_count` | Public | Rendered. |
| `summary.covered_events_count` | Public | Rendered. |
| `summary.uncovered_events_count` | Public | Rendered. |
| `summary.death_events_count` | Public | Available. |
| `summary.covered_death_count` | Public | Available. |
| `windows[].spell_id` | Public | Defensive used. |
| `windows[].spell_name` | Public | Rendered in active defensives. |
| `windows[].category` | Public | Available. |
| `windows[].source_guid` | Public | Current model carries it; acceptable to viewers. |
| `windows[].started_at_ms` | Public | Used for coverage. |
| `windows[].ended_at_ms` | Public | Used for coverage. |
| `windows[].duration_ms` | Public | Available. |
| `events[].type` | Public | Rendered as event type. |
| `events[].occurred_at_ms` | Public | Rendered. |
| `events[].spell_id` | Public | Available. |
| `events[].spell_name` | Public | Rendered. |
| `events[].mechanic_name` | Public | Rendered fallback/context. |
| `events[].amount` | Public | Rendered. |
| `events[].overkill` | Public | Available. |
| `events[].active_defensives` | Public | Rendered. |
| `events[].covered` | Public | Rendered. |

## Observed Mechanics

`ObservedMechanics.for_encounter/1` returns `encounter`, `mechanics`, and
`counts`. The document should omit the duplicate `encounter` object.

`observed_mechanics.counts`:

| Field | Scope | Notes |
|---|---|---|
| `observed_spells` | Public | Mechanics tab count. |
| `producing_failures` | Operator-only | Rule/fact readiness summary. |
| `active_criteria` | Operator-only | Rule/fact readiness summary. |
| `catalog_tracked` | Operator-only | Rule/fact readiness summary. |
| `catalog_context` | Operator-only | Rule/fact readiness summary. |
| `code_defined` | Operator-only | Catalog authoring/readiness summary. |
| `observed_only` | Operator-only | Catalog authoring/readiness summary. |

`observed_mechanics.mechanics[]`:

| Field | Scope | Notes |
|---|---|---|
| `spell_id` | Public | Rendered/link target. |
| `spell_name` | Public | Rendered. |
| `boss_name` | Public | Rendered. |
| `observed` | Public | Combat-log aggregate signals; not raw events. |
| `catalog` | Operator-only | Code-defined raid catalog details and source notes. |
| `criteria` | Operator-only | Active criterion internals. |
| `facts` | Public | Aggregate failure count/damage/players. |
| `rule_status` | Operator-only | Rule pipeline status; public renderer should use product labels only. |
| `diagnostics` | Operator-only | Authoring/readiness messages. |

`mechanics[].observed`:

| Field | Scope | Notes |
|---|---|---|
| `spell_name` | Public | Source observed name fallback. |
| `damage_hits` | Public | Rendered through event count. |
| `affected_players` | Public | Rendered through player count. |
| `damage_source_count` | Public | Available. |
| `total_damage` | Public | Rendered. |
| `max_hit` | Public | Available. |
| `debuff_applications` | Public | Rendered through event count/seen-as channel. |
| `debuffed_players` | Public | Rendered through player count. |
| `max_stack_count` | Public | Available. |
| `interrupt_opportunities` | Public | Rendered through event count/seen-as channel. |
| `successful_interrupts` | Public | Available. |
| `missed_interrupts` | Public | Available. |
| `interrupt_target_count` | Public | Rendered through player/target count. |
| `first_seen_ms` | Public | Available for ordering/context. |
| `last_seen_ms` | Public | Available for ordering/context. |

`mechanics[].catalog`:

| Field | Scope | Notes |
|---|---|---|
| `spell_id` | Operator-only | Duplicates public spell id; keep under operator object if retained. |
| `spell_name` | Operator-only | Duplicates public spell name; keep under operator object if retained. |
| `mechanic_type` | Operator-only | Public can render derived category without source catalog object. |
| `event` | Operator-only | Authoring detail. |
| `boss_encounter_id` | Operator-only | Authoring/catalog detail. |
| `boss_name` | Operator-only | Duplicates public boss name. |
| `raid_name` | Operator-only | Catalog detail. |
| `raid_slug` | Operator-only | Catalog detail. |
| `track` | Operator-only | Rule readiness. |
| `rule` | Operator-only | Rule threshold/source mechanics. |
| `sources` | Operator-only | Authoring provenance. |
| `notes` | Operator-only | Authoring note; may contain local context. |

`mechanics[].criteria[]`:

| Field | Scope | Notes |
|---|---|---|
| `criterion_dim_id` | Operator-only | Internal fact key. |
| `spell_id` | Operator-only | Duplicates public spell id. |
| `spell_name` | Operator-only | Duplicates public spell name. |
| `mechanic_type` | Operator-only | Rule internals. |
| `boss_encounter_id` | Operator-only | Rule internals. |
| `boss_name` | Operator-only | Rule internals. |
| `difficulty_id` | Operator-only | Rule internals. |
| `threshold` | Operator-only | Rule internals. |
| `ruleset_id` | Operator-only | Rule internals. |
| `ruleset_version` | Operator-only | Rule internals. |

`mechanics[].facts`:

| Field | Scope | Notes |
|---|---|---|
| `failure_count` | Public | Rendered in Mechanics tab. |
| `total_damage` | Public | Available/rendered indirectly. |
| `failed_player_count` | Public | Available summary. |

## Rendered Encounter Detail Sections

Current local frontend sections and their backing fields:

| Section | Backing fields | Scope |
|---|---|---|
| Header | `encounter.name`, `encounter.id`, `encounter.start_time` | Public except local `id` operator-only. |
| Stat strip | `counts.deaths`, `failure_preview.counts.failures`, `interrupt_coverage`, `pull_review.damage_done`, `pull_review.low_dps` | Public. |
| Tabs | `observed_mechanics.counts.observed_spells`, `pull_review.low_dps`, `failure_preview.counts.failures`, `counts.deaths`, `counts.interrupt_opportunities` | Public. |
| Overview metadata | `difficulty_name`, `success`, `fight_time_ms`, `group_size`, `wow_encounter_id`, `instance_id`, `start_time`, `id` | Public except local `id` operator-only. |
| Overview pull signals | Death/failure/interrupt/damage/debuff/roster counts and top damage taken | Public. |
| Overview roster | `roster[]` | Public. |
| Mechanics summary | observed mechanic counts and failure counts | Mixed: public counts plus operator-only rule-readiness counts. |
| Mechanics damage taken | `pull_review.damage_taken_spells[]`, matched to `observed_mechanics.mechanics[]` for category labels | Public labels; rule internals hidden. |
| Mechanics debuffs | `pull_review.debuffs` plus player-debuff toggle | Public. |
| Mechanics encounter spells | `observed_mechanics.mechanics[]` | Public observation/fact values; operator-only catalog/criteria/status/diagnostics hidden. |
| Damage summary | `pull_review.damage_done`, `pull_review.low_dps` | Public. |
| Failures summary | `failure_preview.counts`, `failure_preview.mechanics[]` | Public except criterion/player dim ids. |
| Failure diagnostics | `failure_preview.diagnostics[]` | Operator-only. |
| Targeted cone events | `failure_preview.mechanics[].targeted_cone_events[]` | Public except criterion id. |
| Death Recap | `deaths[]` | Public except local row id. |
| Interrupt Coverage | `interrupt_coverage.spell_coverage[]`, `player_contributions[]` | Public except criterion dim ids. |
| Personal Pull Summary selector | `personal_pull_summary.players[]`, `selected_player_guid` | Players public; selected guid is UI/account state. |
| Personal metrics | personal totals per player | Public. |
| Defensive Coverage | `personal_pull_summary.players[].defensive_analysis` | Public. |
| Encounter Performance | `personal_pull_summary.players[].performance` | Public except local encounter ids. |
| Raw Pull Totals | personal damage done/taken totals | Public. |

## Contract Follow-Ups

- Replace local ids in document-rendered history rows with `source_encounter_key`
  before those rows become linkable.
- Decide whether operator-only objects are nested under an explicit
  `operator` key per section or marked through a parallel field-scope schema.
  Do not make public rendering depend on remembering ad hoc hidden fields.
- Keep raw source identity out of the document even in parser mode; the stable
  key is enough for renderer identity.
- Size risk is real but currently modest for the chosen factful fixture
  (`126.7 KiB` uncompressed). Re-measure once field-scope wrappers or affected
  player expansions are added.
