# 2026-05-19: Reference Metadata Ingestion

## Context

Worked task `#37 Ingest Spell and Encounter Reference Metadata`.

The existing source-data layer already had `spell_reference` and `encounter_reference` tables from task `#49`, but it did not yet have an operator-facing import path for metadata exports or a queryable encounter-to-spell relationship table.

## Changes

Added:

- `source_data.encounter_spell_reference`
- `difficulty_id` scope on `source_data.encounter_reference`
- `WeGoNext.SourceData.EncounterSpellReference`
- `WeGoNext.SourceData.ReferenceImporter`
- `mix wgn.import_reference_metadata`

The importer accepts:

- spell-id/name JSON maps such as `tools/spell_names.json`,
- reference bundles with `spells`, `encounters`, and optional `encounter_spells` arrays.

Rows are build-scoped by product, channel, build key/version, locale, source system, and source priority. Imported rows stay in source-data as evidence; they do not activate rules or write gold facts.

## Tests

Added coverage for:

- source-data schema placement and associations,
- spell-name JSON imports,
- bundled spell/encounter/link imports,
- idempotent refresh counts,
- required build-key scope,
- Mix task output and argument validation.

Focused verification:

```bash
MIX_ENV=test mix ecto.migrate
mix test test/we_go_next/source_data_test.exs test/mix/tasks/wgn_import_reference_metadata_test.exs
```

Result:

```text
12 tests, 0 failures
```
