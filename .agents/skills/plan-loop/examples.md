## Prompt

> Write and review docs/plans/2026-09-28-greeter-shout.md until it passes. This is one loop invocation; follow the plan-loop skill exactly.

The plan already existed at `status: planned`, `review_round: 0`, with one
deliberate defect: T2's Acceptance required `python3 cli.py --shout Ana` to
print `Ana, HELLO!`, which contradicts the TL;DR, the Ideal state, MH2, and
the plan's own G2 proof — all of which require `HELLO, ANA!`. This is an
excerpt from a real run, not a hypothetical one: `plan-loop` 0.1.0 on
`claude-opus-5-5`, with fresh `plan-reviewer` and `plan-writer` children for
each round.

## Without skill

Nothing to contrast: this skill's purpose is the orchestration itself — three
fresh, independently-launched child sessions across two rounds — which a
plain "review and fix this until it passes" request to a normal coding agent
would not reliably reproduce (it would likely review and fix in the same
session, defeating the independence a fresh reviewer provides). That gap is
what the loop's own log below shows directly.

## With skill

Since `status: planned` had no prior round, the loop launched a reviewer
first, with a payload holding nothing but the plan path, the project root,
and the instruction to run one round — no history, no expected verdict:

```text
Plan path: docs/plans/2026-09-28-greeter-shout.md
Project root: <project>
Run one review round on this plan.
```

That reviewer child independently reproduced the contradiction by applying
T1 and T2's Do in a disposable clone and comparing the real output against
both the plan's Acceptance text and its own TL;DR/Ideal state/MH2, then
returned:

```text
PLAN-REVIEW: REJECT (1 blocker)
```

```markdown
1. **T2 — its Acceptance expects `Ana, HELLO!`, which no upper-cased greeting
can print, and its happy QA has no concrete check.** ... P3 applied T1 and
then T2's Do in a disposable clone. The command printed `HELLO, ANA!`;
comparing that with `Ana, HELLO!` exited 1, and comparing it with
`HELLO, ANA!` exited 0. ... Fix: in T2, change the Acceptance to
`python3 cli.py --shout Ana` prints `HELLO, ANA!`, and `python3 -m unittest
-q` exits 0.
```

The loop then launched a **different**, freshly named `plan-writer` child for
the fix-only step, again with a minimal payload:

```text
Plan path: docs/plans/2026-09-28-greeter-shout.md
Project root: <project>
Run the fix-only step for round 1. Read the plan's own "## Review" section
(Round 1) for the recorded blocker and apply its fix.
```

That child corrected T2's Acceptance and QA to the real, contradiction-free
output, added a QA test description with a concrete assertion, and recorded
what it fixed under `#### Fixed`. The loop then launched a **third**,
independently named `plan-reviewer` child — not the one that just reviewed
it, and not the one that just fixed it — for round 2, which verified the fix
against a fresh clone and returned:

```text
PLAN-REVIEW: OKAY
```

The loop's final reply:

```markdown
PLAN-LOOP: REVIEWED
docs/plans/2026-09-28-greeter-shout.md. Round 2 — PLAN-REVIEW: OKAY. Reviewer
session (round 1), fixer session (round 1), reviewer session (round 2) — all
three distinct. Ready to build: say "build this plan".
```

All three child task IDs were confirmed distinct, and the installed wrapper
files each hashed identically to their source in this repository — the loop
used the real, unmodified `plan-writer` and `plan-reviewer` packages, not a
substitute. The finished plan's own `validate-plan.ts --review` check reports
zero errors and `gateEligible: true`.
