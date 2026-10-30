# Analysis statecharts

TLA+ models of the app flow and the two state machines proposed for the Analysis screens (we-c5q.12). TLC checks each model against the rules the operator agreed to, and the statechart skill draws `chart.mmd` from the states it explores. The models are a design check, not code. When the transition tables are implemented, each machine's pure `step` table must match its model, and each rule becomes a property test.

| Machine | Drives | Rules checked |
|---|---|---|
| `app-flow` | Navigation between the Analysis screens | Cancel returns where the picker was opened; Back from a Death Recap jump returns to the answer; every question has a scope |
| `pull-pipeline` | One pull's card on the Tonight (break) page | a shown card uses the current rules; a short reset is never shown; a failed pull shows its error; retries are bounded |
| `question-lifecycle` | One question in the Analysis tree | a built-in with a deterministic Tool never calls the model; the budget is never exceeded; a running question always has its 10-minute timer; every Tool call is recorded; a verdict exists only on an answer |

Five gaps in the first proposed tables were found by TLC and fixed in these models:

1. **Pull pipeline:** a rules change while the checks ran produced a "ready" card built on old rules. Fix: checks that finish on old rules mark the card stale.
2. **Question:** the 10-minute timer was ignored while the answer was being written. Fix: the timer stops any running state.
3. **Question:** a Tool result that arrived after Cancel or the timer was dropped, not recorded. Fix: results are always recorded.
4. **Question:** the answer turn was not checked against the budget. Fix: the last turn of the budget is reserved for the answer.
5. **Question:** "continue with a new cap" while a timed-out Tool was still running let the agent start a second call that took the first call's late result. Fix: continue waits for the running Tool. Retry also re-arms the timer.

## Elixir question lifecycle

The headless adapter is documented in [Headless Analysis questions](../agent-loop.md).
`WeGoNext.Analysis.QuestionLifecycle` implements every model action, including
ignored pairs, as rows. The generated `implementation-matrix.md` and
`implementation.mmd` live beside the question model and are checked by ExUnit.
The five model rules are tested after each prefix of seeded random event sequences.

Regenerate the implementation artifacts from `we_go_next/` without starting the app:

```sh
MIX_ENV=test mix run --no-start -e 'alias WeGoNext.Analysis.QuestionLifecycle, as: M; File.write!("../docs/ai-analysis/statecharts/question-lifecycle/implementation-matrix.md", M.matrix()); File.write!("../docs/ai-analysis/statecharts/question-lifecycle/implementation.mmd", M.diagram())'
```

## Regenerate

Requires the `statechart` skill and TLC (`tla2tools.jar` v1.7.4). Use a new `--out` folder each time:

```sh
export TLA2TOOLS=/path/to/tla2tools.jar JAVA=$(command -v java)
cd docs/ai-analysis/statecharts/pull-pipeline
~/.claude/skills/statechart/scripts/statechart PullPipeline.tla --view view.ts --out /tmp/pull-chart
cd ../question-lifecycle
~/.claude/skills/statechart/scripts/statechart QuestionLifecycle.tla --view view.ts --out /tmp/question-chart
cd ../app-flow
~/.claude/skills/statechart/scripts/statechart AppFlow.tla --view view.ts --out /tmp/app-chart
```

What the models leave out: real spend amounts and request counts (budget is counted in model turns, with small limits); several pulls at once (one machine per pull); the content of answers and checks; Tool errors (they behave like a Tool returning).

Render each `chart.mmd` to `chart.svg` with Pele 1.9.0, per the statechart skill's `references/render.md`.
