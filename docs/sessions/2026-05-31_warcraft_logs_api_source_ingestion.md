# 2026-05-31 Warcraft Logs API Source Ingestion

## Summary

Added a file-backed bronze/source-data ingestion path for Warcraft Logs API report/fight response payloads.

New pieces:

- `source_data.warcraft_logs_api_fetch`
- `WeGoNext.SourceData.WarcraftLogsApiFetch`
- `WeGoNext.SourceData.import_warcraft_logs_api_response/1`
- `WeGoNext.SourceData.import_warcraft_logs_api_response_file/2`
- `WeGoNext.SourceData.list_warcraft_logs_api_fetches/1`
- `WeGoNext.SourceData.compare_warcraft_logs_damage_done/3`
- `mix wgn.import_warcraft_logs`

## Boundary

Warcraft Logs API rows are external parser evidence only. They are separate from `combat_log_files`, do not become local combat-log parser input, and do not create active rules, promoted criteria, or gold facts.

Each import writes a flat JSON bronze artifact under `var/bronze/warcraft_logs` by default. The artifact contains query/request provenance and the raw WCL response payload. The source-data row stores report code, fight id, source URL, API/query metadata, request parameters, fetch timestamp, request hash, response hash, artifact path/hash/size, raw response payload, build scope, and provenance metadata. Rows are versioned through `source_data.source_import` by response hash.

The first validation read model compares local `silver.damage_done` player totals against WCL damage-done table entries. This supports debugging DPS math drift without letting WCL data replace local medallion facts.

## Verification

```bash
mix compile
MIX_ENV=test mix ecto.migrate
mix test test/we_go_next/source_data_test.exs test/mix/tasks/wgn_import_warcraft_logs_test.exs
```
