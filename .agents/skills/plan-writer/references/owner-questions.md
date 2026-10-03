# Owner questions

Read this file after the deep analysis. The early sharpening round is separate: at most three questions, one message, only when a fresh chat request is idea-level vague, and only before exploration. This file is the later round. It is not a second idea-refinement.

## What to ask

One message. Product questions first, then technical questions. Skip anything the request, the early round, the code, or the research already settled. This round does not use the "only irreversible" filter.

Cap: at most four product questions and four technical questions. Ask fewer when fewer are open. Each question includes why it is asked and the default if it goes unanswered.

Product:

- Who it is for, and what job they are doing.
- What success looks like for them.
- What is out of scope.
- Which user-facing tradeoff from the research they want.

Technical:

- Which approach or library to follow.
- Data and compatibility.
- Failure behavior.
- Where it lives in this codebase.

A question that names a library, a file, or a storage choice is technical, even when users will notice it.

Only the owner can answer a question. A file you have not read, a search you have not run, or a contract you have not checked is your work, not a question. Keep it on the investigation frontier.

## What to record

`## Questions` always has `### Product` before `### Technical`. Neither group is empty. Each item is an answer or a recorded default. When a group had nothing to ask, list the decisions already settled in that group.

An early-round answer is written once, in the group it belongs to. The later round does not ask it again and does not list it twice.

## When to stop

Do not stop before the draft file exists. In an interactive session, stop after that draft is written when at least one later-round question is still open, or when the tier is `architecture`. Do not stop when both groups contain only settled decisions and the tier is `standard`.

In a non-interactive run, record each default and continue, including when the tier is `architecture`. A session that was told to ask and wait is interactive: write the draft, reply with the draft-gate block, and stop. Do not record a default and continue. A child session that another agent launched returns its open questions to that parent in the reply.

The draft at this gate holds the TL;DR, Scope (including the IS/GAP ledger, the risks, and the Evidence index with its frontier), `## Research`, and `## Questions`. The other headings are present and empty.

## Resume

Read the draft from disk. Take answers from the conversation since the draft was written, or from edits already in `## Questions`. Write them in. Do not re-ask. Before planning tasks, work any open investigation frontier and recheck changed sources; an answered question does not close unread code.
