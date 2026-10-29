# LLM agent loop in Phoenix: provider, client and model options

Research for ticket `we-c5q.2` (map `we-c5q`, AI analysis layer). Researched 2026-10-29.
Feeds `we-c5q.4` (where the loop runs) and `we-c5q.5` (model tier cost and season policy).
Vocabulary follows `GLOSSARY.md`: Analysis session, Tool, Playbook, Promotion, Retro.

Every price and API fact below was read from the provider's own docs or from hex.pm/GitHub
on the date above. Vendor docs change; re-check prices before locking `we-c5q.5`.

## Recommendation

- **Provider:** the Anthropic Messages API, direct. One endpoint (`POST /v1/messages`) covers tool
  use, streaming, prompt caching and mid-conversation system messages. All four current
  Claude tiers share the same tool protocol and a 1M context, so a session can move between
  tiers without code changes.
- **Client:** call the API with **plain Req** (already a dependency, 0.5.17 in `mix.lock`)
  behind one small `WeGoNext.Agent.Anthropic` module, plus an SSE line parser. Own the loop.
  Keep ReqLLM as the fallback if we later want several providers; adopting it means a Req
  0.5 to 0.6+ bump.
- **Process model:** one supervised process per Analysis session (DynamicSupervisor + Registry)
  owns the loop and the record. It streams deltas over Phoenix.PubSub to the LiveView and runs
  Tool calls under a `Task.Supervisor` with timeouts. The LiveView only renders.
- **Model tiers:** early in a raid tier `claude-opus-5-5` ($4 / $20 per MTok). As Tools and
  Playbooks are promoted, `claude-sonnet-5-5` ($2 / $10), then `claude-haiku-5-5`
  ($0.10 / $0.50). Keep `claude-fable-5-1` ($10 / $50) for hard one-off investigations.
- **Caching is mandatory.** For the reference session it cuts cost about 5x (Opus 5.5: $4.16
  uncached vs $0.84 cached). Use one breakpoint at the end of the frozen system+tools prefix
  and automatic caching for the growing tail. Use the 1-hour TTL for human-paced turns.

## 1. Anthropic Messages API

### Tool-use protocol

Source: [Tool use overview](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview),
read 2026-10-29.

- Tools are client tools: each has `name`, `description` and an `input_schema` (JSON Schema),
  plus optional `strict: true` (input guaranteed to validate against the schema),
  `eager_input_streaming` and `cache_control`.
- When Claude wants a Tool, the response has `stop_reason: "tool_use"` and one or more
  `tool_use` blocks (`id`, `name`, `input`). The app runs each call and sends back a `user`
  message containing `tool_result` blocks (`tool_use_id`, `content`, optional `is_error: true`).
  The loop repeats until `stop_reason` is `end_turn`.
- Parallel tool use is on by default. Return **all** results of one assistant turn in a single
  user message. `tool_choice: {type: "auto", disable_parallel_tool_use: true}` caps it at one
  call per turn.
- **Forced tool choice is gone on the current models.** `tool_choice` `any`/`tool` returns a
  400 on `claude-opus-5-5`, `claude-sonnet-5-5` and `claude-fable-5-1` (the tool-use pricing table
  shows no "any, tool" token count for Opus 5.5 / Sonnet 5.5). Steer with the prompt and
  `strict: true`, or use structured outputs (`output_config.format`) when you need JSON back.
- Tool definitions cost tokens like any input, plus a hidden tool-use system prompt of
  **286 tokens** on Opus 5.5, Sonnet 5.5 and Haiku 5.5 (`tool_choice` auto/none).
- Thinking: on Opus 5.5 and Fable 5.1 thinking is always on (`thinking: {type: "disabled"}` is a
  400). Depth is set with `output_config.effort` (`low` to `max`). Default effort is `medium` on
  Opus 5.5 and Haiku 5.5, `high` on Sonnet 5.5 and Fable 5.1
  ([Models overview](https://platform.claude.com/docs/en/models/overview)). Thinking tokens are
  billed as output.
- **Append-only history.** Current models bind thinking blocks to the conversation that produced
  them ("preserved thinking"), and accounts created on or after 2026-08-31 get a 400 when earlier
  turns are edited. The session process must only append to the message list, which also
  suits full session recording. Old tool results can be cleared through the server-side
  context-editing beta (`clear_tool_uses_20250919`); don't trim them by hand.
  (Source: the Anthropic `claude-api` skill reference, cached 2026-10-06; see
  [Migration guide](https://platform.claude.com/docs/en/about-claude/models/migration-guide).)

### Streaming events

Source: [Streaming messages](https://platform.claude.com/docs/en/build-with-claude/streaming),
read 2026-10-29. Set `"stream": true`. The response is server-sent events:

1. `message_start`: a `Message` with empty `content`.
2. Per content block: `content_block_start`, one or more `content_block_delta`, `content_block_stop`.
   Each block has an `index` matching its position in the final `content` array.
3. One or more `message_delta` events (with `stop_reason`, and **cumulative** `usage`).
4. `message_stop`.

Also `ping` events at any time, `error` events (for example
`{"type":"overloaded_error"}`, the in-stream form of HTTP 529), and new event types may appear,
so unknown types must be ignored.

Delta types:

- `text_delta`: `{"type":"text_delta","text":"..."}`.
- `input_json_delta`: tool input arrives as **partial JSON strings**
  (`{"type":"input_json_delta","partial_json":"{\"location\": \"San Fra"}`). Concatenate them and
  parse once at `content_block_stop`. By default the model emits one complete key/value at a
  time, so there can be pauses. `eager_input_streaming: true` on a tool streams large inputs as
  generated, but the input is then not validated server-side and can be truncated, so validate it
  yourself before running the Tool. Our Tool inputs are small (encounter ids, player names, spell
  ids), so leave it off.
- `thinking_delta` and `signature_delta`: with the default `display: "omitted"` the thinking
  block streams an empty string then a signature. Set `thinking: {type: "adaptive", display:
  "summarized"}` to show readable reasoning in the session UI. `display: "updates"` (beta) returns
  short progress notes between tool calls instead.

### Prompt caching

Source: [Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) and
[Pricing](https://platform.claude.com/docs/en/about-claude/pricing), read 2026-10-29.

- The cached prefix is rendered in the order `tools`, then `system`, then `messages`, up to the
  block marked `cache_control: {type: "ephemeral"}`. Hits require a byte-identical prefix.
- Up to 4 breakpoints. Automatic caching (top-level `cache_control`) moves one breakpoint to the
  end of the conversation each request. Each breakpoint looks back at most 20 block positions; a
  run of consecutive `tool_use` (or `tool_result`) blocks counts as one position.
- **Tool definitions, system prompt and tool results are all cacheable.** `tool_result`
  blocks in `messages` are listed as cacheable content, so large Tool outputs are paid at full
  price once (as a cache write) and at the read price on every later request in the session.
- Minimum cacheable prefix: **512 tokens** on Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.1.
  Shorter prefixes silently don't cache.
- TTL: 5 minutes by default (`ttl: "1h"` for an hour). Each read refreshes the entry at no
  cost. Longer-TTL entries must come before shorter ones.
- Multipliers on base input: 5m write 1.25x, 1h write 2x, read 0.1x, except **0.05x on Opus 5.5
  and Sonnet 5.5** and 0.025x on Fable 5.1.
- Invalidators: any change to tool definitions invalidates everything. `tool_choice`, images,
  and thinking/effort changes invalidate the messages part. Caches are per model and per
  workspace, so **switching model tier mid-session loses the cache**.
- For Playbooks: Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.1 accept `{"role": "system"}` messages
  appended to `messages` mid-conversation without invalidating the cached prefix. That is a clean way to load a
  Playbook into a running session (decision for `we-c5q.9`). Source: `claude-api` skill reference,
  cached 2026-10-06; not re-read from the live docs.

### Context limits

[Models overview](https://platform.claude.com/docs/en/models/overview), read 2026-10-29: all four current
models have a **1M-token context** and 128K max output. Long-context requests are billed at the
standard rate except on Haiku 5.5, which charges more when the prompt is **over 100,000 tokens**
($0.50 / $2.50, counting cache reads and writes toward the 100K). The current tokenizer
(since Opus 4.7) produces roughly 30% more tokens for the same text than Sonnet 4.6 and older.

### Current models and prices (USD per million tokens)

From [Pricing](https://platform.claude.com/docs/en/about-claude/pricing), read 2026-10-29.

| Model id | Input | 5m write | 1h write | Cache read | Output | Notes |
|---|---|---|---|---|---|---|
| `claude-fable-5-1` | 10.00 | 12.50 | 20.00 | 0.25 | 50.00 | Most capable; needs 30-day retention (no ZDR) |
| `claude-opus-5-5` | 4.00 | 5.00 | 8.00 | 0.20 | 20.00 | Recommended default |
| `claude-sonnet-5-5` | 2.00 | 2.50 | 4.00 | 0.10 | 10.00 | |
| `claude-haiku-5-5` (prompt up to 100K) | 0.10 | 0.125 | 0.20 | 0.01 | 0.50 | |
| `claude-haiku-5-5` (prompt over 100K) | 0.50 | 0.625 | 1.00 | 0.05 | 2.50 | |

Other modifiers: Batch API 50% off (not useful for interactive sessions, possibly useful for
Retro passes over recorded sessions). `inference_geo: "us"` adds 1.1x. Retirement is not before
September 2027 for any of the four ([Models overview](https://platform.claude.com/docs/en/models/overview)).

**Tier-switch helpers:** the
[advisor tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool) lets a
cheaper executor (e.g. Sonnet 5.5) consult a stronger advisor model mid-generation. It fits the
"cheaper model with an expensive model on call" phase of the season policy. Not evaluated in detail here.

### Brief comparison: OpenAI

[OpenAI API pricing](https://developers.openai.com/api/docs/pricing), read 2026-10-29, standard
tier, short context: `gpt-6-astra` $10 / $50 (cached input $1), `gpt-6.1-sol` $2 / $10 (cached $0.10),
`gpt-6.1-terra` $1 / $5 (cached $0.05), `gpt-6-luna` $0.10 / $0.50 (cached $0.01). Prices
are close to Anthropic's at each tier. Switching would mean a second tool-call wire format and a
second caching model. It is not a reason to start there. ReqLLM (below) hides most of that if we
ever want it.

## 2. Elixir clients

There is **no official Anthropic Elixir SDK**. Official SDKs are Python, TypeScript, Java, Go,
Ruby, C# and PHP (SDK repo list in the `claude-api` skill's live-sources).
Hex data read 2026-10-29 from `https://hex.pm/api/packages/<name>`.

| Option | Latest release | Activity | Streaming | Tool calls | Caching | Fit |
|---|---|---|---|---|---|---|
| **Plain Req** (0.5.17 locked; 0.7.5 latest, 2026-10-06) | n/a | n/a | `into: :self` + `Req.parse_message/2`, or `into: fun` (per-chunk callback). No built-in SSE parser. | We write the loop (about 100 lines) | We place `cache_control` ourselves | **Recommended** |
| [`req_llm`](https://github.com/agentjido/req_llm) | 1.29.0, 2026-10-22 | 797k downloads; pushed 2026-10-28 | `stream_text/3`; streaming goes "through Finch directly due to known Req limitations with SSE responses" | `ReqLLM.Tool`; preserves signed thinking across tool calls | `anthropic_prompt_cache`, `anthropic_prompt_cache_ttl`, `anthropic_cache_messages` | Good multi-provider option. Knows `claude-opus-5-5` and adaptive thinking (in its tests and `adapter_helpers.ex`). **Requires `req ~> 0.6`** (we lock 0.5.17) plus `finch ~> 0.22`, `llm_db`, `zoi`, `splode`, `websockex`. Its Anthropic guide still shows the `budget_tokens` thinking example, which 400s on current models. 1.29.0 fixes a TLS advisory (GHSA-6vww-5m28-f26v) for WebSocket sessions. |
| [`langchain`](https://github.com/brainlid/langchain) | 0.15.7, 2026-10-27 | 1.0M downloads; 1.2k stars | `on_llm_new_delta` callbacks, which run "in the HTTP task context", so send messages to your process | `LangChain.Function`; `LLMChain.run(mode: :while_needs_response / :until_success)` | `cache_control` on content parts and functions | Mature and maintained. `ChatAnthropic` supports adaptive thinking + `output_config` effort (CHANGELOG). Needs `req >= 0.5.3` and `ecto` (we already have both). Brings a framework (chains, callbacks) with its own message model. That is a second session schema next to our recording. |
| [`anthropic_community`](https://github.com/tubedude/anthropic-community) | 0.6.0, 2026-10-21 | 136k downloads, 15 stars | Yes (per description) | Native tool use | Not checked | Small single-maintainer project. Uses Finch directly (`finch ~> 0.24`, we lock 0.22). |
| [`anthropix`](https://github.com/lebrunel/anthropix) | 0.6.2, **2025-06-13** | Last push 2025-06-25 | Yes | Yes | Not checked | **Stale.** It predates adaptive thinking, the 2026 model ids and the forced-tool-choice change. Don't use. |
| `anthropic` (connorjacobsen) | 0.3.0, 2024-04-24 | Abandoned | | | | Don't use. |

Why plain Req: our surface is one endpoint, one provider and client tools only. What we
need from the wire (cache breakpoints, mid-conversation system messages, effort, `display`,
usage fields for cost recording) changes often, and every wrapper above lags it or needs a dep
bump. The SSE parsing is small (split on blank lines, read `event:`/`data:`). `server_sent_events` 1.1.0
(the parser ReqLLM uses) is an option if we'd rather not write it. Hand-written code must
handle `ping`, `error` and unknown event types, and must parse tool input only at
`content_block_stop`.

## 3. Streaming into LiveView and supervised Tool calls

Recommended shape (standard OTP/Phoenix building blocks; see
[`Phoenix.LiveView.start_async/4`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#start_async/4),
[`Task.Supervisor.async_nolink/3`](https://hexdocs.pm/elixir/Task.Supervisor.html#async_nolink/3),
[`Phoenix.PubSub`](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)):

```
Analysis.SessionSupervisor (DynamicSupervisor)
  └─ Analysis.Session (GenServer, one per Analysis session, Registry-named by session id)
       ├─ request task: Req POST /v1/messages, into: fun -> SSE events -> send(session, {:sse, event})
       └─ Tool tasks: Task.Supervisor.async_stream_nolink(Analysis.ToolSupervisor, calls, timeout: ...)
LiveView: subscribes to "analysis_session:<id>" on connected mount; renders deltas; sends user input
          to the Session with GenServer.cast/call.
```

- **The session process owns the loop, not the LiveView.** A LiveView process dies on navigation
  or socket reconnect. With the loop in a GenServer, a reconnect re-subscribes and renders the
  recorded transcript, and the session record (`we-c5q.11`) is written in one place. This
  is also where the loop would sit if `we-c5q.4` later exposes Tools over MCP.
- **Streaming path:** the request runs in a Task linked to the Session (or the Session uses
  `into: :self` and handles `Req.parse_message/2` in `handle_info`). Each parsed event updates
  the in-progress assistant message, then is broadcast over PubSub. The LiveView appends text
  deltas to an assign. Batch text deltas (e.g. flush every ~50 ms) so one token doesn't mean
  one diff over the socket. LiveView `stream/3` suits the list of finished turns, not the
  token-by-token tail.
- **Tool calls:** after `message_stop` with `stop_reason: "tool_use"`, run all `tool_use` blocks
  from that turn concurrently under a `Task.Supervisor` with `async_stream_nolink` and a per-Tool
  timeout. A crash or timeout becomes `tool_result` with `is_error: true` rather than killing the
  session. Put all results in one user message. Tools are plain tested Elixir functions
  over bronze/silver/gold (decided by the map: the agent never runs generated code).
- **Budgets and stops:** cap tool rounds per user turn, and check `stop_reason` for `max_tokens`
  and `refusal` before running tools. Record `usage` (`input_tokens`,
  `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`) per request so
  cost per session is a ratchet, not a guess.
- **Retries:** 429, 529 and in-stream `overloaded_error` are retryable with backoff. Retry the
  whole request; the history is append-only, so a retry re-sends identical bytes and hits cache.

## 4. Cost per Analysis session

### Assumed shape

- 8 operator turns, 20 Tool calls (3,2,3,2,3,2,3,2 per turn, each in its own round, which is the
  worst case; parallel calls would mean fewer requests).
- So **28 API requests**: 20 that end in `tool_use` plus 8 final answers.
- Prefix: 15 KB system + tool definitions. At **3 bytes per token** (an assumption for
  JSON-heavy text on the current tokenizer, which gives about 30% more tokens than older ones)
  that is 5,000 tokens, plus the 286-token tool-use system prompt: **5,286 tokens**.
- Tool results: 2, 6 or 10 KB each, so 667, 2,000 or 3,333 tokens.
- Operator message 100 tokens. Output (thinking + text + `tool_use`) 400 tokens per tool-call
  request and 1,200 per final answer: 20×400 + 8×1,200 = **17,600 output tokens**. That is a guess at
  medium effort; measure it.
- Each request re-sends the whole history. Cached case: each request reads what the previous
  request wrote and writes only the new delta at the 5m rate, with turn gaps under 5 minutes.

### Token totals (from a small simulation of the above)

| Result size | Final context | Input tokens summed over 28 requests | of which cache reads | cache writes |
|---|---|---|---|---|
| 2 KB | 37,006 | 576,220 | 540,414 | 35,806 |
| 6 KB | 63,686 | 952,408 | 889,922 | 62,486 |
| 10 KB | 90,346 | 1,328,314 | 1,239,168 | 89,146 |

Formulas: uncached = input × base + output × out. Cached = writes × 5m-write +
reads × read + output × out.

Worked example, Opus 5.5 at 6 KB:
- uncached: 952,408 × $4/M = $3.810 input + 17,600 × $20/M = $0.352 output → **$4.16**
- cached: 62,486 × $5/M = $0.312 + 889,922 × $0.20/M = $0.178 + $0.352 output → **$0.84**

### Cost per session (USD)

| Model | 2 KB uncached | 2 KB cached | 6 KB uncached | 6 KB cached | 10 KB uncached | 10 KB cached |
|---|---|---|---|---|---|---|
| `claude-fable-5-1` | 6.64 | 1.46 | 10.40 | 1.88 | 14.16 | 2.30 |
| `claude-opus-5-5` | 2.66 | 0.64 | 4.16 | 0.84 | 5.67 | 1.05 |
| `claude-sonnet-5-5` | 1.33 | 0.32 | 2.08 | 0.42 | 2.83 | 0.52 |
| `claude-haiku-5-5` | 0.07 | 0.02 | 0.10 | 0.03 | 0.14 | 0.03 |

Readings:

- Uncached, input dominates (over 90%) because the history is re-sent 28 times. Caching cuts it by
  5-6x. With caching, output becomes the largest part of the bill on Opus/Sonnet (about 40%).
- **Cache misses from slow replies.** If the operator replies after more than 5 minutes, that turn's
  request re-writes the whole history instead of reading it. With all 7 later turns missing
  in the 6 KB case (the turn-start contexts of turns 2-8 sum to 246,902 tokens, re-written
  instead of read), Opus 5.5 pays roughly 246,902 × ($5.00 − $0.20)/M ≈ **+$1.19** per session. The 1-hour TTL avoids that for little:
  writes are only the deltas (62,486 tokens), so 1h writes cost 62,486 × $8/M = $0.50 instead of
  $0.31 at 5m, **+$0.19**. Use `ttl: "1h"` for between-pull sessions.
- Haiku 5.5 stays under its 100K price threshold for all three sizes (final context 90K at 10 KB).
  Larger sessions cross it and the price jumps 5x for those requests.
- Tier ratio per session (cached, 6 KB): Fable 5.1 : Opus 5.5 : Sonnet 5.5 : Haiku 5.5 ≈
  45 : 20 : 10 : 0.6 (cents ≈ 188 : 84 : 42 : 2.6). Haiku is cheap enough to run every
  Auto-run Tool after each pull. Note the figures assume the same output length per model;
  cheaper models at higher effort or with more retries change that.
- Script: `cost.py` (scratch, not committed). The numbers are reproducible from the formulas
  above.

## 5. Data handling

### What leaves the machine

Only what goes into a request: the system prompt, Tool definitions, operator messages and
**every Tool result**. Raw logs are not uploaded unless a Tool returns raw lines. Tool results
will typically contain:

- character names with realm (`"Favikul-Area52-US"` form in the combat log), player GUIDs
  (`Player-3676-0E1BB922`), class/spec, deaths, damage taken, failures and timestamps;
- encounter, spell and NPC ids, which are public game data.

Combat logs are written by the client for everyone in the group, so this is other players'
data, not just the operator's. The local-operator-only scope (map `we-c5q`) keeps sessions off
the public mirror. Options that do not cost accuracy:

- Tools return a stable per-session alias (`P1`, `P2`, or class+role) instead of the name, and
  the LiveView maps aliases back to names locally when rendering. The model never needs the
  real name to reason about mechanics. Decide in `we-c5q.7` (Tool contract).
- Never send GUIDs; they are join keys and useless to the model.

### Anthropic API terms

- **Training:** for commercial offerings including the Anthropic API, "We will not use your
  chats or coding sessions to train our models" unless the customer joins the Development
  Partner Program or explicitly submits feedback
  ([privacy.claude.com 7996885](https://privacy.claude.com/en/articles/7996885-is-my-data-used-for-model-training),
  dated 2026-03-16).
- **Retention:** "we automatically delete inputs and outputs on our backend within 30 days of
  receipt or generation." Exceptions: longer-lived services you control (Files API), a zero data
  retention agreement, Usage Policy enforcement, and legal obligations. Content flagged by trust
  and safety classifiers is kept up to 2 years, classifier scores up to 7 years
  ([privacy.claude.com 7996866](https://privacy.claude.com/en/articles/7996866-how-long-does-anthropic-store-my-organizations-data),
  updated 2026-07-01).
- **Zero data retention:** available by agreement. `claude-fable-5-1` requires 30-day retention
  and is not available under ZDR unless Anthropic authorizes it (the `claude-api` skill reference).
- **Cache isolation:** prompt caches are isolated per organization and per workspace.

## 6. Roadmap option: TypeSafe Jev as a router or Tool selector

Not part of the first slice. Jev is a "System One" model from TypeSafe AI (early access,
announced 2026-09-15). Instead of text, it returns **typed decisions with calibrated probabilities**
over a supplied state.

**API shape** ([TypeSafe API reference](https://docs.typesafe.ai/api/system-one.md),
[Models](https://docs.typesafe.ai/models.md), read 2026-10-29):

```
POST https://api.typesafe.ai/v1/systemone
Authorization: Bearer $TYPESAFE_API_KEY
{"model": "jev-latest",
 "state": "<text or JSON>",
 "questions": {
   "intent": {"type": "choice", "instructions": "Which Tool answers this?",
              "criteria": {"deaths_summary": "...", "mechanic_failures": "..."}},
   "needs_deep_reasoning": {"type": "noul", "instructions": "Does this need multi-step investigation?"}}}
```

Question types: `choice` (returns `choice`, `probabilities` and `confidence`), `score` (ordered levels;
returns `score`, `probabilities` and `confidence`), `noul` (probability of yes) and `box` (image
region; needs a header). Answers are keyed by question name and carry `usage`. Questions
are evaluated in parallel in one request. No free text, reasoning or streaming. Limits: 64K tokens
per request and 32K per question by default; 262K with the `TypeSafe-Danger-Zone-Long-Context: true`
header, which TypeSafe says is "slower and less accurate". Models: `jev-1.14.0` (from 2026-10-14) and `jev-1.13.0`.
SDKs: Python and JavaScript/TypeScript only ([Client SDKs](https://docs.typesafe.ai/sdk.md)).

**Calling from Elixir:** a plain JSON POST with a bearer token. `Req.post!(url, json: body,
auth: {:bearer, key})` covers it; no SDK needed. Errors are standard HTTP (429 and 529 mean
retry with backoff), the body can be up to 32 MiB, gzip/zstd are accepted
([Request rules and errors](https://docs.typesafe.ai/api/errors.md)).

**Access routes and pricing (sources disagree):**

| Source | Route | Input price per M tokens | Output |
|---|---|---|---|
| [TypeSafe Models page](https://docs.typesafe.ai/models.md) | direct, `jev-1.14.0` | **$0.042** ($42 per billion) | free |
| [OpenRouter endpoints API](https://openrouter.ai/api/v1/models/typesafe/jev-1.14/endpoints) | `typesafe/jev-1.14`, provider TypeSafe, context 262,144 | **$0.042** (`"prompt":"0.000000042"`) | 0 |
| [ZenMux TypeSafe page](https://zenmux.ai/typesafe) | `typesafe/jev-1.14`, `typesafe/jev-1.13` | **$0.042** | "-" |
| [AI/ML API model page](https://aimlapi.com/models/typesafe-jev-latest) | `typesafe/jev` via `POST /v1/decisions` | **$0.042** in the header and pricing table but **$0.0577668** in its "API Pricing" section and FAQ. The same page also gives two context figures (256K vs 32,000) | free |

So $0.042 is the vendor price and is confirmed by OpenRouter and ZenMux. The ~$0.058
figure appears only on AI/ML API's own page, which contradicts itself. Assume it is that
reseller's price, not TypeSafe's.

**Jev Router on OpenRouter:** `typesafe/jev-router`
([model page](https://openrouter.ai/typesafe/jev-router), listed 2026-09-25) "picks the best
model and reasoning effort for each request" and runs on Jev. It is called like any model via
OpenAI-compatible `POST /api/v1/chat/completions`. Its listed price is `-1` (variable, billed as
the routed model), context 1,000,000. Not available through OpenRouter's EU in-region routing.
OpenRouter also exposes Jev itself at `POST /api/alpha/decisions` and
`POST /api/v1/systemone` ([OpenRouter Jev guide](https://openrouter.ai/docs/guides/community/jev)).

**Latency:** vendor figures only. The [TypeSafe homepage](https://typesafe.ai) shows
"Completed in 0.114s" vs "8.566s" for an LLM on its own System One workflow; AI/ML API quotes
"70–500 ms end to end, vendor-reported" and a measured 216 ms 24-hour gateway median. Neither
has been checked on our workload.

**Data hosting:** TypeSafe's [privacy policy](https://typesafe.ai/legal/privacy-policy)
(dated 2025-11-19) says services are hosted in the U.S. and it "will not train or fine tune
any artificial intelligence or machine learning models on Input". It sets no fixed retention
period ("as long as reasonably necessary"). The [DPA](https://typesafe.ai/legal/data-processing)
(2026-04-24) names subprocessors only via its trust site. ZDR is offered to enterprise customers
([Legal](https://docs.typesafe.ai/legal.md)). Via OpenRouter, OpenRouter's own data policy
also applies (not reviewed here).

**Fit for us:**
- *Model/effort routing* (Jev Router): it picks among OpenRouter models, so it means routing the
  whole agent loop through OpenRouter's OpenAI-compatible API. That loses Anthropic-specific
  levers (cache breakpoints, mid-conversation system messages), and model switches lose the cache.
  A poor fit for long Analysis sessions. Our own season policy (`we-c5q.5`) is simpler and auditable.
- *Tool / Playbook selection* (Jev direct): a better fit later. One `choice` question over the
  promoted Tool and Playbook catalogue, plus a `noul` like "needs deep reasoning?", could pick the
  Playbook and decide whether a cheap model can answer a question, at about $0.000042 per 1K
  input tokens. Use confidence as a gate: low confidence escalates to the expensive tier. This
  fits Auto-run and Promotion work after Tools exist. It only needs Req.

## Facts not confirmed

- The exact Anthropic doc wording for mid-conversation system messages, preserved thinking
  enforcement and forced `tool_choice` 400s comes from the bundled `claude-api` skill reference
  (cached 2026-10-06), not from a live page read today. The pricing page's missing "any, tool"
  token counts for Opus 5.5/Sonnet 5.5 are consistent with it.
- The bytes-per-token ratio (3) and output tokens per request are assumptions. Measure them with
  `POST /v1/messages/count_tokens` on real Tool output and with recorded `usage` before
  `we-c5q.5` sets budgets.
- How much of prior-turn thinking stays in context on Opus 5.5 (and is billed as input) was not
  checked. The model above ignores it.
- `anthropic_community` caching support, and whether its streaming handles thinking blocks:
  not checked.
- OpenAI caching behaviour (automatic or not): the pricing page lists cached-input rates but
  not the mechanism; not checked further.
- TypeSafe retention period for API inputs and its subprocessor list: not published on the
  pages read. Jev latency on our data: unmeasured.
