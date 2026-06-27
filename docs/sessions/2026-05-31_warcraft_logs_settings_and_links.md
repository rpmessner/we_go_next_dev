# 2026-05-31 Warcraft Logs Settings and Log Links

## Summary

Added the first web UI surfaces for Warcraft Logs integration:

- Settings page fields for Warcraft Logs client name and API key.
- Encrypted local storage for the API key on the default user settings row.
- Imported log row form for linking a Warcraft Logs report URL to a local combat log.
- URL parsing for report code and optional fight id.

## Storage

The WCL API key is encrypted before being stored in Postgres and is not rendered back to the browser. Clearing credentials removes the client name, encrypted key, and key timestamp.

Imported combat-log rows can now store:

- `warcraft_logs_report_url`
- `warcraft_logs_report_code`
- `warcraft_logs_fight_id`
- `warcraft_logs_linked_at`

This supports starting future fetch/compare workflows from an imported local log instead of retyping report metadata.

## Verification

```bash
mix compile --warnings-as-errors
mix test test/we_go_next/accounts_test.exs test/we_go_next_web/live/settings_live_test.exs test/we_go_next_web/live/encounter_live_index_test.exs
```
