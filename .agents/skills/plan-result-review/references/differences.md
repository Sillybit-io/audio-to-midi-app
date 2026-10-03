# Differences and verdicts

Read this file when you record a difference and before you decide the verdict.

## Kinds

| Kind | Meaning |
| --- | --- |
| missing | A requirement, todo, or acceptance criterion has no change and no existing code that satisfies it |
| partial | A change addresses the requirement but not all of it, its acceptance fails, or an execution commitment is not followed, such as the planned branch or a commit's message or files |
| extra | A changed artifact belongs to no todo |
| changed-behavior | A change alters behavior the plan did not ask to alter, or breaks a Must NOT Have |
| obsolete-or-renamed | An artifact the plan names was renamed, moved, or deleted, or a new one replaced it |
| owner-work-changed | Work present at the baseline, staged, unstaged, or untracked, was changed, restored to HEAD, or removed |
| unverified | Evidence needed to judge a requirement or an artifact is unavailable, including a planned Acceptance or QA check that no pass receipt records, or a receipt whose changed paths disagree with its snapshots |

## Fields

Every difference records:

- **Clause:** the plan text it is judged against, as `T3 Acceptance`, `MH2`, or `D4`, with a short quote.
- **Changed part:** `path:line`, a diff hunk, or `path (deleted)`, `path (binary)`, `path (symlink a → b)`, `path (mode 100755 → 100644)`.
- **Expected** and **actual**, as observable facts.
- **Reason** and its **source**: `approved` when the owner's recorded decision authorizes it, with where it is recorded; `inferred` when the reason comes from evidence such as a commit message or a Build note, with that evidence; `unknown` when nothing states it. Never invent a builder's intention.
- **Impact:** what breaks or could break.
- **Disposition:** `accepted-approved`, `fix-required`, `needs-owner`, or `needs-evidence`.
- **Next:** the check or fix that closes it.

A check you run during review shows the current state. It does not show that the builder tested a todo before starting the next one. When a receipt does not record a planned check, report it as `unverified` with disposition `needs-evidence`, even when your own run passes.

A reason does not make a violation acceptable. Only an owner's recorded approval does, and the difference stays listed.

## Verdict

Decide in this order:

1. **MISMATCH** when any difference is not approved by the owner and is not `unverified`. The count is the number of those differences.
2. **INCOMPLETE** when no such difference remains but required evidence is missing: an unreadable or corrupt baseline, a requirement you could not check, or an acceptance command that could not run.
3. **MATCH** when every requirement maps to a change or to existing code that satisfies it, every changed artifact maps to a todo, all owner work is preserved, and every remaining difference is owner-approved.

MATCH certifies the compared implementation and its evidence. It does not certify other workflow gates that have not run, and it does not waive a gate the builder still owes.
