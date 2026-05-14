# WeGoNext — Product Vision

*Captured 2026-04-09 after data loss and rebuild. This replaces assumptions from the original build.*

## What Is This

A WoW combat log analysis tool that runs alongside the game on a second monitor. Parses combat logs in near-real-time (logs flush to disk after each encounter ends) and provides actionable analysis between pulls.

## Priority Stack

1. **My play, this pull** — What did I do wrong? What killed me? Where did my rotation break down? Uptime gaps not caused by phase changes?
2. **My play, over time** — Am I improving pull-over-pull? Am I dying to the same things? Trend tracking across attempts.
3. **Raid-wide diagnosis** — What killed us? Who failed mechanics? Who needs to improve?
4. **Sharing** — Give analysis to raid leads, let players see their own data via hosted site or in-game addon link.

The original build jumped straight to #3 and skipped #1 and #2.

## The Gap This Fills

WoW's built-in damage meter (new in War Within) covers basics: DPS by ability, damage taken, interrupts, deaths. But it's all aggregate. It does NOT show:

- **Per-target DPS** — are we DPSing adds at the right time, or tunneling the boss?
- **Per-phase / time-window breakdowns** — what was my DPS during the burn window?
- **Contextual "why" questions** — who was hitting the boss when they should've been on adds?
- **Rotation analysis** — uptime, downtime not from phase changes, cooldown usage
- **Pull-over-pull trends** — am I improving or dying to the same thing every attempt?

The old third-party addons (Details!, Skada) could do some of this but the built-in meter simplified it away.

**WeGoNext = the analysis layer that answers "why" questions, not another damage meter.**

## Two Content Modes

### After a Wipe (Diagnostic)
Focus on what went wrong:
- Deaths — what killed us, who died to what
- Mechanic failures — who stood in fire, who missed interrupts
- What to fix for the next pull
- "What did *I* do wrong" front and center

### After a Kill (Evaluative)
Focus on how we did:
- Performance breakdown, personal bests
- Comparison to previous wipe pulls on the same boss
- Celebratory but useful — who crushed it, what improved

### Before First Pull / During Pull
- Boss info, historical data from previous sessions
- Last wipe/kill summary if available

## M+ Is First-Class

Not secondary to raids. Especially valuable for failed keys — understanding what went wrong across an entire dungeon run.

Key differences from raid analysis:
- Multiple encounters/pulls in a single session, not repeated attempts on one boss
- Death cost is concrete (time penalty) — knowing which deaths cost the key
- Interrupt coverage is life or death (kick rotations)
- Avoidable damage across the whole run
- Dungeon run = aggregate view; individual pulls/bosses = drill-down

## Who Uses This

### Now
Solo tool — the developer (Mittwoch, Warlock, Hand of Algalon on Wyrmrest Accord) dogfooding during raids and pugs. Not a raid leader, but wants to improve own play and offer analysis to the raid team.

### Soon
Guild sharing — Hand of Algalon has multiple raid teams that would use it if it proves valuable.

### Later
- Hosted version with role-based access (raid leads see everything, players see own data)
- In-game addon that links players to their private analysis on the web

## Physical Setup

- WoW fullscreen on primary monitor
- Browser on second monitor (~1920px) pointing at localhost (WSL2 running Elixir server)
- Quick glanceability matters — glancing between pulls, not studying complex dashboards

## Development Philosophy

Build incrementally from felt needs during actual gameplay. Don't design features up-front from imagination. The tool should grow from "I wish I could see X right now" moments during raids and M+.
