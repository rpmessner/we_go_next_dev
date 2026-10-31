---------------------------- MODULE FileIngest ----------------------------
EXTENDS Naturals, TLC
VARIABLES phase, offset, previous, writers, pull, age, replay
vars == <<phase, offset, previous, writers, pull, age, replay>>
Busy == phase \in {"importing", "syncing", "reimporting"}
Init == /\ phase = "idle" /\ offset = 0 /\ previous = 0
        /\ writers = 0 /\ pull = "pending" /\ age = 0 /\ replay = 3
Start == /\ ~Busy
         /\ phase' \in {"importing", "syncing", "reimporting"}
         /\ writers' = 1 /\ age' = 0
         /\ pull' = IF phase' = "reimporting" THEN "pending" ELSE pull
         /\ replay' = IF phase' = "reimporting" THEN 0 ELSE replay
         /\ UNCHANGED <<offset, previous>>
Parse == /\ Busy /\ offset < 2 /\ (replay = 3 \/ replay = offset)
         /\ previous' = offset /\ offset' = offset + 1
         /\ replay' = IF replay = 3 THEN 3 ELSE offset + 1
         /\ pull' = "pending"
         /\ UNCHANGED <<phase, writers, age>>
Replay == /\ Busy /\ replay # 3 /\ replay < offset
          /\ replay' = replay + 1 /\ pull' = "pending"
          /\ UNCHANGED <<phase, offset, previous, writers, age>>
Project == /\ Busy /\ pull \in {"pending", "failed"}
           /\ pull' \in {"done", "failed"}
           /\ UNCHANGED <<phase, offset, previous, writers, age, replay>>
Finish == /\ Busy /\ pull = "done" /\ (replay = 3 \/ replay = offset)
          /\ phase' = "idle" /\ writers' = 0 /\ replay' = 3
          /\ UNCHANGED <<offset, previous, pull, age>>
Fail == /\ Busy /\ phase' = "failed" /\ writers' = 0
        /\ UNCHANGED <<offset, previous, pull, age, replay>>
Tick == /\ Busy /\ age < 2 /\ age' = age + 1
        /\ UNCHANGED <<phase, offset, previous, writers, pull, replay>>
Timeout == /\ Busy /\ age = 2 /\ phase' = "failed" /\ writers' = 0
           /\ UNCHANGED <<offset, previous, pull, age, replay>>
Rest == /\ ~Busy /\ UNCHANGED vars
Next == Start \/ Parse \/ Replay \/ Project \/ Finish \/ Fail \/ Tick \/ Timeout \/ Rest
ProgressMonotonic == offset >= previous
SingleWriter == writers \in {0, 1} /\ (Busy <=> writers = 1)
NoSkippedPull == phase = "idle" => pull # "failed"
ReplayBounded == replay = 3 \/ replay <= offset
ProgressNeverDecreases == [][offset' >= offset]_vars
ReplaySurvivesFailure == [][(Busy /\ phase' = "failed") => replay' = replay]_vars
TerminalOrTimeout == Busy ~> ~Busy
Spec == Init /\ [][Next]_vars /\ WF_vars(Tick) /\ WF_vars(Timeout)
=============================================================================
