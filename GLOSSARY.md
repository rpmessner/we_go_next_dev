# we_go_next

A raid and Mythic+ diagnostic tool over WoW combat logs: a medallion warehouse of deterministic analysis, with an LLM analysis layer on top that explores what the warehouse does not yet answer.

## AI analysis layer

**Analysis session**:
One conversation between the operator and the LLM agent about the logs on file, recorded in full so it can be reviewed later.
_Avoid_: chat, thread, conversation

**Tool**:
A named, parameterized, tested operation over bronze, silver or gold that the agent can call during an analysis session.
_Avoid_: function, command, query

**Playbook**:
A stored, versioned set of agent instructions for a kind of question, optionally scoped to a boss or encounter.
_Avoid_: skill, prompt, recipe

**Auto-run**:
A Tool the app calls on its own when the active log state changes, handing the result to the session up front.
_Avoid_: trigger, hook, background analysis

**Promotion**:
Turning an operation the agent keeps repeating across analysis sessions into a Tool, a Playbook, an Auto-run, or eventually a deterministic medallion output, so later sessions get it cheaper and more reliably.
_Avoid_: graduation, codification

**Retro**:
A review of recorded analysis sessions that finds repeated or expensive operations and proposes promotions.
_Avoid_: postmortem, audit
