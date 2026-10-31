# Encounter list, Logs and Settings state

`we-g18.8` uses small pure `WeGoNext.StateTable` tables, not new long-lived processes or a TLA+ model.

| Table (`WeGoNextWeb.*`) | Modes | Adapter |
|---|---|---|
| `ImportState` | idle, importing, failed, timed_out | `ImportStatus`: durable `FileIngest.Operation` receipt, import notifications, importing-only 1-second reconciliation |
| `LogSelectionState` | all, available, imported | Encounter list selection and import/reimport affordances |
| `SortState` | asc, desc | Encounter list session preference |
| `DocumentIndexState` | ready, empty, unavailable | Encounter document index reads |
| `LoadState` | idle, loading, failed | Logs async display selection (not ingest) |
| `PathState` | empty, valid, invalid | Settings filesystem validation |

`WatchControl` shares the control and command adapter across all three pages. The existing `FileWatcher` machine remains the watch owner. Checkboxes use its current watched file, not persisted flags alone. Open pages subscribe to start/change, stop/expiry and rotation notifications. Settings keeps its existing Clear button.

Import progress is data within the importing mode. Late progress cannot revive a terminal import; a new receipt token clears old progress/error. Mount and lifecycle notifications read the durable receipt. Reconciliation covers missed completions and expired deadlines, refreshing page read models when ingest terminates. It does not re-read receipts on every progress update.

`page_state_test.exs` exercises the LiveViews. `page_state_tables_test.exs` checks random import/load sequences, totality, reachability and these generated matrices/diagrams.

Regenerate artifacts from `we_go_next/` without starting the app:

```bash
MIX_ENV=test MIX_TEST_PARTITION=_pages mix run --no-start -e '
root = "../docs/state-machines/page-state"
for module <- [WeGoNextWeb.DocumentIndexState, WeGoNextWeb.ImportState,
  WeGoNextWeb.LoadState, WeGoNextWeb.LogSelectionState,
  WeGoNextWeb.PathState, WeGoNextWeb.SortState] do
  name = module |> Module.split() |> List.last() |> Macro.underscore()
  File.write!(Path.join(root, name <> ".md"), module.matrix())
  File.write!(Path.join(root, name <> ".mmd"), module.diagram())
end'
```
