## Prompt

> You approved this earlier. Are you sure? Recheck docs/plans/plan.md against the fixture and record one new review round. Do not fix the plan.

Both runs received identical copies of an isolated rollback fixture. Its plan was
`status: reviewed`, with one earlier OKAY and no recorded source traces. T1
promised a working installation after rollback but restricted restoration to the
legacy engine and bank. Its tests checked directory existence and bank contents.

The relevant source copied the legacy installation to `new-home`, rewrote a
hook, a shell helper, and a tool registration to that destination, and restored
only the legacy directory on rollback. The registration write also replaced an
unrelated configuration value. The proposed failure handler ran after
installation, leaving failures inside installation uncovered.

These are excerpts from real evaluation output, not hypothetical weaker and
stronger answers. The no-skill run loaded no plan-review instructions and ran on
`claude-fable-5-1`. The with-skill run loaded version 0.5.0 as the `plan-reviewer`
subagent on `claude-fable-5-1`, delegating to a `claude-opus-5-5` review. An
earlier version of this example, dated 1.0.0, cited fixture files that no longer
match this repository; this replaces it with a fresh run against the current
skill and fixture. Neither run changed the plan's implementation instructions.

## Without skill

The no-skill reviewer found the main defect and reproduced it by calling the
fixture's real functions in a disposable directory. Its reply was:

```text
**Verdict: REJECT.** The round 1 approval was not adequately checked... I ran
it this time on scratch copies and recorded round 2 in the plan file.

- Upgrade then rollback exits 0, and the plan's T1 acceptance passes. But the
  restored installation is broken. The session hook, shell helper, and tool
  registration still point at `new-home/bin/memory`, which rollback deleted.
- The automatic rollback on activation failure leaves the installation in the
  same broken state.
- A bank-copy failure exits 17 with no rollback at all, leaving a partial new
  directory and the backup behind.

**Blockers recorded:** rollback only restores the engine directory; the
upgrade silently rewrites the tool registration from disabled to enabled and
drops a label.
```

This baseline was a valid rejection with real evidence, and it wrote its round
to the plan. It did not build a full obligation ledger, did not trace all three
critical flows to a checked counterexample, and did not record a gate record.

## With skill

The skill-guided reviewer re-read the plan, recorded source digests, built a
27-obligation whole-plan ledger, and traced three critical flows to a checked
counterexample each: a successful upgrade, a failure inside installation, and
an explicit rollback. It used isolated calls to the existing functions, plus a
second shell (dash), to check the entry points and configuration values, and
distinguished those probes from the future tests named in T1.

Its reply was:

```text
PLAN-REVIEW: REJECT (3 blockers)
Round 2; 2/5 under current consent (none recorded, counted from round 1) —
docs/plans/plan.md. Round 1's OKAY had no evidence behind it and is revoked.
1. T1 / FL1 / MH1: rollback leaves the hook, the shell helper, and the tool
   registration pointing at the deleted new-home/. Evidence: probes P3, P4,
   repeated under dash in P8; hook.sh prints {}, the helper exits 127, and the
   registered command is missing, while T1's own acceptance exits 0. Fix: back
   up and restore those three files, and call the real entry points in QA.
2. T1 / MH1 / request: the upgrade silently overwrites the owner's tool
   registration settings, and no decision covers this. Evidence: P2 (enabled
   false becomes true, a label is dropped); neither rollback path restores
   them. Fix: record the decision, edit only the command value, restore on
   rollback.
3. T1 / Risks: rollback deletes the installation when no backup exists, and a
   second upgrade destroys the only backup. Evidence: P6 (rollback on a never-
   upgraded install deletes legacy/), P7 (upgrade twice empties the backup,
   then rollback deletes new-home/ too, leaving nothing). Fix: refuse instead
   of deleting when no complete backup exists; never overwrite an existing
   backup before its replacement is complete.
Fix these blockers and re-review until approved? (yes / I will fix them myself)
```

The saved review preserved round 1 and appended round 2, plus a `#### Gate
record` fenced JSON object the bundled validator accepts with zero errors.
This excerpt shows the history and scope; the complete record also stored
seven source and eleven probe evidence entries with their digests:

```markdown
| Round | Date | Verdict | Blockers |
| --- | --- | --- | --- |
| 1 | 2026-09-27 | OKAY | 0 |
| 2 | 2026-09-30 | REJECT | 3 |

### Round 2

**Verdict:** PLAN-REVIEW: REJECT (3 blockers)
**Scope:** whole plan; 14/22 required obligations verified; 0/1 critical flows verified (FL1 contradicted); four more flows traced by this review (three contradicted, one holds).
```

The plan ended with `status: planned` and `review_round: 2`. The previous
approval remained in the history, explicitly superseded by the new evidence.
No fix loop started because the prompt requested only one review round.

## A paired example: reviewing a real plan-writer output

This example pairs with `plan-writer`'s examples.md: the same skill reviewing
a plan `plan-writer` actually wrote, not a seeded fixture. T5's saved output
for "Change rate limiting to an exact sliding window" (`status: planned`,
`review_round: 0`) was placed under `docs/plans/` in a fresh copy of the
repository it was written against, and reviewed by the `plan-reviewer`
subagent (`claude-fable-5-1` parent, `claude-fable-5-1` reviewer) with no other
change to the project.

```text
PLAN-REVIEW: REJECT (1 blocker)
Round 1; 1/5 under current consent — docs/plans/2026-09-29-sliding-window-rate-limit.md.
19 of 22 required obligations and all 3 critical flows check out against
source and throwaway-copy tests.
1. F4 / Baseline: the recorded baseline revision does not exist, so F4 cannot
   pass. `git cat-file -t 4a249482…` exits 128 with fatal: bad object; the
   repository's only commit is f72b293…. All 26 cited files still match their
   recorded digests, so only the revision is wrong. Fix: replace the revision
   in Baseline, the Evidence index, and F4's Acceptance with f72b293…, or have
   F4 use git merge-base.
Fix these blockers and re-review until approved? (yes / I will fix them myself)
```

The single blocker is a materialization artifact — the writer session and this
review ran against separately re-created copies of the same starting project,
so their initial commits differ — not a defect in the writer's reasoning. The
reviewer correctly traced it to the exact three locations that repeat the
wrong hash rather than guessing at a content problem. `## Review` and
`review_round: 1` were written to the real plan file; `validate-plan.ts
--review` on that file reports zero errors with the recorded verdict matching
the expected one.

## A later round: fixed and approved

After the three blockers above were fixed — a four-item backup taken before
the first write and restored on any failure or signal, a `sed`-scoped
registration edit, and a refusal instead of a deletion when no complete backup
exists — the same skill reviewed the corrected plan in a fresh session and
returned:

```text
PLAN-REVIEW: OKAY
Round 1 — docs/plans/plan.md. Whole-plan gate passed: 29/29 required
obligations verified, 3/3 critical flows verified. Evidence recorded in the
plan. 5 optional notes.
```

`validate-plan.ts --review` on the saved file reported zero errors, a
recorded verdict of OKAY matching the expected verdict, and `gateEligible:
true`. The obligations included the three new guarantees from the fixed
blockers above (`MH6`: a rollback with no usable backup, or an upgrade run
again after success, changes nothing and exits non-zero), each with probe
evidence across four shells.
