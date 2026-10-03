---
name: plan-loop
description: Drives a plan from a request or a draft to a reviewed plan by launching fresh plan-writer and plan-reviewer children in turn, never itself. Each round's reviewer is a new named session with no prior round's verdict in its payload; the fix step between rounds is a new plan-writer child too, never the session that wrote or reviewed before it. Stops at OKAY, at the five-round consent boundary, or at a genuinely unavailable input, with a structured handback instead of an invented independence claim. Building is the next request after review. Use when asked to write and review a plan until it passes, loop a plan through review, or fully automate planning to a reviewed state.
license: CC-BY-ND-4.0
metadata:
  version: "0.1.0"
  category: planning
  suggested-model: anthropic/claude-sonnet-5
  suggested-effort: high
---

# plan-loop

## Purpose

plan-loop automates the writer-then-reviewer cycle without weakening either skill's independence: it never writes a plan and never reviews one itself. Every round's reviewer is a freshly launched child session, given only the plan path and the current round; it never reads a parent's opinion, a fixer's self-assessment, or the loop's own history of what it hopes the verdict will be. Between rounds, a fix is a fresh `plan-writer` child running its fix-only step, never a continuation of the session that reviewed it and never the same session that will review it next. Five complete rounds without an OKAY is a consent boundary the loop stops at, not a cap it works around; a denied child spawn, an unavailable tool, or a depth limit is a structured handback to whatever invoked this loop, not a quiet inline substitute. The loop ends at a reviewed plan. It never builds. The `suggested-model` hint is advisory.

## When to use / when NOT to use

Use plan-loop when you:

- Want a plan written and reviewed to approval in one request, without manually relaying each round yourself.
- Have a plan already in `draft` or `planned` state and want it driven to `reviewed` automatically.
- Want genuinely independent rounds: a fresh reviewer every time, never the session that just fixed the plan.

Do NOT use plan-loop when you:

- Want one review round, or want to decide round by round yourself. Use `plan-reviewer` directly.
- Want only the plan written, with review handled separately. Use `plan-writer` directly.
- Are ready to build a reviewed plan. That is `plan-builder`; this skill stops once the plan is reviewed.
- Are already inside a plan-writer or plan-reviewer child session. Do not launch this loop from there; return your own handback instead.

## Workflow

1. Resolve what you were given: a planning request with no plan yet, or an existing plan path. Read [references/handoff.md](references/handoff.md) before doing anything else; it defines the handback shape this whole workflow uses.
2. **No plan yet.** Launch a fresh `plan-writer` child with the request, exactly as a user would give it. Wait for it to finish before doing anything else; only one actor writes the plan at a time. If it stops at the draft-gate block with an owner question, and this is the user's own session, relay the question here and wait; if this session is itself a child, return a handback with `nextRole: "writer"` and the open question under `inputs`, rather than answering for the owner. Once the child reaches `status: planned`, continue.
3. **An existing plan.** Read its `status`. `draft` needs a writer child first, as in step 2, given the plan path and its open frontier. `planned` or `reviewed` (on an explicit re-review request) starts the round loop below. Anything else is a handback naming what is unclear.
4. **Round loop.** Read the plan fresh from disk. Count complete rounds since the last recorded consent (or since round 1 if none). At five, stop: on the user's own session, ask whether to continue for up to five more or stop; as a child, return a handback with `kind: "consent"` and the round count under `inputs`. Never continue past five rounds without a recorded fresh consent, and never treat an old consent as covering a new five.
5. Launch a fresh `plan-reviewer` child. Its task payload is the plan path, the project root, and "one review round" — nothing else. It must not contain this loop's history, a fixer's own account of what it changed, or any framing of what verdict to expect; the reviewer reads prior rounds from the plan file itself, on its own authority, not from this loop's telling.
6. Wait for that child to finish, then read the verdict from the plan file's own `## Review` section — the durable record, not only the child's reply — so a resumed loop sees the same state a fresh one would.
7. **OKAY.** Stop. Report the plan is reviewed; building is the next request, not this loop's job.
8. **REJECT or INCOMPLETE.** If the blockers or gaps are identical to the immediately preceding round, with no new evidence and no newly runnable check named, stop and hand back rather than spending another round on an identical blocked checkpoint. Otherwise, launch a fresh `plan-writer` child for the fix-only step: the plan path and this round's number, nothing else. Wait for it. Then return to step 4 for a new round, with a new reviewer child — never the child that just fixed it, and never a resumed or forked session pretending to be new.
9. **A denied child launch, an unavailable tool, or a depth limit** that prevents launching a fresh child at any point is an immediate handback with the appropriate `nextRole` and `reason`; it is never worked around by reviewing or fixing inline. A host that blocks a nested spawn from inside a child (a reviewer or writer that itself tried to launch another child) surfaces as that child's own handback, which this loop relays upward rather than absorbing silently.

## Output format

The reply starts with exactly one verdict line:

```text
PLAN-LOOP: REVIEWED
PLAN-LOOP: HANDBACK (<kind>; <reason>)
```

```markdown
PLAN-LOOP: REVIEWED
<plan path>. Round <n> — PLAN-REVIEW: OKAY. Writer session <id>, reviewer session <id>. Ready to build: say "build this plan".
```

```markdown
PLAN-LOOP: HANDBACK (<kind>; <reason>)
<plan path>. <n> complete round(s). Next role: <writer | reviewer | owner>. Inputs: <what the next actor needs>. Next action: <the smallest concrete step that unblocks this>.
```

## Guardrails

MUST:

- MUST launch a new named child session for every writer, fixer, and reviewer turn; never resume, fork, or reuse a session across roles or rounds.
- MUST give a reviewer child only the plan path, the project root, and the round instruction — never this loop's history, a fixer's self-report, or any expected-verdict framing.
- MUST wait for each writer or fixer child to finish before launching that round's reviewer, and never let more than one actor write the plan at once.
- MUST read the verdict and round count from the plan file's own recorded state, not only from a child's reply, so a resumed loop matches a fresh one.
- MUST stop and require fresh consent at five complete rounds since the last one, on the user's own session, or hand back as a child.
- MUST return a structured handback (`kind`, `planPath`, `nextRole`, `inputs`, `reason`, `nextAction`) on a denied child launch, an unavailable tool, unreadable evidence, a depth limit, or an identical blocked checkpoint.
- MUST stop at the first OKAY and report the plan reviewed, without launching a builder or any further round.

NEVER:

- NEVER review or fix the plan inline as this loop's own session, under any circumstance.
- NEVER let the session that just fixed the plan also review it, by resuming, forking, or any other means.
- NEVER include the parent's verdict, opinion, or persuasion in a reviewer child's task payload.
- NEVER convert a round cap, a tool denial, a timeout, or an owner's waiver into an OKAY verdict; only a fresh reviewer's genuine approval does that.
- NEVER spend a round retrying an identical blocked checkpoint with no new evidence or newly runnable check.
- NEVER build the plan, or invoke `plan-builder`; this loop stops at a reviewed plan.
- NEVER continue past five rounds since the last consent without a freshly recorded one.

## QA checklist

- [ ] Every writer, fixer, and reviewer turn ran in its own newly launched child session, distinctly named, never resumed or forked.
- [ ] Each reviewer child's task payload held only the plan path, project root, and round instruction.
- [ ] Only one actor wrote the plan at a time; each writer/fixer child finished before its round's reviewer launched.
- [ ] The recorded round count and verdict came from the plan file itself, and matched what a fresh read would show.
- [ ] Consent was freshly recorded before any round past the fifth since the last consent.
- [ ] A denied launch, unavailable tool, unreadable evidence, depth limit, or identical blocked checkpoint produced a handback with all six required fields, not a retried round or an inline substitute.
- [ ] The loop stopped at the first OKAY without launching a builder.
- [ ] No cap, denial, timeout, or waiver was reported as an OKAY.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
