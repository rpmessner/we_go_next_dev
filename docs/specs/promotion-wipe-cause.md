# Promotion 1: the promote-analysis skill, proven on the wipe-cause fact

Status: approved by the operator (foreman, 2026-10-30): first 3 deaths, 30 s wipe cutoff. Ticket we-sfg.1 under the Promotion epic we-sfg. Vocabulary: `GLOSSARY.md` (Promotion, Tool, Analysis session).

## Goal

Turn the method the AI used to answer "why did this pull wipe?" into deterministic, verified gold code, and capture the steps as a project-local `promote-analysis` skill so later promotions follow the same path.

## Why

The operator wants analysis the AI does well to become part of the warehouse, so later sessions get it instantly and for free, and the break page can show it between pulls. The wipe cause is the right first case:
- It is the AI's own method in corpus Q1 and Q4: order the deaths, take the first ones, and read their killing blows.
- The failure taxonomy ranks it first to build.
- It needs no new silver data.
- It has operator-verified reference answers and a Warcraft Logs report to check against.

## Non-goals

- Other promotions: damage done (we-5v4), soaks and tank swaps (we-1xz).
- The phase 2 question picker UI and the break page itself. This ticket delivers what they will call.
- Changing silver, the parser, or existing fact semantics.
- Calling the Anthropic API from the app.

## Decisions

1. **Which deaths decide a wipe** (operator, approved). Proposed rules:
   - Take the first 3 player deaths in a wiped pull that happen before the wipe cutoff, ordered by time.
   - The wipe cutoff is 30 s before the pull ends, matching Warcraft Logs' Death Statistics.
   - Feign Death is already excluded in silver (we-6l9).
   - A kill has no wipe cause.
   - Pulls under 10 s (resets) are skipped, as in the pull pipeline model.
2. **Gold output** (agent call): a new fact table `gold.fact_wipe_cause`, one row per deciding death. Columns:
   - pull (`encounter_dim_id`), rank (1–3), player, death time;
   - killing blow spell and its source;
   - the catalogued mechanic and its type when the spell is in the rules catalog, plus whether that mechanic is avoidable (unknown when uncatalogued);
   - a derivation stamp.

   The table is rebuilt with the other gold facts, and the stamp is bumped whenever the definition changes.
3. **Deterministic Tool** (agent call): `wipe_cause(pulls)` reads the gold rows and returns the standard envelope with evidence, like `failures`. A built-in question, "Why did this pull wipe?", is bound to it, so the question takes the question lifecycle's no-model path (operator decision: built-ins with a deterministic Tool answer instantly). Across pulls, the Tool also returns the most common deciding killing blow. That feeds the break page's "repeating tonight".
4. **Verification** (agent call; each check is a test or script in the repo, and each must be shown failing on a deliberately broken variant before it counts):
   - *Reference set:* on Sszorak pull 5, the first deciding death is Kahnu at 155.271 s to Mutilate, matching reference answers Q1 and Q4 (revision 2). Every wiped Sept 6 pull's deciding deaths agree with the reference evidence JSON.
   - *Warcraft Logs:* the deciding deaths on all 16 shared pulls match WCL report `aW7mTPNrXwLcM2DR` death order and killing blows, read through the v1 API. Where WCL names no killing blow, that's recorded, not counted as a mismatch.
   - *AI agreement:* the baseline answers the judge graded correct, plus the operator's overrides for Q1 and Q4, agree with the fact's first death and killing blow. The single live verdict was "wrong" and is used as a must-not-repeat case: the fact never names Mädz's Feign Death.
   - *Cost:* rerun the baseline's Q1 and Q4 with the built-in available, and record calls and cost before and after.
5. **The skill** (agent call): `.agents/skills/promote-analysis/SKILL.md`, symlinked from `.claude/skills/`, written with the writing-for-agents skill. Its steps:
   1. Find a repeated, operator-confirmed method in recorded sessions (export plus retro).
   2. Write it down as rules, a gold output and a stamp.
   3. Implement it.
   4. Run the four verification checks.
   5. Bind the built-in question.
   6. Record cost before and after.

   It is proven by being followed once, for this promotion.

## Acceptance checks

1. After a rebuild on dev, `gold.fact_wipe_cause` holds deciding deaths for every wiped Sept 6 pull; Sszorak pull 5's rank 1 is Kahnu, 155.271 s, Mutilate.
2. The WCL comparison script reports a match on all 16 shared pulls, or lists each mismatch with its reason.
3. Each verification check fails on a deliberately broken variant (for example, the cutoff removed, or the order reversed), and passes on the real code.
4. Over MCP, the `wipe_cause` Tool answers the built-in question for Sszorak pull 5 without the model, with evidence citing pull and time.
5. Baseline Q1 and Q4 rerun: cost and call counts before and after are recorded in the reference-set index.
6. The `promote-analysis` skill exists, is registered, and its steps match what was done here.
7. Gates: `mix test`, `mix credo`, `mix format`, zero warnings.

## Ask-first boundaries

- Changing silver, the parser, or other facts' semantics.
- A different cutoff or rank count than the operator approves.
- Any paid run beyond baseline Q1 and Q4 (about $5).

## Left to the builder

- Module names, the exact columns beyond those named above, and how the WCL script caches responses.
