# 2026-05-18 Legacy Model Layer Pruning

Task #31 removed the remaining active legacy model-layer paths that kept the old analyzer-backed UI model alive.

## Removed

- `WeGoNext.Criteria` and `WeGoNext.Criteria.MechanicCriteria`
- `WeGoNext.Preferences` and spell preference schema
- legacy JSON analysis cache modules and deserializer/serializer
- `Mix.Tasks.WeGoNext.BackfillAnalysis`
- analyzer-backed `FailureAnalyzer` and `PullSummary`
- importer `compute_legacy_analysis` option and background analysis broadcasts
- tests that inserted `public.mechanic_criteria` rows

## Database

Added `20260518010000_drop_legacy_model_layer_artifacts.exs`.

The migration removes:

- `public.mechanic_criteria`
- `public.spell_preferences`
- `public.encounters.analysis`
- `public.encounters.storage_tier`

`public.encounters` remains in place as transitional import bookkeeping until a replacement import-domain record exists.

## Verification

- `mix compile`
- `mix test`
- Applied `mix ecto.migrate` to the local dev database
- Verified via `information_schema` that the legacy public tables and encounter cache columns are gone
