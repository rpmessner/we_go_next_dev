# Headless Analysis questions

`WeGoNext.Analysis.ask/3` starts one temporary supervised `:gen_statem` process per question. The process stays alive after an answer or stop so callers can send Retry, Continue, or a verdict event. A node restart does not replay paid requests. Recorded questions, messages, and Tool calls remain in Postgres.

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
```

State and answer notifications follow persistence. Text deltas are provisional until the complete assistant message is stored. `QuestionRunner.snapshot/1` synchronously reads a running process. After recording an operator verdict through the existing `record_verdict` Tool, callers can send `:record_verdict` to advance an answered question to `judged`.

A deterministic built-in can use `kind: :builtin, builtin_tool: {tool_name, args}`. It uses the same recorded executor and no model. This is the adapter entry point, not the built-in picker planned in we-cqa.8.

## Model and Tool requests

`Analysis.Anthropic` calls `POST /v1/messages` through Req. It reads `ANTHROPIC_API_KEY` at request time. It does not log provider bodies or keys. Automatic HTTP retries are disabled; Retry is an explicit lifecycle event.

The system prompt reuses `priv/analysis/analyst.md`, the session identity, and the automatically loaded Playbooks. An appended instruction explains that the in-app session has already started. Tools come from the existing registry, excluding `start_session`. Both the Tool-definition prefix and system prompt have one-hour ephemeral cache breakpoints. Automatic caching also covers the growing history.

Requests disable parallel Tool use. The adapter accepts one Tool per model turn, matching the TLA+ model. An invalid or parallel Tool request gets error results and fails without executing Tools. Accepted calls go through `Analysis.call_tool/2`, including its registry validation, five-second read-only executor, bounded result, and `analysis.tool_calls` audit. A cancelled or timed-out question lets an outstanding Tool finish and stores its result without requesting another model turn.

The SSE decoder handles partial frames, Tool JSON, thinking signatures, errors, pings, unknown events, and cumulative usage. Completed Messages content is append-only. An incomplete stream fails rather than producing an answer. All usage fields are stored, including cache reads and writes. Dollar accounting and the nightly cap remain we-cqa.3.

## Lifecycle and storage

The table is `Analysis.QuestionLifecycle`. Its [complete matrix](statecharts/question-lifecycle/implementation-matrix.md) and [diagram](statecharts/question-lifecycle/implementation.mmd) are generated from the same rows and checked by tests. The compile-time validator rejects unknown names, missing state/event pairs, and missing or ambiguous fallback rows.

The ten-minute timeout is a named `:gen_statem` timeout, not a state timeout. Changing from thinking to calling a Tool cannot cancel it. Retry and Continue replace the timeout. The last model turn is reserved for an answer by sending `tool_choice: none`. Continue is accepted only once and only after any outstanding Tool has returned.

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

## First live run (2026-10-31)

`mix wgn.ask --log Archive-WoWCombatLog-090626_103607.txt --boss Sszorak --pull 5` asked corpus Q1. The run was Analysis session `a5e057c4-55af-466f-9f20-84cb40792dbb`, question `d0519f30-80bd-4312-bb76-e25f053b665d`, and it ended `answered`.

- **Answer:** the first death was Kahnu at 2:35 to Mutilate, matching revision 2 of the reference. Claims carried citations and inferences were labelled. One factual slip: it called Mädz a Survival Hunter; the reference says Beast Mastery.
- **Calls:** 10 model requests and 9 Tool calls, including one `wipe_cause`.
- **Tokens:** 22 uncached input, 153,814 cache-read, 37,039 cache-write and 3,561 output.
- **Cost:** about $0.40 at the documented Opus 5.5 rates. The same question cost $4.20 in the Claude Code baseline and $1.37 in the post-promotion rerun.
- **Export:** `mix wgn.export_analysis` matched every Tool call.
