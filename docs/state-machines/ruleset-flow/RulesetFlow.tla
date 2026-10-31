--------------------------- MODULE RulesetFlow ---------------------------
EXTENDS Naturals, Sequences, FiniteSets
VARIABLES phase, completed, failedAt, rebuild, activeRows, dimRows, factRows
vars == <<phase, completed, failedAt, rebuild, activeRows, dimRows, factRows>>
Catalog == {"kept"}
Original == {"kept", "retired"}
Init == /\ phase = "sync" /\ completed = <<>> /\ failedAt = "none"
        /\ rebuild \in BOOLEAN
        /\ activeRows = Original /\ dimRows = Original /\ factRows = Original
Sync == /\ phase = "sync"
        /\ phase' = IF rebuild THEN "rebuild" ELSE "done"
        /\ completed' = Append(completed, "sync")
        /\ activeRows' = Catalog
        /\ UNCHANGED <<failedAt, rebuild, dimRows, factRows>>
Rebuild == /\ phase = "rebuild" /\ phase' = "done"
           /\ completed' = Append(completed, "rebuild")
           /\ factRows' = Catalog
           /\ UNCHANGED <<failedAt, rebuild, activeRows, dimRows>>
Fail == /\ phase \in {"sync", "rebuild"}
        /\ failedAt' = phase /\ phase' = "failed"
        /\ UNCHANGED <<completed, rebuild, activeRows, dimRows, factRows>>
Done == /\ phase \in {"done", "failed"} /\ UNCHANGED vars
Next == Sync \/ Rebuild \/ Fail \/ Done
Spec == Init /\ [][Next]_vars
Expected == <<"sync">> \o (IF rebuild THEN <<"rebuild">> ELSE <<>>)
CompletedPrefix == completed = SubSeq(Expected, 1, Len(completed))
FailureIsExplicit == (phase = "failed") = (failedAt # "none")
RebuildAfterSync == phase = "rebuild" => completed = <<"sync">>
DoneMeansRequestedWorkComplete == phase = "done" => completed = Expected
SyncRetires == Len(completed) > 0 => activeRows = Catalog
KeysStayAttached == dimRows = Original /\ factRows \subseteq dimRows
SyncKeepsFacts == Len(completed) < 2 => factRows = Original
=============================================================================
