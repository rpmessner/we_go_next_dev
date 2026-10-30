---- MODULE AppFlow ----
\* Navigation between the Analysis screens proposed in we-c5q.12: which screen you are on,
\* and where Cancel and Back take you. Both evidence modes (side inspector, jump to Death
\* Recap) and both placements (full page, docked panel) are in, as the operator asked.
EXTENDS Naturals

VARIABLES screen, pickerFrom, scope, backTo
vars == <<screen, pickerFrom, scope, backTo>>

Screens == {"tonight", "encounter", "docked", "failures", "picker", "question", "inspector", "recap_jump"}

Init ==
  /\ screen = "tonight"
  /\ pickerFrom = "none"
  /\ scope = "none"
  /\ backTo = "none"

OpenPullCard ==
  /\ screen = "tonight"
  /\ screen' = "encounter"
  /\ UNCHANGED <<pickerFrom, scope, backTo>>

OpenFailures ==
  /\ screen = "tonight"
  /\ screen' = "failures"
  /\ UNCHANGED <<pickerFrom, scope, backTo>>

BackToTonight ==
  /\ screen \in {"encounter", "failures", "question"}
  /\ screen' = "tonight"
  /\ UNCHANGED <<pickerFrom, scope, backTo>>

AskWhy ==
  /\ screen = "tonight"
  /\ screen' = "picker" /\ pickerFrom' = "tonight" /\ scope' = "night"
  /\ UNCHANGED backTo

AskAboutPull ==
  /\ screen = "encounter"
  /\ screen' = "picker" /\ pickerFrom' = "encounter" /\ scope' = "pull"
  /\ UNCHANGED backTo

AskAboutMechanic ==
  /\ screen = "failures"
  /\ screen' = "picker" /\ pickerFrom' = "failures" /\ scope' = "mechanic"
  /\ UNCHANGED backTo

AskFollowUp ==
  /\ screen = "question"
  /\ screen' = "picker" /\ pickerFrom' = "question"
  /\ UNCHANGED <<scope, backTo>>

Ask ==
  /\ screen = "picker"
  /\ screen' = "question"
  /\ UNCHANGED <<pickerFrom, scope, backTo>>

CancelPicker ==
  /\ screen = "picker"
  /\ screen' = pickerFrom
  /\ UNCHANGED <<pickerFrom, scope, backTo>>

OpenInspector ==
  /\ screen = "question"
  /\ screen' = "inspector"
  /\ UNCHANGED <<pickerFrom, scope, backTo>>

CloseInspector ==
  /\ screen = "inspector"
  /\ screen' = "question"
  /\ UNCHANGED <<pickerFrom, scope, backTo>>

JumpToRecap ==
  /\ screen = "question"
  /\ screen' = "recap_jump" /\ backTo' = "question"
  /\ UNCHANGED <<pickerFrom, scope>>

BackToAnswer ==
  /\ screen = "recap_jump"
  /\ screen' = backTo /\ backTo' = "none"
  /\ UNCHANGED <<pickerFrom, scope>>

OpenPanel ==
  /\ screen = "encounter"
  /\ screen' = "docked"
  /\ UNCHANGED <<pickerFrom, scope, backTo>>

ClosePanel ==
  /\ screen = "docked"
  /\ screen' = "encounter"
  /\ UNCHANGED <<pickerFrom, scope, backTo>>

OpenFullAnalysis ==
  /\ screen = "docked"
  /\ screen' = "question" /\ scope' = "pull"
  /\ UNCHANGED <<pickerFrom, backTo>>

Next ==
  \/ OpenPullCard \/ OpenFailures \/ BackToTonight \/ AskWhy \/ AskAboutPull
  \/ AskAboutMechanic \/ AskFollowUp \/ Ask \/ CancelPicker \/ OpenInspector
  \/ CloseInspector \/ JumpToRecap \/ BackToAnswer \/ OpenPanel \/ ClosePanel
  \/ OpenFullAnalysis

Spec == Init /\ [][Next]_vars

\* Rules the reader agrees to.
AlwaysOnAScreen == screen \in Screens
QuestionHasScope == screen = "question" => scope \in {"night", "pull", "mechanic"}
BackReturnsToAnswer == screen = "recap_jump" => backTo = "question"
CancelReturnsWhereOpened == screen = "picker" => pickerFrom \in {"tonight", "encounter", "failures", "question"}
====
