# Spec

TLC reached 8 states and 11 steps. The chart draws 8 states and 7 arrows.
The chart does not draw 4 steps that stay in one chart state.

## CurrentMeansConsistent breaks
The shortest path has 2 steps:
0. idle: facts 0, document 0, current
1. start rebuild: building: facts 0, document 0, current
2. build facts: built: facts 1, document 0, current

## FailureIsVisible breaks
The shortest path has 3 steps:
0. idle: facts 0, document 0, current
1. start rebuild: building: facts 0, document 0, current
2. build facts: built: facts 1, document 0, current
3. write fails or process stops: failed: facts 1, document 0, current

## Rules that hold
TypeOK, NoDeadlock
