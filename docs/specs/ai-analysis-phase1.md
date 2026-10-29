# AI analysis phase 1: Tools over MCP

Status: draft for approval (2026-10-29), with the builder check folded in. Board draft `draft:ai-analysis-phase1` (project we_go_next_dev). Decisions come from the wayfinder map **AI analysis layer** (beads `we-c5q`); each closed ticket there holds its detail. Vocabulary: `GLOSSARY.md`.

## Goal

Let the operator run real Analysis sessions from Claude Code over the logs on file. Claude Code calls our starter Tools through a dev-only MCP endpoint, and every Tool call and verdict is recorded so retros can find promotions.

## Why

The operator wants analysis to grow through use: an expensive model explores early in a raid tier, operations it repeats get promoted into Tools and Playbooks, and later sessions get cheaper and more automated. Phase 1 is the cheapest way to start collecting that usage. Claude Code is the chat, so no session UI or API client is needed before real sessions exist. Success for the operator is asking the 12 corpus questions (`docs/ai-analysis/question-corpus.md`) about the Sept 6 raid between or after pulls and getting cited answers, with a record good enough to review afterwards.

## Non-goals

- The in-app agent loop, Anthropic API client, LiveView session screen, and spend-cap enforcement (phase 2; decisions locked on the map).
- Composite Tools (pull comparison, unruled-spell ranking, coaching notes). They must emerge through Promotion. Shipping them now defeats the point.
- Auto-runs, in-app retro, DB-backed Playbooks, model routing (Jev), name aliasing.
- Any exposure beyond the operator's machine: no public mirror, no raider access.
- Initiative 7's defensive/consumable silver grain. `log_events` stands in for it.
- Anti-goal: Tools that write anything, or that turn silver into a generic raw-event warehouse.

## Decisions

1. **Analysis context** (user, we-c5q.7). A new `WeGoNext.Analysis` context, separate from the medallion. Each Tool is one module implementing a Tool behaviour: name, model-facing description, JSON input schema, and a run function taking args and session context. A registry lists enabled Tools as data. Tools call existing silver, gold, encounter-document and bronze read functions and own no tables.
2. **Starter Tools** (user, we-c5q.6). Primitives only:
   - `list_pulls(boss | night)`: pulls with outcome, duration and ids.
   - `pull_summary(pull)`: encounter-document overview, roster and pull signals.
   - `deaths(pulls)`: deaths with killing blow and recap.
   - `failures(pulls, player?, mechanic?)`: `gold.fact_failure` across pulls.
   - `damage_taken(pulls, spell?, player?)`: silver player × spell hits and amounts.
   - `interrupts(pulls)`: kickable casts, kicks and misses. It reads today's interrupt silver, which overcounts opportunities and misses (we-23), so its description and every result carry a caveat telling the agent to verify with `log_events` (user, builder check).
   - `log_events(pull, filters, time window)`: filtered raw events from a bronze re-parse of one pull.

   Session-support Tools: `session_context`, `list_playbooks`, `get_playbook`, `record_verdict`.
3. **Result envelope** (user, we-c5q.7). JSON `{data, evidence, truncated, next_cursor}`. Evidence names each row's source: pull id, timestamps, and byte offset for `log_events`. Cap about 8 KB; over the cap, truncate and return a cursor.
4. **Guarantees** (user, we-c5q.7). Read-only database transaction and no file writes. Deterministic for the same inputs and data. 5 s limit per call. Errors and timeouts go back to the model as tool errors with a short reason and never crash the endpoint.
5. **Real names** (user, we-c5q.7). Character names and GUIDs go to the model unaliased.
6. **Read paths** (agent call, from we-c5q.3 measurements):
   - Pull summaries come from encounter documents.
   - Failures come from `gold.fact_failure`.
   - Deaths, hits, debuffs, damage done and interrupts come from silver.
   - Everything else goes through `log_events`. Never cache parsed pulls (about 200 MB each), and never recompute silver at Tool time.
7. **Filtered bronze parse** (user, we-c5q.6; agent call on shape). A new filtered parse entry point in the Zig NIF. Filters: event types, source/target GUIDs, spell ids, time window. It drops non-matching lines before building terms. The existing `parse_events/4` used by import stays unchanged. It ships together with we-p7i (ReleaseSafe build on a dirty CPU scheduler). The byte range comes from `gold.dim_encounter` start/end bytes.
8. **MCP endpoint** (user, we-c5q.4 and builder check). Dev-only. Dev keeps listening on 0.0.0.0, and a plug on the analysis MCP route rejects every caller that isn't loopback. Tidewave's own remote access is unchanged. It exposes the registry's Tools, the analyst instructions as an MCP prompt that starts a session (e.g. `analysis-session`), and the active-log snapshot through `session_context`.
9. **Session context** (user, we-c5q.8). Analyst instructions (role, Tool use, citation rules, glossary) live as files under the app's analysis priv directory, the same files phase 2 uses as its system prompt. The session's log is an argument to the `analysis-session` prompt, defaulting to the most recently imported log (user, builder check). The snapshot and every Tool are scoped to that log for the session, and `list_pulls(night)` stays within it. Cross-log questions wait for a later Tool. The snapshot is about 2-3 KB: the session's log, its pulls (boss, number, outcome, duration, ids), the roster with class/spec/role, and medallion freshness (stale derivation stamps, unimported pulls). Everything else comes through Tools.
10. **Citations** (user, we-c5q.10). The instructions require every factual claim to cite Tool evidence, e.g. `[Sszorak pull 4, 2:31, deaths]`. A claim without evidence is marked as inference. Phase 1 citations are plain text.
11. **Playbooks** (user, we-c5q.9):
    - Markdown files with front matter in the analysis priv directory, versioned and reviewed through git.
    - Front matter fields: title, scope (`global` | `boss`), encounter_ids, question_families (wipes, deaths, mechanics, coaching, own-play), status (`active` | `retired`).
    - The global Playbook and the target boss's Playbooks load automatically. `list_playbooks` filters by question family.
    - Phase 1 ships only the global Playbook (agent call). Boss Playbooks come from retros.
12. **Recording** (user, we-c5q.11). A new `analysis` Postgres schema. Phase 1 tables:
    - sessions: MCP session, start time, active log, Playbooks loaded with their git commit.
    - Tool calls: session, Tool, args, full result (bounded by the cap), result size, duration, truncated, error.
    - verdicts: session, the answer or question it judges, verdict correct/partly/wrong, correction text.

    Rows are kept indefinitely. The messages table belongs to phase 2.
13. **Verdicts** (user, we-c5q.10). The `record_verdict` Tool stores a structured verdict when the operator judges an answer in chat. The instructions tell the agent to call it whenever the operator says an answer is right, partly right or wrong.
14. **Export** (user, we-c5q.11). A mix task exports a session, or a night's sessions, as JSONL in the shape phase 2 will also produce. Phase 1 joins the Claude Code transcript with the server-side Tool-call log. How the join matches calls is an agent call: by Tool name, args and order within the session.
15. **Reference set** (user, we-c5q.10). Import the Sept 6 log. Write one reference answer per corpus question, drafted from deterministic silver/gold/bronze queries and verified once by the operator. Q5 and Q6 reference answers use bronze cast and aura events, since Initiative 7 is not built. The Q8 reference answer uses bronze `SPELL_CAST_SUCCESS` and `SPELL_INTERRUPT` events, not interrupt silver. A documented procedure reruns the 12 questions and grades answers against the references.
16. **Model** (user, we-c5q.5). Phase 1 sessions use Opus 5.5 in Claude Code. Spend is governed by Claude Code's own billing. The $5/session and $50/night caps belong to phase 2.
17. **Session boundary** (agent call, builder check). An Analysis session starts each time the `analysis-session` prompt is invoked, not per MCP connection. The prompt mints an analysis session id and returns it in the instructions, and every Tool takes that id as an argument. That way verdicts and Tool calls stay attached across `/clear`, reconnects and dev recompiles, and the export joins on it. The prompt's arguments also name the target boss (optional), which drives Playbook auto-loading in decision 11.
18. **NIF bundle** (agent call, builder check). we-p7i's build-mode and scheduler change to `parse_events/4` is in scope here, provided its results are identical (existing import and silver tests pass, and before/after timings are recorded). The filtered entry point may share line-parsing code with `parse_events/4` only under that same condition. Any change to what `parse_events/4` returns stays ask-first.

## Acceptance checks

1. **End to end, outside the code.** In Claude Code, the operator connects to the MCP endpoint, starts the `analysis-session` prompt and asks corpus Q1 about a Sszorak pull from Sept 6. The answer cites Tool evidence for every factual claim, and each Tool call it made appears as a row in the `analysis` Tool-call table.
2. **All 11 Tools listed over MCP** (7 starter plus 4 session-support), each with passing tests per the verification plan.
3. **Size cap holds.** On the largest real pull (Twin Fangs, about 107 MB, 368k events), every starter Tool's result stays at or under the cap, or truncates with a usable cursor.
4. **`log_events` speed.** A filtered `log_events` call on that pull returns in at most 0.5 s on the ReleaseSafe build, from local disk. Baseline: 1.04–1.34 s unfiltered ReleaseSafe and 2.2–3.9 s Debug (we-c5q.3).
5. **Read-only and loopback-only are enforced.** A test shows a Tool attempting a write fails inside its read-only transaction, and an MCP request from a non-loopback address is rejected.
6. **Verdicts land.** Saying "that's wrong, it was X" in a session produces a structured verdict row linked to the session.
7. **Export works.** Exporting a real session yields JSONL in which each Tool call from the transcript is matched to its server-side row.
8. **Reference set.** All 12 reference answers are checked in and operator-verified. One graded run of the 12 questions is recorded as the baseline score; phase 1 sets no pass threshold.
9. **Medallion untouched.** No silver, gold or rules schema changes. Import behaviour of `parse_events/4` is unchanged: existing import and silver tests pass.
10. **Gates.** `mix test` (feature tests need a working chromedriver), `mix credo`, `mix format`, zero compile warnings.

## Verification plan

- **Tool seam:** each Tool module's run function, tested with `DataCase` over real-log fixture slices (the pattern of `pet_attribution_real_log_test`). Assert the envelope, the evidence and the cap. A schema test validates the args the agent will send.
- **NIF seam:** the filtered parse entry point tested against the real fixtures, plus a timing check on the Twin Fangs pull. Before/after numbers for we-p7i are recorded.
- **MCP seam:** a protocol-level test through the endpoint covering tool listing, a call, an error-as-tool-result, and the prompt.
- **E2E seam:** an operator-run Claude Code session over the imported Sept 6 log for acceptance checks 1, 6 and 7. Evidence: the session transcript, the Tool-call rows, and the export file.
- **Evidence for the handoff:** test output, the `log_events` timing table, the row counts from the E2E session, and the baseline grading results.

## Ask-first boundaries

- Adding any dependency other than a single MCP server library, or upgrading Req.
- Any change to silver, gold or rules schemas or projections, or to `parse_events/4` behaviour.
- Any write path from a Tool, or binding the endpoint beyond localhost or outside dev.
- Adding a Tool beyond the starter and session-support set, or any composite Tool.
- Calling the Anthropic API from the app.
- Writing boss Playbooks before a retro proposes them.

## Left to the builder

- Use a maintained Elixir MCP server library, or a thin hand-rolled endpoint. Pick after checking maturity; this is the one allowed new dependency.
- Exact JSON input schemas, cursor encoding, module names inside the Analysis context, and table and column names in the `analysis` schema.
- The global Playbook and analyst instructions wording. The operator reviews them in the diff.
- The transcript-to-log join details, within decision 14.
- How the reference answers are graded: by the operator, or by a judge model against the references with the operator spot-checking.
