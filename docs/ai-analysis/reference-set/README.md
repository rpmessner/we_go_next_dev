# Rerun and grade the Sept 6 corpus

Use the [index](index.md) to review the twelve draft answers and their pull choices. The operator still needs to verify the references, run the live acceptance session, and record the baseline. None of those steps happened during this build.

Run commands from the repository root unless a command changes directory. Keep run artifacts under `/tmp` or another private directory outside git. They contain real player names, messages, usage, and session IDs.

## Recompute the evidence without an Analysis session

This step does not call Claude or the MCP endpoint. The SQL opens a read-only, repeatable-read transaction. The Python script reads its snapshot and the bronze file and writes only the specified new output directory. Do not use `mix run` with the dev application started: startup workers can write independently of a read-only query.

```sh
PGPASSWORD=postgres PGOPTIONS='-c default_transaction_read_only=on' \
  psql -XqAt -h localhost -U postgres -d we_go_next_dev \
  -v ON_ERROR_STOP=1 -f scripts/analysis-reference.sql \
  > /tmp/wgn-reference-snapshot.json

python3 scripts/analysis_reference.py \
  --snapshot /tmp/wgn-reference-snapshot.json \
  --catalog docs/ai-analysis/reference-set/survival-catalog.json \
  --log /tmp/wgn-nif-090626.txt \
  --output /tmp/wgn-reference-recomputed

diff -ru docs/ai-analysis/reference-set/evidence /tmp/wgn-reference-recomputed
```

Use a new output directory on each recomputation. A clean diff proves that the query and bronze extraction reproduce the checked-in numerical evidence. A changed database or ruleset can change the evidence. Review such a diff; do not replace the reference answers automatically.

The source log is `Archive-WoWCombatLog-090626_103607.txt`, imported as log `30`. The local copy used here has SHA-256 `f4c3032b6dab40bd5c443ea6ee3c42f05f6111d39a89966f316c3f86f51f5938`. Its mounted source is `/mnt/e/World of Warcraft/_retail_/Logs/warcraftlogsarchive/Archive-WoWCombatLog-090626_103607.txt`. Either copy must retain exactly the same bytes because evidence offsets are absolute. Gold pull IDs are analytics IDs, not public encounter IDs.

To check the frozen survival catalog against its source without starting the app:

```sh
(cd we_go_next && mix run --no-start -e \
  'IO.puts(Jason.encode!(WeGoNext.GameData.SurvivalActions.all()))') \
  > /tmp/wgn-survival-catalog-output.txt
```

Compare the JSON line from that output with `survival-catalog.json`. The catalog comes from existing code at base `f3b06f29ce314dfa34b372343c6069d4ecb76383`. It distinguishes button IDs from aura IDs, but is not an exhaustive defensive or potion list. It does not prove a player had a talent, an item, a ready charge, or an unchanged base cooldown.

## Verify the reference answers

1. Read each `qNN.md` beside its `evidence/qNN.json` and the recomputation diff.
2. Confirm the selected pulls in `index.md`. Change `questions.json` and the answer together if you choose a different pull.
3. Check causal and coaching statements as inference. No failure facts exist for this night in this snapshot. No active-ruleset criterion applies to these bosses. Archived seed criteria do not establish active coverage.
4. Check Q5, Q6, and Q8 against the original bronze offsets. Q5 lists observed uses, not invented ready or unused cooldowns. Q6 distinguishes an open aura at the damage timestamp from a recent cast. Q8 does not turn every completed boss ability into a missed kick.
5. Q12 targets the operator's character, set by `OWN_CHARACTER` in `analysis_reference.py` (Wispless for Sept 6). Change it only on the operator's word; never infer the character from class or the project character list.
6. Record reviewer, date, corrections, and approved scope in `index.md`. Retain the reviewed reference revision with the baseline artifacts.

The Python extractor is a focused reference query, not a replacement combat-log parser. It reads the common CSV event prefix, spell IDs, interrupt extra-spell IDs, and the existing advanced damage block's unit HP fields. Spell names come from the log. Milliseconds use the original wall-clock origin at each gold start byte; timezone offsets are not applied a second time. Boss HP is the minimum observed valid boss-named sample, not necessarily the exact final percentage. An absent sample stays unknown.

All counts are scoped to the eighteen encounter ranges, not trash or the entire wall-clock night. Death counts are silver death events, including repeated deaths after resurrection. Raw hit counts include periodic ticks and differ with exposure. Rules must be in an active ruleset and match boss and difficulty before the extractor calls them applicable.

## Run the questions headlessly

This step spends the operator's Claude usage and writes Analysis sessions and Tool-call audit rows to dev. Run it only after reference review. The dev server must already be running on port 4000 with the imported file accessible. Do not restart or migrate dev for this procedure.

From a terminal outside another Claude Code session, with an authenticated `claude` command:

```sh
python3 scripts/analysis_benchmark.py run \
  --model claude-opus-5-5 \
  --output /tmp/wgn-analysis-baseline-opus55
```

The script invokes each question through `claude -p --mcp-config <generated-file> --strict-mcp-config`. It uses twelve fresh Claude Code conversations. Each asks `start_session` to select log `30`, then follows the returned instructions and Playbooks. It fixes the corpus pull choices and requires factual citations and an Analysis session UUID in each final answer. The script does not supply reference answers to the answering model.

Built-in Tools and filesystem access are disabled. Only the loopback Analysis MCP server is configured. The working directory is an empty artifact subdirectory, and `--setting-sources ''` excludes inherited Claude settings. No question resumes a previous conversation. The default model is `claude-opus-5-5`; `--model` chooses a later comparison model. `--timeout` defaults to 1200 seconds per invocation. The script neither retries a failed call nor overwrites an existing run directory.

Keep the following artifacts:

- `manifest.json` records the model, question selections, reference hashes, and runner hash.
- `qNN.prompt.txt`, `qNN.call.json`, `qNN.stdout.json`, and `qNN.stderr.txt` preserve the prompt, arguments, raw Claude response, usage when supplied, and diagnostics.
- `qNN.answer.md` contains the final answer. `qNN.status.json` records success or failure.
- `mcp.json` contains only the endpoint configuration. `workspace/` is the isolated working directory.

A failure stops the batch. Preserve the partial directory, fix the environment, and use a new directory for a complete run. Do not grade a partial batch as a baseline. The prompt requires the model to start a session; the operator must verify its returned UUID and audit rows. A successful process exit alone does not prove that the model obeyed.

## Grade the completed run

This step also spends Claude usage. The judge has no MCP servers or built-in Tools and cannot record database verdicts.

```sh
python3 scripts/analysis_benchmark.py grade \
  --model claude-opus-5-5 \
  --run /tmp/wgn-analysis-baseline-opus55 \
  --output /tmp/wgn-analysis-baseline-opus55-grade
```

The judge receives each answer and its reference Markdown, including the per-death and per-player tables. The full linked JSON is for human spot-checks, not a hidden source of judge Tool calls. Each verdict is `correct`, `partly`, or `wrong`, with a one-line reason. `results.md` contains the table, category counts, and an advisory score with correct worth 1 and partly worth 0.5. Phase 1 has no pass threshold. Raw judge output and prompts remain beside the results.

Grading refuses a run if its answer Markdown, question manifest, catalog, or numerical JSON evidence changed. Updates to the verification record in `index.md` or this procedure do not change the answer key. Retain the original references to regrade an old run; do not compare answers against a silently changed answer key. Invalid or empty judge output fails the batch rather than becoming a score. A judge can still be factually wrong. Spot-check every wrong/partly judgment and any confident causal claim, then record human overrides separately without editing the raw judge response.

For later comparisons, keep the reference revision, pull selections, judge model, and scoring rubric unchanged. Vary one Tool, Playbook, instruction change, or answering model at a time. Record code revisions and compare question-level results, not only the total score.

## Exercise Q1, verdict recording, and export in Claude Code

The headless batch is not a replacement for spec acceptance checks 1, 6, and 7.

1. Connect Claude Code to `http://127.0.0.1:4000/analysis/mcp` as the `analysis` HTTP MCP server. Start `analysis-session` with log `30` and boss `Sszorak`, or call `start_session` with those values.
2. Ask Q1 for Sszorak pull 5, gold pull `440`. Inspect citations and compare with `q01.md`.
3. Give an explicit judgment in the conversation, including the correction if partly or wrong. Confirm that Claude calls `record_verdict` for that Analysis session UUID. Do not accept its prose claim as proof of insertion.
4. Locate the Claude Code JSONL transcript for the conversation. The headless calls use explicit `--session-id` values in `qNN.call.json`; these are Claude conversation UUIDs, not Analysis session UUIDs.
5. Export from `we_go_next/` with the Analysis session UUID and actual transcript path:

```sh
cd we_go_next
mix wgn.export_analysis --session ANALYSIS_UUID \
  --transcript /path/to/claude-session.jsonl \
  --output /tmp/wgn-analysis-q1-export.jsonl
```

Inspect the exported `session`, `tool_calls`, `verdicts`, and unmatched records. Require the expected verdict row and matching transcript/server pairs for all Analysis evidence calls. `start_session` is called without a prior Analysis UUID and can appear as an unscoped transcript call; inspect it rather than inventing ownership. Other unrelated Claude Tools can also be unscoped. Follow [session-export.md](../session-export.md) for reconnects and transcript-wide messages. Do not use `--night 2026-09-06` to select today's Analysis sessions: that selector uses session-start UTC dates, not raid dates.

Record the transcript, export, baseline result paths, and human-reviewed score in `index.md` after these checks. Only then can the coordinator assess the remaining ticket acceptance items.

## Test without spending Claude usage

```sh
python3 -B -m unittest discover -s scripts/tests
(cd we_go_next && MIX_TEST_PARTITION=_refset TEST_PORT=4106 \
  mix test test/we_go_next/analysis/reference_query_test.exs \
           test/we_go_next/analysis/reference_scripts_test.exs)
```

The tests substitute an executable named `claude` on a private PATH. They exercise the public run/grade commands, reference-change refusal, non-overwrite behavior, failure handling, and judge isolation. Fixture bronze events test target scoping, removal, aura overlap at the last damage event, hostile NPC filtering, and exclusion of archived criteria. SQL fixtures test log scoping and aggregation in the isolated test database. No test calls the live MCP endpoint or a paid model.
