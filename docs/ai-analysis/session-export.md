# Analysis session export v1

Run from `we_go_next/` against the database containing the Analysis sessions:

```sh
mix wgn.export_analysis --session ANALYSIS_UUID \
  --transcript /path/to/claude-session.jsonl --output /tmp/analysis-session.jsonl
mix wgn.export_analysis --night 2026-09-06 \
  --transcript-dir /path/to/claude-project --output /tmp/analysis-night.jsonl
```

`--night` selects sessions **started on that UTC date**, not the combat log's
raid date. Repeat `--transcript` for reconnects or `/clear` transcripts. A directory
reads top-level `*.jsonl`, excluding subagent directories. Inputs are read-only;
the output must be a new file. Invalid JSON reports its file and line and aborts.
Exports contain private messages and real player names; keep them out of git.

Each JSONL line is an `analysis_session` record with `schema_version: 1`:

- `session`: persisted identity, start time, active log id, boss and any recorded
  Playbook metadata. `context.active_log` contains export-time log metadata.
  The original snapshot is in recorded `session_context` Tool results.
- `messages`: original Claude Code message events, including UUIDs, content,
  timestamps, usage and transcript session ids. `_source` adds file and line.
  `messages_scope: source_transcripts` means messages retain **transcript-wide**
  scope. A transcript can span multiple Analysis sessions; these messages are
  not falsely assigned to one. All supplied messages are retained for retro.
- `tool_calls`: entries with `status`, `transcript` and `server`. Server data
  includes args, the full bounded result, errors, result size and duration.
  Transcript data includes the Tool-use id, wire name, timestamp and Tool results.
- `verdicts`: persisted answer/question text, judgment, correction and timestamp.
- `unmatched`: counts of unmatched transcript calls, server rows and unscoped
  transcript calls. Each unmatched item remains in the export. Calls without an
  Analysis session id (including unrelated Claude Tools) are listed separately
  in `unscoped_transcript_calls`; no session ownership is inferred.

The pure `WeGoNext.Analysis.Export.join/3` matches by Analysis session id,
Tool name (stripping the MCP `mcp__SERVER__` prefix), exact JSON args and occurrence
order. Transcript calls are timestamp-ordered across files and line-ordered within
equal timestamps; server rows are id-ordered. Repeated identical calls consume
one row each. A missing transcript result is preserved as an empty results list.

`record_verdict` prepares and caps feedback in the normal read-only executor.
Only after successful execution does the recording path insert `analysis.verdicts`
and the Tool-call audit row atomically. No other Tool gains write access. Verdicts
have restricting session foreign keys and no automatic expiration.
