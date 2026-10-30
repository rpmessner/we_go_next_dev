---- MODULE PullPipeline ----
\* One pull on the Tonight (break) page, as proposed in the we-c5q.12 design.
\* Encodes the proposed transition table as written, so TLC checks the table itself.
EXTENDS Naturals

CONSTANTS MaxAttempts

VARIABLES phase, card, attempts, rules, builtWith
vars == <<phase, card, attempts, rules, builtWith>>

Init ==
  /\ phase = "waiting"
  /\ card = "none"
  /\ attempts = 0
  /\ rules = 0          \* version of the mechanic rules / derivation stamps
  /\ builtWith = 0      \* rules version the pull's facts were built with

EncounterStart ==
  /\ phase = "waiting"
  /\ phase' = "in_progress" /\ card' = "in_progress"
  /\ UNCHANGED <<attempts, rules, builtWith>>

EncounterEnd ==
  /\ phase = "in_progress"
  /\ phase' = "importing"
  /\ UNCHANGED <<card, attempts, rules, builtWith>>

ImportedShortReset ==
  /\ phase = "importing"
  /\ phase' = "skipped" /\ card' = "none"
  /\ UNCHANGED <<attempts, rules, builtWith>>

Imported ==
  /\ phase = "importing"
  /\ phase' = "projecting"
  /\ UNCHANGED <<card, attempts, rules, builtWith>>

Projected ==
  /\ phase = "projecting"
  /\ phase' = "building_gold"
  /\ UNCHANGED <<card, attempts, rules, builtWith>>

Built ==
  /\ phase = "building_gold"
  /\ phase' = "checking" /\ builtWith' = rules
  /\ UNCHANGED <<card, attempts, rules>>

\* Fix: a card is shown only if its facts were built with the current rules.
ChecksDone ==
  /\ phase = "checking" /\ builtWith = rules
  /\ phase' = "ready" /\ card' = "shown"
  /\ UNCHANGED <<attempts, rules, builtWith>>

CheckFailed ==
  /\ phase = "checking" /\ builtWith = rules
  /\ phase' = "ready_partial" /\ card' = "shown_partial"
  /\ UNCHANGED <<attempts, rules, builtWith>>

ChecksDoneOnOldRules ==
  /\ phase = "checking" /\ builtWith # rules
  /\ phase' = "stale" /\ card' = "stale"
  /\ UNCHANGED <<attempts, rules, builtWith>>

StepFailed ==
  /\ phase \in {"importing", "projecting", "building_gold"}
  /\ phase' = "failed" /\ card' = "error" /\ attempts' = attempts + 1
  /\ UNCHANGED <<rules, builtWith>>

Retry ==
  /\ phase = "failed" /\ attempts < MaxAttempts
  /\ phase' = "importing"
  /\ UNCHANGED <<card, attempts, rules, builtWith>>

\* Rules can change at any time (an operator syncs mechanics or a derivation stamp is bumped).
\* The proposed table only reacts in ready and ready_partial; elsewhere the event is ignored.
RulesChanged ==
  /\ rules < 1
  /\ rules' = rules + 1
  /\ IF phase \in {"ready", "ready_partial"}
       THEN phase' = "stale" /\ card' = "stale"
       ELSE UNCHANGED <<phase, card>>
  /\ UNCHANGED <<attempts, builtWith>>

Rebuild ==
  /\ phase = "stale"
  /\ phase' = "projecting"
  /\ UNCHANGED <<card, attempts, rules, builtWith>>

Done ==
  /\ phase \in {"ready", "ready_partial", "skipped", "failed"}
  /\ UNCHANGED vars

Next ==
  \/ EncounterStart \/ EncounterEnd \/ ImportedShortReset \/ Imported \/ Projected
  \/ Built \/ ChecksDone \/ CheckFailed \/ ChecksDoneOnOldRules \/ StepFailed \/ Retry \/ RulesChanged
  \/ Rebuild \/ Done

Spec == Init /\ [][Next]_vars

\* Rules the reader agrees to.
CardShowsCurrentRules == card \in {"shown", "shown_partial"} => builtWith = rules
ResetNeverShown == phase = "skipped" => card = "none"
FailureIsVisible == phase = "failed" => card = "error"
RetriesBounded == attempts <= MaxAttempts
====
