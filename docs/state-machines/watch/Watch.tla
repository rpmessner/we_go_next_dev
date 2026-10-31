----------------------------- MODULE Watch -----------------------------
EXTENDS Naturals
CONSTANT UnsafeReply
VARIABLES phase, tracked, durable, pending, quiet, highwater
vars == <<phase, tracked, durable, pending, quiet, highwater>>
Init == /\ phase = "idle" /\ tracked = 0 /\ durable = 0
        /\ pending = 0 /\ quiet = 0 /\ highwater = 0
Select == /\ tracked < 2 /\ phase # "rotating"
          /\ tracked' = tracked + 1 /\ durable' = tracked'
          /\ highwater' = tracked' /\ phase' = "tracking" /\ quiet' = 0
          /\ UNCHANGED pending
Directory == /\ phase = "idle" /\ phase' = "directory"
             /\ UNCHANGED <<tracked, durable, pending, quiet, highwater>>
Sync == /\ phase = "tracking" /\ pending = 0
        /\ phase' = "syncing" /\ pending' = tracked
        /\ UNCHANGED <<tracked, durable, quiet, highwater>>
Rotate == /\ phase \in {"tracking", "directory"} /\ pending = 0 /\ tracked < 2
          /\ phase' = "rotating" /\ pending' = tracked + 1
          /\ UNCHANGED <<tracked, durable, quiet, highwater>>
Return == /\ pending # 0
          /\ IF phase = "rotating"
                THEN /\ tracked' = pending /\ durable' = pending
                     /\ highwater' = tracked' /\ phase' = "tracking"
                ELSE /\ IF UnsafeReply /\ phase = "tracking"
                             THEN tracked' = pending
                             ELSE UNCHANGED tracked
                     /\ UNCHANGED <<durable, highwater>>
                     /\ phase' = IF phase = "syncing" THEN "tracking" ELSE phase
          /\ pending' = 0 /\ UNCHANGED quiet
Fail == /\ phase \in {"syncing", "rotating"} /\ phase' = "backoff"
        /\ pending' = 0 /\ UNCHANGED <<tracked, durable, quiet, highwater>>
Retry == /\ phase = "backoff" /\ phase' = IF tracked = 0 THEN "directory" ELSE "tracking"
         /\ UNCHANGED <<tracked, durable, pending, quiet, highwater>>
Write == /\ tracked # 0 /\ quiet' = 0
         /\ UNCHANGED <<phase, tracked, durable, pending, highwater>>
Tick == /\ phase \notin {"idle", "idle_off"} /\ quiet < 2
        /\ quiet' = quiet + 1
        /\ IF quiet' = 2 THEN /\ phase' = "idle_off" /\ tracked' = 0 /\ durable' = 0
                             /\ highwater' = 0
           ELSE UNCHANGED <<phase, tracked, durable, highwater>>
        /\ UNCHANGED pending
Stop == /\ phase' = "idle_off" /\ tracked' = 0 /\ durable' = 0 /\ highwater' = 0
        /\ UNCHANGED <<pending, quiet>>
Restart == /\ phase' = IF durable = 0 THEN "idle" ELSE "tracking"
           /\ tracked' = durable /\ pending' = 0 /\ quiet' = 0
           /\ UNCHANGED <<durable, highwater>>
Done == UNCHANGED vars
Next == Select \/ Directory \/ Sync \/ Rotate \/ Return \/ Fail \/ Retry \/ Write \/ Tick \/ Stop \/ Restart \/ Done
Spec == Init /\ [][Next]_vars
Agreement == tracked = durable
NeverRevert == tracked = 0 \/ tracked >= highwater
Restored == durable = 0 \/ phase \notin {"idle", "idle_off", "directory"}
AutoOff == quiet = 2 => durable = 0
=============================================================================
