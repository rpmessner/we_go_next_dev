------------------------------ MODULE Spec ------------------------------
EXTENDS Naturals
CONSTANT ReservePartial
VARIABLES phase, facts, document, stamp
vars == <<phase, facts, document, stamp>>

Init == /\ phase = "idle" /\ facts = 0 /\ document = 0 /\ stamp = "current"
Begin == /\ phase = "idle" /\ phase' = "building"
         /\ stamp' = IF ReservePartial THEN "partial" ELSE stamp
         /\ UNCHANGED <<facts, document>>
Build == /\ phase = "building" /\ phase' = "built"
         /\ facts' = IF ReservePartial THEN facts ELSE 1
         /\ UNCHANGED <<document, stamp>>
Write == /\ phase = "built" /\ phase' = "written"
         /\ document' = 1 /\ UNCHANGED <<facts, stamp>>
Commit == /\ phase = "written" /\ phase' = "done"
          /\ facts' = 1 /\ stamp' = "current" /\ UNCHANGED document
Fail == /\ phase \in {"building", "built", "written"}
        /\ phase' = "failed" /\ UNCHANGED <<facts, document, stamp>>
Done == /\ phase \in {"done", "failed"} /\ UNCHANGED vars
Next == Begin \/ Build \/ Write \/ Commit \/ Fail \/ Done

TypeOK == /\ phase \in {"idle", "building", "built", "written", "done", "failed"}
          /\ facts \in {0, 1} /\ document \in {0, 1}
          /\ stamp \in {"current", "partial"}
CurrentMeansConsistent == stamp = "current" => facts = document
FailureIsVisible == phase = "failed" /\ facts # document => stamp = "partial"
=============================================================================
