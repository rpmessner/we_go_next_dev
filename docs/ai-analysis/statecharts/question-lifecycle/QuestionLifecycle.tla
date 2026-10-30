---- MODULE QuestionLifecycle ----
\* One question node in the Analysis tree, as proposed in the we-c5q.12 design.
\* Encodes the proposed transition table as written. Budget is counted in model turns
\* (each turn costs spend and one request); Limit stands for $5 / 40 requests.
EXTENDS Naturals

CONSTANTS Limit, RaisedLimit

VARIABLES phase, kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict
vars == <<phase, kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

Running == {"thinking", "calling_tool", "writing"}

Init ==
  /\ phase = "draft"
  /\ kind \in {"builtin", "agent"}
  /\ turns = 0 /\ cap = Limit /\ raised = FALSE
  /\ toolInFlight = FALSE /\ toolCalls = 0 /\ recorded = 0
  /\ timer = FALSE /\ modelCalls = 0 /\ verdict = FALSE

AskBuiltin ==
  /\ phase = "draft" /\ kind = "builtin"
  /\ phase' = "computing"
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

Computed ==
  /\ phase = "computing"
  /\ phase' = "answered"
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

AskAgent ==
  /\ phase = "draft" /\ kind = "agent"
  /\ phase' = "thinking" /\ timer' = TRUE
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, modelCalls, verdict>>

\* Fix 3: Tools may use the budget except its last turn, which is reserved for the answer.
ToolRequested ==
  /\ phase = "thinking" /\ turns + 1 < cap
  /\ phase' = "calling_tool" /\ turns' = turns + 1 /\ modelCalls' = modelCalls + 1
  /\ toolInFlight' = TRUE /\ toolCalls' = toolCalls + 1
  /\ UNCHANGED <<kind, cap, raised, recorded, timer, verdict>>

OverLimit ==
  /\ phase = "thinking" /\ turns >= cap
  /\ phase' = "limit_hit"
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

\* The Tool result arrives asynchronously. The table handles tool_returned only in calling_tool;
\* in any other state the event is ignored, so the result is not recorded.
ToolReturned ==
  /\ toolInFlight
  /\ toolInFlight' = FALSE
  /\ recorded' = recorded + 1   \* Fix 2: the result is recorded in every state
  /\ IF phase = "calling_tool" THEN phase' = "thinking" ELSE UNCHANGED phase
  /\ UNCHANGED <<kind, turns, cap, raised, toolCalls, timer, modelCalls, verdict>>

AnswerStarted ==
  /\ phase = "thinking" /\ turns < cap
  /\ phase' = "writing" /\ turns' = turns + 1 /\ modelCalls' = modelCalls + 1
  /\ UNCHANGED <<kind, cap, raised, toolInFlight, toolCalls, recorded, timer, verdict>>

AnswerDone ==
  /\ phase = "writing"
  /\ phase' = "answered" /\ timer' = FALSE
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, modelCalls, verdict>>

\* The 10-minute timer fires once. The table maps it only in thinking and calling_tool.
Timeout ==
  /\ timer
  /\ timer' = FALSE
  /\ IF phase \in Running   \* Fix 1: the timer stops writing too
       THEN phase' = "limit_hit"
       ELSE UNCHANGED phase
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, modelCalls, verdict>>

ApiError ==
  /\ phase \in {"thinking", "writing"}
  /\ phase' = "failed"
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

Retry ==
  /\ phase = "failed"
  /\ phase' = "thinking" /\ timer' = TRUE   \* Fix 1: Retry re-arms the timer
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, modelCalls, verdict>>

Cancel ==
  /\ phase \in Running
  /\ phase' = "cancelled"
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls, verdict>>

\* Fix 4: continuing waits for a Tool that is still running, so its late result is not
\* mistaken for the next call's result.
ContinueWithNewCap ==
  /\ phase = "limit_hit" /\ ~raised /\ ~toolInFlight
  /\ phase' = "thinking" /\ raised' = TRUE /\ cap' = RaisedLimit /\ timer' = TRUE
  /\ UNCHANGED <<kind, turns, toolInFlight, toolCalls, recorded, modelCalls, verdict>>

RecordVerdict ==
  /\ phase \in {"answered", "judged"}
  /\ phase' = "judged" /\ verdict' = TRUE
  /\ UNCHANGED <<kind, turns, cap, raised, toolInFlight, toolCalls, recorded, timer, modelCalls>>

Done ==
  /\ phase \in {"cancelled", "limit_hit", "answered", "judged"}
  /\ UNCHANGED vars

Next ==
  \/ AskBuiltin \/ Computed \/ AskAgent \/ ToolRequested \/ OverLimit \/ ToolReturned
  \/ AnswerStarted \/ AnswerDone \/ Timeout \/ ApiError \/ Retry \/ Cancel
  \/ ContinueWithNewCap \/ RecordVerdict \/ Done

Spec == Init /\ [][Next]_vars

\* Keeps the retry loop finite for the model checker.
Bounded == turns <= RaisedLimit + 2

\* Rules the reader agrees to.
BuiltinNeverCallsModel == kind = "builtin" => modelCalls = 0
StaysWithinBudget == turns <= cap
RunningHasTimer == phase \in Running => timer
EveryToolCallRecorded == ~toolInFlight => recorded = toolCalls
VerdictOnlyOnAnswers == verdict => phase = "judged"
====
