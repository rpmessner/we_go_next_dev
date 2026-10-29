# Analysis tracer contracts

## Tool interface

`WeGoNext.Analysis.Tool` declares `name/0`, `description/0`, `input_schema/0`,
and `run(args, session)`. JSON args have string keys. The session is a persisted
`WeGoNext.Analysis.Session`, not an MCP connection or the current FileWatcher log.
`Registry.tools/0` is the enabled module list. `Registry.definitions/0` produces
MCP definitions. The tracer enables only `session_context` and `list_pulls`.

Every Tool input includes `session_id`, the UUID returned by the
`analysis-session` prompt. `list_pulls` accepts optional `boss`, `night`, and
`cursor` strings. Boss matches an exact name or WoW encounter id. Night is a UTC
`YYYY-MM-DD` date, always within the session log. The session's optional boss
argument records intent; it does not hide other bosses in that log.

`run/2` returns `{:ok, envelope}` or `{:error, short_reason}`. Successful envelopes
have `data`, `evidence`, `truncated`, and `next_cursor`. `Result.page/5` accepts
ordered `{data_row, evidence_row}` pairs, JSON args, a `{tool_name, session_id}`
scope, an optional data renderer, and an optional byte cap. It measures the whole
JSON envelope, including evidence and cursor, against 8,192 bytes by default.
A row that cannot fit alone returns a Tool error instead of silently dropping data.

Cursors encode a row offset and a digest of the scope and filters. They are not
authentication tokens. Continuations use the same Tool, session, and filters.
Results are deterministic against unchanged source data; imports between pages
can change the ordering. Restart pagination after an import.

`session_context` limits each page to 3,072 bytes. Pull rows precede roster rows.
Freshness counts cover the entire log; freshness id lists cover the current page.
Null `pull_id` means the public import catalogue has no matching gold encounter.
`public_encounter_id` is bookkeeping, never the analytics pull id. Roster fields
come from silver without aliasing. Class and spec are numeric ids, or null when
unknown. Missing failure facts do not establish that a pull is fresh or clean.

## Execution and recording

`Analysis.call_tool/2` resolves the session, validates inputs with `Arguments`,
and calls `Executor.run/3`. `Arguments` supports the JSON Schema subset listed
in its module documentation, including nested objects and arrays. A Tool needing
other schema keywords must extend that validator with tests. Each execution uses a supervised, unlinked task with
a five-second deadline and a read-only Postgres transaction. Statement timeout
is also five seconds. Tool code must not write files. The two tracer Tools read
only existing database rows; neither reparses logs nor rebuilds medallion data.

The executor returns errors without stack traces or internal exception messages.
The caller records success or failure outside the read-only transaction in
`analysis.tool_calls`. `result` is the full bounded envelope sent in MCP text
content, `result_size` measures its encoded JSON bytes, and `duration_ms` measures
execution through result preparation, excluding audit insertion. Error envelopes
also have `error`; MCP returns them with `isError: true`.

Unknown or missing sessions produce audit rows with a null session foreign key.
The original args retain the supplied id. Existing sessions and calls have
restricting foreign keys and no automatic expiration. Verdicts, Playbooks, and
messages are not part of this migration.

## MCP transport

`POST /analysis/mcp` uses stateless Streamable HTTP with JSON responses and MCP
protocol revision `2025-03-26`. Initialization advertises Tools and prompts.
Notifications return HTTP 202; GET returns 405 because there is no SSE stream.
The negotiated March revision supports request batches, except initialization.
There is no MCP transport session id. Invoking `prompts/get` for
`analysis-session` always inserts a new Analysis session, even after reconnects.
The optional `log` argument is a `combat_log_files.id` string. Without it, the
prompt selects the latest non-null `last_parsed_at`, breaking ties by log id.

Only dev enables the endpoint; tests enable it explicitly for protocol checks.
The plug checks the socket peer, Host, and optional Origin before reading JSON.
Only loopback peers and localhost hosts/origins pass. Forwarded headers cannot
relax the check. Dev's existing `0.0.0.0` binding and Tidewave remain unchanged.
Requests are limited to 64 KiB. No authentication is added beyond local access.

### Transport choice

The maturity check found [Anubis MCP](https://github.com/zoedsoupe/anubis-mcp),
the maintained Hermes successor, with Streamable HTTP server support. The tracer
uses a thin Plug endpoint instead: this ticket needs only synchronous JSON
responses, notifications, and no transport session state. It adds no dependency
or provider client. The protocol tests cover this limited implementation.

Sources checked for this choice:

- [MCP Streamable HTTP, 2025-03-26](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports)
- [MCP initialization lifecycle](https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle)
- [Anubis transport documentation](https://anubis-mcp.hexdocs.pm/transports.html)

The connection command and operator verification steps are in the build report.
