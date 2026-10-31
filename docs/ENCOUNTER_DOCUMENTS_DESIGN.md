# Encounter documents

The medallion build emits versioned per-encounter JSON documents. The local
frontend reads them from disk rather than querying warehouse tables at mount.

## Build and read path

```text
silver projections + gold facts/read models
  -> Gold.RebuildEncounter
  -> Documents.generate_for_encounter
  -> Documents.Store.FileSystem
  -> local encounter list and detail LiveViews
```

`Documents.EncounterDocument` serializes the encounter summary, roster, deaths,
damage review, debuffs, mechanic observations, failure preview, interrupt
coverage, personal summary, and survival usage. The document carries schema and
derivation versions so stale or unsupported files can be explained in the UI.

Files under `documents_root` (override with `DOCUMENTS_ROOT`):

- `encounters/<source_encounter_key>.json`: one pull's analysis.
- `index.json`: generated encounter list with headline counts and raid-night metadata.

Identity comes from `WeGoNext.Mirror.Keys.source_encounter_key/1`, backed by the
unique key on `gold.dim_encounter`. The historical module namespace remains for
compatibility. Missing identity inputs prevent document generation. Local detail
URLs use `/encounters/:source_encounter_key`.

`WeGoNext.Documents.Store` defines the storage seam; its production adapter is
`Store.FileSystem`. Generation and reads remain independently testable against
temporary directories. Raid-night renames regenerate affected local documents.

## Operations and verification

```bash
mix wgn.rebuild_documents --encounter-id <encounter_dim_id>
```

Tests cover document content, versioning, index updates, local storage, and
LiveView rendering, including missing, empty, and stale documents. See
[`OPERATIONS.md`](OPERATIONS.md) for rebuild policy.

## Retired publishing path

The hosted public mirror was shut down because of cost. we-g18.2 removes its
outbox, upload worker, publishing flags, remote store and credentials, report
slugs, public viewer, run-mode split, and deployment configuration. Gold identity
keys and local document generation remain. Publishing may return as a static
HTML/JS artifact on a free or cheap host; there is no current publishing backend.

Historical plans are retained as retired reference material, not implementation
instructions.
