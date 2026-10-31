# Headless Analysis questions

`WeGoNext.Analysis.ask/3` starts one temporary supervised `:gen_statem` process per question. The runner stops after a terminal state, once any outstanding Tool result is appended. Retry, Continue, and verdict events restart a runner from its stored snapshot. Boot recovery marks interrupted thinking/calling_tool/writing questions failed and offers explicit Retry; it never replays paid requests. Recorded questions, messages, and Tool calls remain in Postgres.

## API

```elixir
{:ok, question, pid} = WeGoNext.Analysis.ask(
  %{"log" => "Archive-WoWCombatLog-090626_103607.txt", "boss" => "Sszorak", "pull_number" => 5},
  "Why did Sszorak pull 5 wipe: what was the first thing that went wrong?",
  subscribe: true,
  model: "claude-opus-5-5"
)

WeGoNext.Analysis.get_question(question.id)
WeGoNext.Analysis.question_event(question.id, :cancel)
WeGoNext.Analysis.question_event(question.id, :continue)
WeGoNext.Analysis.question_event(question.id, :retry)
```

`log` accepts an imported log id or a unique filename fragment, as in the existing Analysis startup. `boss` is optional. Additional scope fields describe the selected pull to the model; Tools remain pinned to the session's resolved log. Tool arguments cannot select another Analysis session.

The default model is `claude-opus-5-5`. Set `model:` when starting an Analysis session. Pass `session_id:` to ask another question in that session; its model must match. Each question currently has its own message history. Follow-up context belongs to we-cqa.5.

`subscribe: true` subscribes before the process starts, avoiding a lost first event. Alternatively, call `Analysis.subscribe_question/1`. Phoenix.PubSub broadcasts on `analysis_question:QUESTION_UUID`:

```elixir
{:analysis_question, question_id, {:state, state_atom}}
{:analysis_question, question_id, {:text_delta, text}}
{:analysis_question, question_id, {:usage, usage_map}}
{:analysis_question, question_id, {:answer, text}}
{:analysis_question, question_id, {:error, reason}}
```

State and answer notifications follow persistence. Text deltas are provisional until the complete assistant message is stored. A failed transition write returns/broadcasts an error and stops paid work; failure-state persistence is best-effort if the database remains unavailable. `QuestionRunner.snapshot/1` reads a running process or its stored snapshot without restarting it. MCP `record_verdict` advances the persisted answer to `judged` through the lifecycle table, atomically with the verdict and Tool audit. Supply optional `question_id` for explicit identity; legacy calls can identify one exact stored answer. Ambiguous or unmatched in-app answers are rejected rather than judging an arbitrary question. External MCP sessions with no question rows keep their session-only verdicts.

A deterministic built-in can use `kind: :builtin, builtin_tool: {tool_name, args}`. It uses the same recorded executor and no model. This is the adapter entry point, not the built-in picker planned in we-cqa.8.

## Model and Tool requests

`Analysis.Anthropic` calls `POST /v1/messages` through Req. It reads `ANTHROPIC_API_KEY` at request time. It does not log provider bodies or keys. Automatic HTTP retries are disabled; Retry is an explicit lifecycle event.

The system prompt reuses `priv/analysis/analyst.md`, the session identity, and the automatically loaded Playbooks. An appended instruction explains that the in-app session has already started. Tools come from the existing registry, excluding `start_session`. Both the Tool-definition prefix and system prompt have one-hour ephemeral cache breakpoints. Automatic caching also covers the growing history.

Requests disable parallel Tool use. The adapter accepts one Tool per model turn, matching the TLA+ model. An invalid or parallel Tool request gets error results and fails without executing Tools. Accepted calls go through `Analysis.call_tool/2`, including its registry validation, five-second read-only executor, bounded result, and `analysis.tool_calls` audit. A cancelled or timed-out question lets an outstanding Tool finish and stores its result without requesting another model turn.

The SSE decoder handles partial frames, Tool JSON, thinking signatures, errors, pings, unknown events, and cumulative usage. Completed Messages content is append-only. An incomplete stream fails rather than producing an answer. All usage fields are stored, including cache reads and writes. Dollar accounting and the nightly cap remain we-cqa.3.

## Lifecycle and storage

The table is `Analysis.QuestionLifecycle`. Its [complete matrix](statecharts/question-lifecycle/implementation-matrix.md) and [diagram](statecharts/question-lifecycle/implementation.mmd) are generated from the same rows and checked by tests. The compile-time validator rejects unknown names, missing state/event pairs, and missing or ambiguous fallback rows.

The ten-minute timeout is a named `:gen_statem` timeout, not a state timeout. Changing from thinking to calling a Tool cannot cancel it. Retry and Continue replace the timeout. The last model turn is reserved for an answer by sending `tool_choice: none`. Continue is accepted only once and only after any outstanding Tool has returned.

Boot recovery also repairs outstanding Tool transcripts after Cancel/timeout without changing those terminal states. An interrupted Tool gets an error result describing its unknown outcome, not a replay. Runtime options such as HTTP test plugs are not persisted; `question_event/3` accepts fresh runner options when restarting.

The [runner model and chart](../state-machines/question-runner/README.md) cover stop/restart recovery.

The default turn cap is 40, raised to 80 by Continue. Full spend/request accounting and operator-facing limit controls belong to we-cqa.3. The lifecycle counters follow the TLA+ abstraction: successful Tool or answer turns, rather than failed HTTP attempts.

Migration `20261030210000_create_analysis_questions_and_messages.exs` changes only the `analysis` schema:

- `sessions.model` stores the operator's model choice.
- `questions` stores scope, question text, model, state, lifecycle snapshot, answer, and error.
- `messages` stores ordered session/question ownership, role, complete content blocks, stop reason, usage, and timestamp.

Foreign keys restrict deletion of referenced sessions and questions. There are no medallion writes or automatic dev migrations.

## Paid verification command

After the coordinator applies the migration and provides `ANTHROPIC_API_KEY` in the runtime environment, run from `we_go_next/`:

```sh
mix wgn.ask --log Archive-WoWCombatLog-090626_103607.txt --boss Sszorak --pull 5 --model claude-opus-5-5
```

This asks corpus Q1, prints the Analysis session and question ids, and prints the final answer. One question can make several paid Messages requests while it calls Tools. The model is instructed to cite every factual claim; citation accuracy still needs the operator's live verification.

Export the printed session id without an external transcript:

```sh
mix wgn.export_analysis --session ANALYSIS_UUID --output /tmp/analysis-in-app.jsonl
```

No paid API call was made during implementation.
