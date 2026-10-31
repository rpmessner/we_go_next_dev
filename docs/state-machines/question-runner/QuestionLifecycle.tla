---- MODULE QuestionLifecycle ----
\* One question node plus its temporary runner process (we-g18.5).
\* Budget is counted in model turns
\* (each turn costs spend and one request); Limit stands for $5 / 40 requests.
EXTENDS Naturals

CONSTANTS Limit, RaisedLimit

VARIABLES process, phase, kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict
vars == <<process, phase, kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

Running == {"thinking", "calling_tool", "writing"}

Init ==
  /\ process = "up"
  /\ phase = "draft"
  /\ kind \in {"builtin", "agent"}
  /\ turns = 0 /\ cap = Limit /\ raised = FALSE
  /\ toolInFlight = FALSE /\ toolCalls = 0 /\ recorded = 0
  /\ timer = FALSE /\ modelCalls = 0 /\ verdict = FALSE

AskBuiltin ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase = "draft" /\ kind = "builtin"
  /\ phase' = "computing"
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

Computed ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase = "computing"
  /\ phase' = "answered"
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

AskAgent ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase = "draft" /\ kind = "agent"
  /\ phase' = "thinking" /\ timer' = TRUE
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, modelCalls, verdict>>

\* Fix 3: Tools may use the budget except its last turn, which is reserved for the answer.
ToolRequested ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase = "thinking" /\ turns + 1 < cap
  /\ phase' = "calling_tool" /\ turns' = turns + 1 /\ modelCalls' = modelCalls + 1
  /\ toolInFlight' = TRUE /\ toolCalls' = toolCalls + 1
  /\ UNCHANGED <<kind, cap, raised, recorded, timer, verdict>>

OverLimit ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase = "thinking" /\ turns >= cap
  /\ phase' = "limit_hit"
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

\* Tool results are appended even after Cancel or timeout.
ToolReturned ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ toolInFlight
  /\ toolInFlight' = FALSE
  /\ recorded' = recorded + 1   \* Fix 2: the result is recorded in every state
  /\ IF phase = "calling_tool" THEN phase' = "thinking" ELSE UNCHANGED phase
  /\ UNCHANGED <<kind, turns, cap, raised, toolCalls, timer, modelCalls, verdict>>

AnswerStarted ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase = "thinking" /\ turns < cap
  /\ phase' = "writing" /\ turns' = turns + 1 /\ modelCalls' = modelCalls + 1
  /\ UNCHANGED <<kind, cap, raised, toolInFlight, toolCalls, recorded, timer, verdict>>

AnswerDone ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase = "writing"
  /\ phase' = "answered" /\ timer' = FALSE
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, modelCalls, verdict>>

\* The 10-minute timer fires once, including while writing.
Timeout ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ timer
  /\ timer' = FALSE
  /\ IF phase \in Running   \* Fix 1: the timer stops writing too
       THEN phase' = "limit_hit"
       ELSE UNCHANGED phase
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, modelCalls, verdict>>

ApiError ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase \in {"thinking", "writing"}
  /\ phase' = "failed"
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

Retry ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase = "failed"
  /\ phase' = "thinking" /\ timer' = TRUE   \* Fix 1: Retry re-arms the timer
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, modelCalls, verdict>>

Cancel ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase \in Running
  /\ phase' = "cancelled"
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

\* Fix 4: continuing waits for a Tool that is still running, so its late result is not
\* mistaken for the next call's result.
ContinueWithNewCap ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase = "limit_hit" /\ ~raised /\ ~toolInFlight
  /\ phase' = "thinking" /\ raised' = TRUE /\ cap' = RaisedLimit /\ timer' = TRUE
  /\ UNCHANGED <<kind, turns, toolInFlight, toolCalls, recorded, modelCalls, verdict>>

RecordVerdict ==
  /\ process = "up"
  /\ UNCHANGED process
  /\ phase \in {"answered", "judged"}
  /\ phase' = "judged" /\ verdict' = TRUE
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls>>

Stop ==
  /\ process = "up" /\ phase \in {"cancelled", "limit_hit", "answered", "judged", "failed"}
  /\ ~toolInFlight
  /\ process' = "down"
  /\ UNCHANGED <<phase, kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

Crash ==
  /\ process = "up" /\ (phase \in Running \/ toolInFlight)
  /\ process' = "lost"
  /\ UNCHANGED <<phase, kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

Recover ==
  /\ process = "lost"
  /\ process' = "down" /\ timer' = FALSE
  /\ phase' = IF phase \in Running THEN "failed" ELSE phase
  /\ toolInFlight' = FALSE /\ recorded' = toolCalls
  /\ UNCHANGED <<kind, turns, cap, raised, toolCalls, modelCalls, verdict>>

RestartOnDemand ==
  /\ process = "down" /\ phase \in {"failed", "limit_hit", "answered", "judged"}
  /\ process' = "up"
  /\ UNCHANGED <<phase, kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

Done ==
  /\ phase \in {"cancelled", "limit_hit", "answered", "judged", "failed"}
  /\ UNCHANGED vars

Next ==
  \/ AskBuiltin \/ Computed \/ AskAgent \/ ToolRequested \/ OverLimit \/ ToolReturned
  \/ AnswerStarted \/ AnswerDone \/ Timeout \/ ApiError \/ Retry \/ Cancel
  \/ ContinueWithNewCap \/ RecordVerdict \/ Stop \/ Crash \/ Recover \/ RestartOnDemand \/ Done

Spec == Init /\ [][Next]_vars

\* Keeps the retry loop finite for the model checker.
Bounded == turns <= RaisedLimit + 2

\* Rules the reader agrees to.
BuiltinNeverCallsModel == kind = "builtin" => modelCalls = 0
StaysWithinBudget == turns <= cap
RunningHasTimer == phase \in Running => timer
EveryToolCallRecorded == ~toolInFlight => recorded = toolCalls
VerdictOnlyOnAnswers == verdict => phase = "judged"

StoppedIsQuiescent == process = "down" => phase \notin Running /\ ~toolInFlight
====
