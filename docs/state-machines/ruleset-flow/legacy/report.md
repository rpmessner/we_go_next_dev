# RulesetFlow

TLC reached 3 states and 4 steps. The chart draws 3 states and 2 arrows.
The chart does not draw 2 steps that stay in one chart state.

## SyncNeverDemotes breaks
The shortest path has 1 step:
0. sync: active (started active)
1. re-seed defaults status to draft: done: draft (started active)

## Rules that hold
AtMostOneActive, RebuildAfterPromotion, FailureIsExplicit, CompletedPrefix, NoDeadlock
