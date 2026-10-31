--------------------------- MODULE RulesetFlow ---------------------------
EXTENDS Naturals, Sequences
CONSTANT LegacyDemotion
VARIABLES status, otherActive, phase, completed, failedAt, startedActive,
          activate, promote, rebuild
vars == <<status, otherActive, phase, completed, failedAt, startedActive,
          activate, promote, rebuild>>
opts == <<activate, promote, rebuild>>
Init == /\ status \in {"draft", "active", "archived"}
        /\ otherActive \in BOOLEAN
        /\ (status = "active" => ~otherActive)
        /\ startedActive = (status = "active")
        /\ activate \in BOOLEAN /\ promote \in BOOLEAN /\ rebuild \in BOOLEAN
        /\ (rebuild => (activate /\ promote))
        /\ phase = "sync" /\ completed = <<>> /\ failedAt = "none"
LegacyInit == Init /\ startedActive /\ ~activate /\ ~promote /\ ~rebuild
Sync == /\ phase = "sync"
        /\ phase' = IF activate THEN "activate" ELSE IF promote THEN "promote" ELSE "done"
        /\ completed' = Append(completed, "sync")
        /\ status' = IF LegacyDemotion THEN "draft" ELSE status
        /\ UNCHANGED <<otherActive, failedAt, startedActive, opts>>
Activate == /\ phase = "activate" /\ status' = "active" /\ otherActive' = FALSE
            /\ phase' = IF promote THEN "promote" ELSE "done"
            /\ completed' = Append(completed, "activate")
            /\ UNCHANGED <<failedAt, startedActive, opts>>
Promote == /\ phase = "promote" /\ phase' = IF rebuild THEN "rebuild" ELSE "done"
           /\ completed' = Append(completed, "promote")
           /\ UNCHANGED <<status, otherActive, failedAt, startedActive, opts>>
Rebuild == /\ phase = "rebuild" /\ phase' = "done"
           /\ completed' = Append(completed, "rebuild")
           /\ UNCHANGED <<status, otherActive, failedAt, startedActive, opts>>
Fail == /\ phase \in {"sync", "activate", "promote", "rebuild"}
        /\ failedAt' = phase /\ phase' = "failed"
        /\ UNCHANGED <<status, otherActive, completed, startedActive, opts>>
Done == /\ phase \in {"done", "failed"} /\ UNCHANGED vars
Next == Sync \/ Activate \/ Promote \/ Rebuild \/ Fail \/ Done
Spec == Init /\ [][Next]_vars
AtMostOneActive == ~(status = "active" /\ otherActive)
SyncNeverDemotes == startedActive => status = "active"
RebuildAfterPromotion == phase = "rebuild" =>
    ("promote" \in {completed[i] : i \in DOMAIN completed} /\ status = "active")
FailureIsExplicit == (phase = "failed") = (failedAt # "none")
Expected == <<"sync">> \o (IF activate THEN <<"activate">> ELSE <<>>) \o
            (IF promote THEN <<"promote">> ELSE <<>>) \o
            (IF rebuild THEN <<"rebuild">> ELSE <<>>)
CompletedPrefix == completed = SubSeq(Expected, 1, Len(completed))
=============================================================================
