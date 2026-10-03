# Handback and resume

Read this file before launching a child or handling one's return. It defines
the one handback shape every step of the Workflow uses, and how a stopped or
interrupted loop picks back up without repeating a fresh child's work.

## The handback

A handback is a structured refusal to fake progress. It has six fields:

- `kind` — what stopped the loop: `"question"` (an owner decision only a
  human can make), `"consent"` (the five-round boundary), `"unavailable"` (a
  tool, dependency, or piece of evidence this session cannot reach),
  `"depth"` (this session cannot launch the next child itself), or
  `"blocked"` (an identical checkpoint with no new evidence, per Workflow
  step 8).
- `planPath` — the plan this concerns, so the recipient does not have to
  guess or re-resolve it.
- `nextRole` — who should act next: `"writer"`, `"reviewer"`, or `"owner"`.
- `inputs` — what that next actor needs: an open question's exact text, the
  missing tool or evidence, the round count at the consent boundary, or the
  repeated blocker.
- `reason` — one sentence naming why this session cannot do it itself.
- `nextAction` — the smallest concrete step that unblocks this: launch a
  fresh writer with the fix-only step for round `<n>`, launch a fresh
  reviewer for round `<n+1>`, ask the owner the named question, or renew
  consent for up to five more rounds.

A handback is not a failure report about the plan; it is an honest statement
that this session's own authority or reach ends here. Whatever invoked this
loop — the user's own session, or a further parent orchestrator — decides
what happens next: relay the question, supply the missing input, grant
consent, or launch the named next child itself.

## Depth and nested spawn

A host may cap how many levels of child a session may launch. When this
loop's own session is already a child and cannot launch the writer or
reviewer child a step requires, that is a `kind: "depth"` handback with
`nextRole` naming which child is needed next; do not attempt the role
yourself in that session. When a *launched* writer or reviewer child itself
tries to spawn a further child and the host blocks it, that child returns its
own handback; relay it upward with `planPath` and `nextRole` intact rather
than reinterpreting or absorbing it.

## Resume

This loop keeps no state outside the plan file itself: `status`,
`review_round`, and the full `## Review` history already record where a plan
stands. A loop resumed after a handback, a host restart, or a fresh session
re-reads the plan and continues from exactly that recorded state — it does
not need to know how many rounds ran before, only what the file currently
says. Re-derive the round count and the five-round consent boundary from the
plan's own history table on every resume; do not trust a count remembered
from an earlier session that might be stale.

## What a payload never contains

A reviewer child's task payload is the plan path, the project root, and the
instruction to run one review round — nothing else. It never contains: this
loop's own history of prior rounds, a fixer's account of what it changed or
why, a summary of what verdict would be convenient, or any framing that
implies the plan is expected to pass. The reviewer's independence depends on
reading the plan and its recorded rounds fresh, on its own authority, not on
being told what happened before.
