# Analysis session screen: design brief

Status: draft for operator review (2026-10-30). Resolves the design half of wayfinder ticket we-c5q.12, "What does the Analysis session screen look like and how does it behave?". The prototype half comes after this brief is reviewed: its variants test the open questions at the end, not layouts invented from nothing. Vocabulary: `GLOSSARY.md`.

## Evidence from phase 1

The sources are 13 recorded Analysis sessions on the Sept 6 log: the operator's live Q1 session and the 12 baseline questions run headlessly on Opus 5.5. They are the rows in `analysis.sessions`, `analysis.tool_calls` and `analysis.verdicts`, the live transcript, and the graded baseline in `reference-set/baselines/2026-10-29-opus55/`.

- **An answer takes minutes, not seconds.** Wall time per question ranged from 24 s to 10 min, with a median of about 2.3 min. The live Q1 answer took 76 s. Tool time is a small share of that (0.5–47 s per session); the rest is the model thinking and writing.
- **An answer is a long chain of Tool calls.** Each question took 16–134 Tool calls, with a median of about 49. 60% of all calls returned a truncated page (419 of 703), and 353 were cursor follow-ups. `deaths` alone made 179 calls, 163 of them fetching the next page.
- **Cost varies widely.** Baseline answers cost $0.49–6.77 each. Q3 and Q6 cost more than the $5/session cap that phase 2 will enforce.
- **Checking the evidence was the operator's main act.** In the one live session, the answer was well cited and still wrong: the Feign Death case. The correction came from checking evidence, not from the answer's prose. The baseline's 8 "partly" grades are nearly all about what the agent did not look at: deaths skipped, pulls not covered, reference elements omitted.
- **Errors were rare.** There was 1 Tool error in 703 calls, and the agent carried on after it.

## Contexts of use

| Context | Time available | What the operator wants | Can a session serve it? |
|---|---|---|---|
| Between pulls (runback) | 30–90 s | What killed us, and the one thing to change | Not by asking. A fresh answer takes about 2 min. This needs Auto-runs that are ready when the pull ends (fog on the map), or deterministic views that already exist (Death Recap, Failures). |
| Raid break, or right after a kill or a wipe streak | 5–15 min | Why we keep wiping, and what changed on the kill | Yes. One or two questions, watched while they run. |
| After the raid | Unbounded | Coaching notes, cross-pull trends, checking answers, verdicts | Yes. This is the main use: several questions, digging into evidence, recording verdicts. |
| Retro | Unbounded | Which operations repeat, and what to promote | Partly. It needs session history and export. The phase 1 retro runs outside the app. |

Recommendation: design the screen for the raid break and after the raid. Say plainly, in the product, that between-pull help comes from the existing views and later Auto-runs. Asking during runback leads to an answer that arrives after the next pull starts.

## Primary task and hierarchy

The primary task is to ask a question about this log, get a cited answer, decide whether to trust it, and record the verdict.

The order of importance follows from the evidence:

1. **The answer**, with its citations inline.
2. **The evidence behind a citation.** One click from the claim to the rows behind it: pull, time, Tool, and the raw event with its byte offset where there is one. This is the step that caught the Feign Death error.
3. **What the agent checked, and what it didn't.** Coverage, not a raw call log: "deaths on pulls 436–444, log_events for Mädz on 440 (casts, 0:10–0:20)". Group the trail by Tool and pull, and show page counts instead of about 49 rows (Miller's law: chunk 16–134 calls into a handful of meaningful groups). Show the raw call list on demand.
4. **Progress and spend while it runs:** elapsed time, the current step, spend against the $5 cap, requests against 40.
5. **Verdict controls** next to the answer they judge.
6. **Session history and export.**

## UX laws that shape this

- **Doherty threshold.** Answers take minutes, so streaming text is not enough. The screen must show progress: which step it is on, how long it has run, and the current spend. It must also offer cancel.
- **Tesler's law.** The paging complexity (cursors, truncated pages) belongs to the system. The operator should never see "next_cursor". The trail shows "deaths, 9 pages".
- **Zeigarnik effect.** A session that hit the cap or was cancelled is unfinished work. It must say what remains and offer to resume or continue under a new cap, with its state kept.
- **Jakob's law.** The operator already knows Claude-style chat: conversation in the middle, a collapsed "used N tools" line, and side panels for supporting material. The raid-tool conventions come from Warcraft Logs and this app: a report, a fight picker, then tabs. Prefer those conventions to an invented layout.

## Information architecture

Today's navigation has four entries: Encounters (`/`), Logs, Failures and Settings. Encounter detail sits under a log's encounter.

A session belongs to a log, not to an encounter. A third of the corpus questions span pulls (Q2, Q3, Q10, Q11), and `session_context` is scoped to a log.

Recommendation:
- **One home for sessions:** a top-level "Analysis" entry. It holds the active log's sessions, a new session, and history.
- **Entry points from the existing pages:** "Ask about this pull" on encounter detail, and "Ask about this mechanic" on Failures. Each opens a session pre-scoped to that pull or mechanic.
- **Citations that point into the existing app:** a cited pull and time opens the encounter page's Death Recap at that row. The session screen should not grow its own copy of those views.

## Phase 1 findings to file regardless of the design

- The `deaths` Tool pages one recap hit per page. That caused 163 follow-up calls across 13 sessions, and it is the biggest single driver of call counts. It is a Tool-contract candidate for the first retro.
- `session_context` had 45 cursor follow-ups, probably from paginated stale-pull lists. Worth checking.

## Operator decisions (foreman, 2026-10-30)

1. **Context:** design mainly for the raid break and after the raid. The operator still wants help between pulls, for course correction ("if you're doing something wrong or making a repeated mechanic mistake, it'd be good to know"). It doesn't have to be tied to one pull: a **break page that builds up as each encounter finishes**. That pulls the Auto-run fog into scope for design. The page is filled by Tools the app runs on its own at `ENCOUNTER_END` (the log flushes then), not by questions asked during runback. Real example from Sept 6: Eternal Venom was the top killing blow on all 7 Twin Fangs wipes (5–10 deaths each).
2. **Placement:** test both, the log-level Analysis page and the panel docked on encounter detail.
3. **Evidence:** test both, the side inspector and the jump into existing views. Also, "the main chat [should] have a link to the full analysis page": a compact panel and a full page coexist, linked.
4. **Trail and history:** "I don't really want my main interface to keep scrolling and have to go searching through old stuff, it should be a more hierarchical interface." This rules out a chat transcript as the main structure. Questions and answers are organised by night, then encounter, then pull. One answer is shown at a time, with its evidence and coverage beneath it. History is navigated through that tree, not by scrolling.

Mockups: the private canvas "Analysis session screen options" (claude.ai/artifact/5HbrEmQKhXMxWmFyFZ9Uq7). Rows 1–3 show the first options. Row 4 adds the hierarchical page and the build-up break page from these decisions.
