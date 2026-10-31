# Encounter detail state

`WeGoNextWeb.EncounterLive.DetailState` owns the detail page's transitions.
`EncounterLive.Show` loads documents, projects the returned data into assigns,
and runs the `patch_tab` effect with `push_patch`.

Document states are `missing`, `stale`, `empty`, and `fresh`, in that precedence.
The shared `WeGoNext.Freshness.classify/1` must classify every stamp as current
before a document can be empty or fresh. Missing, partial, and outdated stamps
all retain the existing stale banner.

Tab, filter flags, expanded death-heal keys, and personal player selection are
orthogonal data. Controls do not change document freshness. URL params select
a tab without emitting a patch; tab clicks select a tab and emit a patch.
Unknown or absent tabs retain the existing Overview fallback. Other controls
remain session-local and survive tab patches, not reloads.

No TLA+ model or TLC run: we-g18.9 explicitly calls for a small table only.
The compile-time validator checks table coverage. Tests check the generated
matrix and diagram, randomized control sequences, toggle inversion, and the
LiveView adapter's document states, controls, reload, and history behavior.

Regenerate the checked artifacts from `we_go_next/`:

```sh
MIX_ENV=test mix run --no-start -e '
  root = "../docs/state-machines/encounter-detail"
  machine = WeGoNextWeb.EncounterLive.DetailState
  File.write!(Path.join(root, "implementation-matrix.md"), machine.matrix())
  File.write!(Path.join(root, "implementation.mmd"), machine.diagram())
'
```
