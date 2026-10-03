## Prompt

> Write an ADR for our decision to store plan-review verdicts inside the plan file instead of a separate report file.

This is a real decision made while designing this repository's `planning` skills: `plan-review` writes its verdict into `## Review` inside the same plan file `plan-writer` produces, rather than into a separate report file the way `ai-review` does.

## Without skill

An agent with no tech-writing skill produces something that reads like an ADR but is not decision-complete: no alternatives, no real cost admitted, a marketing tone, and no stable location or number.

```markdown
# ADR: Plan Review Storage Strategy

In today's fast-paced development environment, it's important to note that keeping
things simple is crucial. We are excited to announce that plan-review will write
its verdict directly into the plan file.

## Benefits

- Seamless integration between writing and reviewing
- Robust single source of truth
- Powerful and easy to follow

## Status

Accepted.
```

Saved as `ADR.md` at the repository root. It never names who reads this or why, has no Context or Consequences section, lists no alternative that was considered and rejected, admits no cost, and uses four of the banned phrases in three sentences.

## With skill

**Step 1.** Reader and next action: "The next contributor who wonders why `plan-review` writes into the plan file, to decide whether to keep that design or change it."

**Step 2.** Type: decision record, chosen because this is a "why" question, not a task or a lookup. Path: `docs/decisions/0001-review-verdicts-live-in-the-plan-file.md` — no `docs/decisions/` directory exists yet in this repository, so this is `0001`.

**Step 3.** Facts gathered from the repository: `.gitignore:5` lists `reports/`, so anything written there is local and never committed; `skills/review/ai-review/SKILL.md:36,47` shows the alternative already in use elsewhere — a stable per-target report file at `reports/ai-review-<id>.md`, written and updated on every run, never staged or committed. No commands to verify; this document cites paths, not commands.

**Step 4.** Outline: Context (why this needed deciding), Decision (what was chosen), Consequences (what it costs), Alternatives considered (the two rejected options), Status history.

**Step 5–6.** Written in simple English; none of the banned phrases from the skill's table appear.

**Step 7.** Full record:

````markdown
# 0001. Plan-review verdicts live in the plan file

- Status: accepted
- Date: 2026-09-26

## Context

`plan-writer` produces one plan file per change, and `plan-review` checks it before anyone builds from it. The review needs to store its verdict somewhere a later reader, and a later round of review, can find without extra lookup. This repository's `reports/` directory already holds a similar kind of working file — `ai-review` writes one report per pull request there — but that directory is listed in `.gitignore`, so nothing under it is ever committed with the branch.

## Decision

We will write the verdict into a `## Review` section inside the plan file itself, updated in place on every round, rather than into a separate file.

## Consequences

The plan and its review history travel together in one file, in one commit, in one diff — a teammate reading the plan sees the verdict without opening a second file. The cost is that `plan-review` now edits a file it did not create, so its guardrails restrict it to touching only the `## Review` section and two frontmatter keys, never the plan's other content. A plan with many review rounds also grows longer over time, since each round's body is appended rather than replaced.

## Alternatives considered

- A separate `reports/plan-review-<slug>.md` file, matching `ai-review`'s pattern — rejected because `reports/` is gitignored in this repository, so the verdict would never be committed with the plan it describes, and a plan that changes hands to a different session would lose its review history.
- Leaving the verdict only in the chat reply, with no file written — rejected because the developer who executes the plan is often a different session or a different person than the one who reviewed it, and a verdict that lives only in one chat transcript never reaches them.

## Status history

- 2026-09-26: proposed during the design of the `planning` skills
- 2026-09-26: accepted
````

**Step 11.** Reply:

```markdown
Written: `docs/decisions/0001-review-verdicts-live-in-the-plan-file.md` — decision record, for the next contributor to decide whether to keep or change this design.
- Facts verified: 0 commands run, 2 paths checked (`.gitignore:5`, `skills/review/ai-review/SKILL.md:36,47`), 0 links opened.
- Not verified: none.
- Words: 312. Sections: 5.
```
