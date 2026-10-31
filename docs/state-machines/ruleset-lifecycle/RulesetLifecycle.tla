-------------------------- MODULE RulesetLifecycle --------------------------
EXTENDS Naturals, FiniteSets
VARIABLES statuses, everActive, leftDraft
vars == <<statuses, everActive, leftDraft>>
Ids == {1, 2}
Active == {id \in Ids : statuses[id] = "active"}
Init == /\ statuses \in [Ids -> {"draft", "active", "archived"}]
        /\ Cardinality(Active) <= 1
        /\ everActive = (Active # {})
        /\ leftDraft = {id \in Ids : statuses[id] # "draft"}
Activate == \E id \in Ids :
    /\ statuses' = [i \in Ids |-> IF i = id THEN "active"
                       ELSE IF statuses[i] = "active" THEN "archived" ELSE statuses[i]]
    /\ everActive' = TRUE
    /\ leftDraft' = leftDraft \cup {id} \cup Active
ArchiveDraft == \E id \in Ids :
    /\ statuses[id] = "draft"
    /\ statuses' = [statuses EXCEPT ![id] = "archived"]
    /\ leftDraft' = leftDraft \cup {id}
    /\ UNCHANGED everActive
Sync == UNCHANGED vars
RejectResetOrActiveArchive == UNCHANGED vars
Next == Activate \/ ArchiveDraft \/ Sync \/ RejectResetOrActiveArchive
Spec == Init /\ [][Next]_vars
AtMostOneActive == Cardinality(Active) <= 1
NeverLoseActive == everActive => Active # {}
NoResetToDraft == \A id \in leftDraft : statuses[id] # "draft"
TypeOK == statuses \in [Ids -> {"draft", "active", "archived"}]
=============================================================================
