# WCL Bronze Evidence and Local Validation

Status: proposed implementation plan, grounded in read-only discovery on 2026-09-06.
Scope clarified with the operator: close data and correctness gaps using repeatable
comparisons; track findings in beads and documentation, without a new discrepancy UI.
Existing beads must be reconciled before execution; the configured city Dolt
endpoint was unavailable during planning. The work packages below are not new
issue IDs and have not been filed or marked complete.

## Goal

Import the September 6 local raid log, capture matching Warcraft Logs API
evidence in bronze, and run repeatable per-encounter comparisons using developer tooling.
Trace discrepancies back to their source, fix confirmed local bugs, and replay
the same evidence to prove the corrections across the raid night.

Done means every in-scope comparison is exact or has a specific, evidenced
explanation; unavailable evidence must be recorded as incomplete in the run report. WCL is an
independent implementation to compare against, not an authority that overrides
local observations or authored mechanics.

## Verified starting point

- Local filename: `WoWCombatLog-090626_103607.txt`, 1,168,915,469 bytes at inspection.
- Combat log header: version 22, advanced logging enabled, build `12.1.0`.
- Recorded interval: September 6, 2026, 10:36:07.630–14:06:27.829, UTC−04:00.
- 18 encounter starts and 18 ends, with three kills:

  | Encounter | Game encounter ID | Pulls | Kills |
  |---|---:|---:|---:|
  | Nymrissa Wavecaller | 3379 | 1 | 1 |
  | Sszorak | 3420 | 9 | 1 |
  | The Twin Fangs | 3421 | 8 | 1 |

- All start records have difficulty ID 15. Two Sszorak resets last approximately
  five seconds and twenty milliseconds; these are useful matching edge cases.
- Local input was still in the live Logs directory on the current E: install.
  Archon may move it to `warcraftlogsarchive/Archive-WoWCombatLog-090626_103607.txt`.
  Resolve both locations immediately before import; do not choose by file mtime.
- Read-only SQL found zero `combat_log_files` rows containing this filename stem,
  zero `source_data.warcraft_logs_api_fetch` rows, and zero evidence rows for the
  supplied report.
- Remote target supplied by the operator:
  [report aW7mTPNrXwLcM2DR](https://www.warcraftlogs.com/reports/aW7mTPNrXwLcM2DR).
  Its fights, visibility, roster, and correspondence to the local log are not yet
  verified. Do not invent remote fight IDs from local pull order.
- A client-credentials OAuth probe returned HTTP 401 using the supplied operator
  files as client ID and client secret. Confirm that the name file contains the
  OAuth client ID rather than the application display name. No token was obtained.
- Existing uncommitted changes affect the Zig parser and silver pet attribution.
  Preserve them and record their diff identity in the baseline; do not attribute
  their behavior to the committed revision alone.

## Reuse and gaps

Reuse these existing paths:

- [SourceData](../we_go_next/lib/we_go_next/source_data.ex): API response artifacts,
  query/response hashes, provenance catalog, and damage-done comparison.
- [Import task](../we_go_next/lib/mix/tasks/wgn.import_warcraft_logs.ex): saved JSON
  ingestion and the damage-done GraphQL preset; currently requires a bearer token.
- [WCL context](../we_go_next/lib/we_go_next/warcraft_logs.ex): log/report association.
- [Bronze reconciliation](../we_go_next/lib/we_go_next/bronze/combat_log_reconciler.ex):
  live-to-archive identity reconciliation.
- Existing Settings, imported-log linking UI, and encounter document generation.

The present comparison strips realm suffixes, matches by lowercased name, selects
the first recursively discovered entries list, and defaults to a 0.5% damage
tolerance. That is insufficient for trustworthy validation. The importer also
needs OAuth, GraphQL-error handling, report-level metadata, event pagination,
completion tracking, and a repeatable fetch/compare command. The current evidence schema requires a
positive fight ID; represent report-level captures explicitly instead of using a
fake fight ID or attaching report metadata to an arbitrary pull.

## Work packages and acceptance checks

### A. Establish the two inputs and API access

1. Read the actual OAuth client ID/secret from operator-owned credential files.
   Keep credentials and access tokens out of command arguments, logs, artifacts,
   fixtures, and repository files. Use a developer-side authentication probe;
   new credential-management UI is not part of this work.
2. Exchange credentials, fetch report metadata/fights/master actors, and record
   the API rate budget. Use the exact supplied report rather than guild discovery.
   A private report requires a user-authorized OAuth flow; do not change visibility
   to make a client-credentials request work.
3. Resolve the local live/archive source, verify that its bytes are stable, and
   record a full content hash plus the existing operational fingerprint. Import
   through the normal bronze → silver → gold → encounter-document workflow.
   Preserve source bytes; keep publishing disabled for this validation run.
4. Record a baseline manifest: local artifact identity, application revision and
   dirty-diff hash, parser/NIF build, projection/document/failure versions, rules
   identity, report identity, and fetched evidence hashes.

Acceptance: successful authenticated metadata response, one local import identity,
18 accounted-for encounter pairs, and a manifest linking both sources. Moving the
file to the archive and rescanning must not duplicate encounters. Explicitly
account for resets even if ordinary encounter lists hide them.

### B. Match fights and players before comparing numbers

Match local `gold.dim_encounter.id` to `(report_code, fight_id)` using game
encounter ID, difficulty, absolute start/end times, outcome, and roster evidence.
Convert WCL report-relative milliseconds to absolute time and normalize local
UTC offsets. Record boundary differences; never silently shift clocks per pull
to make totals fit. Record ambiguous or unmatched pulls in the comparison output.

Map report-local actor IDs to local player GUIDs using the identifiers actually
returned by WCL, realm-qualified names and corroborating roster metadata. Do not
treat an NPC game ID or an unqualified character name as a global player key.
Record pet/guardian owners separately and report unknown or conflicting owners.

Acceptance: all 18 local pulls and all relevant remote boss fights have an explicit
matched, local-only, remote-only, or ambiguous disposition. Only confirmed pairs
enter numeric comparison. Repeated bosses, same-name cross-realm actors, and short
resets cannot silently collapse into another fight/player.

### C. Capture replayable WCL bronze evidence

Extend the current importer rather than creating a second ingestion system.
Capture report metadata once, then fight-scoped tables and focused event families.
Persist raw response pages with query/variables, filters, fetch time, report/fight,
cursor, response hash, and API/schema provenance. Preserve historical artifacts
when refetching changed responses. Comparisons refer to exact capture versions.

Follow the API's returned pagination cursor until completion. Record page order,
request bounds and completion; guard against repeated cursors and partial failures.
Do not advance a timestamp manually or deduplicate identical-looking events in a
way that discards legitimate simultaneous hits. Handle HTTP failures, HTTP-200
GraphQL errors, missing reports, expired tokens, rate limits and malformed payloads
as unavailable/failed evidence, never as empty successful metrics. Bound retries
and allow a failed capture to resume safely.

Acceptance: a multipage capture replays offline to the same normalized rows;
interrupted/failed captures cannot produce a green comparison; retrying a completed
capture does not duplicate evidence. No credentials occur in retained artifacts.

### D. Compare the first pull and close confirmed gaps

Start with the Twin Fangs kill beginning at **13:55:51.477 UTC−04:00**. This is a
local anchor, not a claim about its remote fight ID. Compare damage done by player,
then spell and target to local silver, and verify the numbers shown by the encounter
document/UI. Include pet-heavy roster members actually observed in this pull.

Define and store the comparison policy: time window, enemy/friendly targets,
boss-only versus all targets, overkill, absorption, pet ownership/rollup, wipe
cutoff, and ability-ID mapping. Probe the actual WCL table/event response shape;
do not infer whether player totals already include pets. Compare integer totals
before DPS; when comparing rates, show both denominators and active-time policies.

Extend the existing Mix task or add a focused comparison command that emits a
machine-readable result and a concise Markdown report. Include local/WCL values,
absolute/relative deltas, spell/target breakdowns, policy, capture time, and evidence
references. Use saved bronze by default; refetch is explicit. Retain the inputs and
invocation needed to reproduce a result. This is developer tooling, not a new
application workflow or discrepancy database.

Run reports distinguish exact, unequal, unmatched, incomplete, and stale results;
document explanations and unresolved questions alongside the findings in docs or
beads. Report every nonzero delta. A documented rounding allowance
may apply to a derived display value, but the current blanket 0.5% tolerance must
not label unequal integer totals as exact. Invalid or missing WCL data is not zero.

Acceptance: one documented command compares the selected real pull from captured
evidence; every player is accounted for, deltas have spell/target evidence, and an
offline rerun reproduces the baseline. Confirmed defects are fixed with regressions
and before/after evidence. Verify affected values on the existing encounter page.

### E. Expand across this raid night and the supported measurements

After the first vertical works, run each supported comparison for all confirmed
fight pairs. Use the Nymrissa and Sszorak kills, a long Twin Fangs wipe, and the
short resets as additional regression cases.

| Measurement | Comparison grain and semantic checks |
|---|---|
| Roster/boundaries | Player identity, outcome, duration, missing actors/fights |
| Damage done | Player × spell × target; pets, targets, overkill and time windows |
| Damage taken | Player × spell; hit counts, absorbed/overkill fields, periodic hits |
| Deaths | Player × death occurrence; timestamp, killing event, resurrection/repeated deaths |
| Successful interrupts | Interrupter × interrupted actor/spell × occurrence |
| Debuffs | Target × spell × occurrence; application versus refresh and stack changes |
| Existing defensive/consumable views | Underlying casts/auras/heals for selected abilities; coverage explicitly reported |

Compare missed-interrupt judgments or mechanic failures only when both definitions
and supporting observations are defensible. WCL casts are not proof of interrupt
opportunities. WCL rankings, scores, and avoidable labels are not failure-fact
oracles. Mark unsupported measurements explicitly rather than expanding silver
into a generic event warehouse. For raw-event investigation, replay bounded local
bronze slices and WCL evidence artifacts.

Acceptance: a generated raid-night report records every fight/metric disposition;
no omitted player, unsupported metric or partial page is represented as a pass.

### F. Diagnose, fix, and replay confirmed defects

For each unexplained delta:

1. Reproduce it with the comparison command on frozen evidence. For a wrong value
   surfaced to users, also reproduce it on the existing encounter page.
2. Trace local bytes → parser fields → silver aggregation → document → displayed
   number, alongside the corresponding WCL table/events and filters.
3. Classify it as a local defect, matching defect, comparison-policy difference,
   missing evidence, or external behavior requiring investigation.
4. Extract the smallest faithful real-data regression fixture, keeping required
   summon/owner and boundary context. Demonstrate the failing assertion first.
5. Fix the responsible layer. Never copy WCL totals into local facts or add a
   report-specific adjustment. Reproject local bronze for parser/silver changes;
   a gold-only rebuild is insufficient. Bump applicable derivation/version stamps,
   including failure derivation when fact semantics change, then regenerate docs.
6. Replay the selected pull and the whole raid-night matrix against the same WCL
   capture. Record before/after values and verify neighboring metrics did not drift.

Acceptance: zero unexplained discrepancies in completed in-scope comparisons;
each explained difference cites concrete evidence and policy. Every discovered
defect has a regression and before/after proof. Any unresolved discrepancy or
unavailable comparison remains open in beads or the findings document, with its
evidence and next investigation step. Group findings by root cause rather than
creating an issue for every affected row. Filing a confirmed bug is not a substitute
for fixing it within this work's scope.

## Sequencing and verification

- A → B → C → D is the first deliverable; D includes fixing defects needed to
  make that pull trustworthy. E and F then extend the same loop across the night.
- Reconcile these packages with the existing WCL beads once the tracker is
  reachable. Do not duplicate the already-built importer/comparator tickets.
- Use mocked HTTP contract tests for auth, GraphQL errors, pagination, retries
  and rate limits; DB tests for source identity, artifact versions and matches;
  pure fixture tests for comparison semantics. Add LiveView coverage only when a
  confirmed fix changes existing rendered behavior.
- Run a real import → fetch → compare → fix → rebuild → compare loop and verify
  corrected values on the existing encounter page. Any Wallaby feature coverage
  must use the repository's page objects. Automated regression runs use stored
  evidence and do not depend on live API availability.
- Implementation gate: zero compile warnings, `mix test`, `mix credo`, and the
  repository `mix quality` gate as applicable; retain actual real-data evidence.
- A changed local derivation, match/policy, or WCL capture invalidates the old
  comparison. Record those identities in the run report; the comparison command
  must reject stale cached results or recompute them before asserting parity.

## Scope and checkpoints

This turn produces the plan and verifies prerequisites; it does not import the
raid, alter parser behavior, publish data, or claim WCL parity. Implementation can
reuse the existing local database and uploader-independent document workflow.
The Cloudflare/static-mirror migration is a separate workstream.

Deliverables are bronze evidence, repeatable comparison tooling, confirmed fixes,
regression tests, and a concise evidence report. Beads and documentation own the
investigation backlog. No discrepancy CRUD, comparison dashboard, matching-review
UI, or new product status workflow is required. Existing UI verification checks
that corrected medallion values reach users; it is not a prerequisite to build
another feature before diagnosing gaps.

No new WCL-derived local combat-log inputs, legacy CSV dependencies, authored
rule creation from API responses, public comparison publishing, or population
rankings. WCL source evidence remains separate from local combat-log provenance.
Review this plan before implementation under the repository's planning agreement;
changing report visibility or sharing, replacing unrelated local work, commits,
and deployment remain outside this plan's execution scope.

## API references

- [WCL authentication](https://www.warcraftlogs.com/api/docs): client credentials
  exchange and public versus user-authorized APIs.
- [Report schema](https://www.warcraftlogs.com/v2-api-docs/warcraft/report.doc.html):
  fight, table, event, filter, and actor metadata capabilities. Confirm actual
  response shapes through authenticated probes before implementing normalization.
- [Event pagination schema](https://www.warcraftlogs.com/v2-api-docs/warcraft/reporteventpaginator.doc.html).
- [Current operations](OPERATIONS.md#import-warcraft-logs-api-evidence).
