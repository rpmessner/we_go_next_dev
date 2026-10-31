# Watch

TLC reached 52 states and 331 steps. The chart draws 7 states and 24 arrows.
The chart does not draw 104 steps that stay in one chart state.
The view hides 52 steps, so the chart does not draw them.

## Agreement breaks
The shortest path has 4 steps:
0. idle
1. view or import newest log: tracking
2. appended data or pending replay: syncing
3. view or import newest log: tracking
4. stale reply overwrites selected log: tracking

## NeverRevert breaks
The shortest path has 4 steps:
0. idle
1. view or import newest log: tracking
2. appended data or pending replay: syncing
3. view or import newest log: tracking
4. stale reply overwrites selected log: tracking

## Rules that hold
Restored, AutoOff, NoDeadlock
