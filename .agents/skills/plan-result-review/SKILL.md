---
name: plan-result-review
description: Compares everything a build changed with the reviewed plan it implemented, from the build's baseline snapshot. Inventories committed, staged, unstaged, untracked, deleted, renamed, binary, mode, and symlink changes, maps every requirement to a change and every change to a todo, checks that the owner's pre-build work survived, and explains each difference with its location, reason, and reason source. Returns MATCH, MISMATCH, or INCOMPLETE. Use when asked to check a build against its plan, review the result, confirm nothing was missed, or run a plan's scope-fidelity gate.
license: CC-BY-ND-4.0
metadata:
  version: "0.1.0"
  category: planning
  suggested-model: openai/gpt-6-astra
  suggested-effort: max
---

# plan-result-review

## Purpose

plan-result-review answers one question after a build: does what changed match what the reviewed plan said to change, and nothing else? It works from the build's baseline snapshot, not from the last commit, so it sees staged, unstaged, and untracked work, deletions, renames, binaries, modes, and symlinks. It also sees work the owner had in progress before the build started. It maps in both directions: every requirement and todo to the change or existing code that satisfies it, and every changed artifact to the todo that owns it. Each difference names the plan clause, the changed part, what was expected and what happened, and why, with the source of that reason. An unknown reason stays unknown. A reason never turns a violation into a match; only the owner's recorded approval does, and even then the difference stays visible. The skill writes only the plan's `## Result review` section and never repairs code. Run it in a fresh session, so the reviewer did not build what it reviews. The `suggested-model` hint is advisory.

## When to use / when NOT to use

Use plan-result-review when you:

- Finished building a reviewed plan and need an independent check before calling it complete.
- Run a plan's scope-fidelity gate, such as F4.
- Suspect the build missed a requirement, added unplanned changes, or touched the owner's own work.

Do NOT use plan-result-review when you:

- Want the plan itself reviewed before a build. That is `plan-review`.
- Want the code reviewed for quality or security without a plan. That is `ai-review`.
- Want the differences fixed. This skill reports them; the builder fixes them.

## Workflow

1. Resolve the plan path from the request. Read the whole plan from disk: frontmatter, spec, `## Review`, `## Build`, and any earlier `## Result review` rounds. The plan's approval is the latest OKAY round.
2. Record the identity: the plan's canonical spec digest, the current HEAD, and the dirty state. Record the phase: the gate you run for, such as `F4`, or `completion`.
3. Choose the baseline. Read [references/inventory.md](references/inventory.md). Use the Build record's snapshot; otherwise an explicit snapshot, base, or range from the caller; otherwise ask. Never guess `HEAD~1`, and never compare only the last commit. When owner-work preservation must be certified and no readable snapshot exists, the verdict is INCOMPLETE.
4. Build the change inventory with the helper `scripts/inventory-changes.ts`, or by hand as the reference describes. Include every path in the baseline and receipts, even when git no longer lists it. Record the totals by layer.
5. Read what changed. For each changed path, read its diff or its binary, mode, or symlink change, and enough surrounding code to judge behavior. When a question needs a wider search, you may send `plan-scout` one bounded question; otherwise search yourself.
6. Map requirements to changes. For each Must Have, Must NOT Have, gap, design decision, and todo (its Do, Must not, Acceptance, and QA), find the change or existing code that satisfies it. Run each acceptance and QA check you can in a disposable copy of the project, and record the command and result. A receipt's claim that a check passed is evidence to verify, not proof.
7. Check the execution commitments. Compare the current branch with the plan's `branch:`. For each `Commit: yes` todo, find its commit and compare the message and the files with the todo. For each Done todo, compare the checks its pass receipt records with the todo's Acceptance and QA commands. A planned check the receipt does not record is test-before-next evidence the build lacks, even when the check passes when you run it now. For each receipt with an after snapshot, compare its recorded changed paths with the paths and layers that differ between its before and after snapshots. A receipt that leaves out or adds a change misattributes work. Check the order the receipts record against the plan's order of checks, then commit, then Done: a commit that first appears before the receipt that records the todo's checks was made before those checks.
8. Map changes to todos. For each changed artifact, name the todo that owns it. The plan and its receipts are the authority; a file no todo names is extra, even when the change looks useful.
9. Check the owner's work. For every path that had staged, unstaged, or untracked changes at the baseline, confirm those layers survived, unless a todo owned that exact change. A path restored to HEAD, a deleted untracked file, or a newly ignored file counts as changed even when `git diff` is empty.
10. Record each difference with the fields in [references/differences.md](references/differences.md). Take an `approved` reason only from the owner's recorded decision, such as a Build note that quotes it or an answered question. Mark every other reason `inferred`, with its evidence, or `unknown`.
11. Decide the verdict by that reference: MISMATCH for unapproved differences, then INCOMPLETE for missing required evidence, then MATCH.
12. Append a round to `## Result review` in the plan, and preserve earlier rounds. Change nothing else in the plan or the project. Re-read the saved section and confirm that its verdict, counts, and identity match your findings.
13. Reply with the verdict block.

### Handling feedback

A challenge to a difference triggers an evidence check, not automatic removal. Correct an unsupported finding and say why. A hedged remark, such as "I think that file is fine", never removes a difference by itself: answer with the evidence and a yes/no question. An owner's explicit approval of a deviation is recorded as `approved` with its date, and the difference stays listed.

## Output format

The reply starts with exactly one verdict line:

```text
PLAN-RESULT: MATCH
PLAN-RESULT: MISMATCH (<n> differences)
PLAN-RESULT: INCOMPLETE
```

The section appended to the plan:

````markdown
## Result review

| Round | Date | Phase | Verdict | Differences |
| --- | --- | --- | --- | --- |
| 1 | <date> | F4 | MISMATCH | 2 |

### Result round <n>

**Verdict:** PLAN-RESULT: <verdict>
**Identity:** spec <digest>; HEAD <revision>; baseline <snapshot> (<manifest digest>) | base <revision>, owner work not certifiable
**Phase:** <F4 | completion>; <other gates still open, or none>
**Inventory:** <n> paths changed — committed <n>, staged <n>, unstaged <n>, untracked <n>, removed <n>; owner-work paths <n>, preserved <n>

#### Requirements

| Requirement | Satisfied by | Evidence | Status |
| --- | --- | --- | --- |
| MH1 <text> | `path:line`, or existing `path:line` | `<command>` → <result> | met / partial / missing / unverified |

#### Commitments

| Commitment | Plan | Observed | Status |
| --- | --- | --- | --- |
| Branch | `<branch:>` | `<current branch>` | met / not met |
| T<n> commit | `<message>`; `<files>` | `<sha> <message>`; `<files>` | met / not met |
| T<n> recorded checks | `<Acceptance and QA commands>` | `<commands the pass receipt records>` | met / not recorded |
| Receipt <seq> changed paths | `<paths that differ between its snapshots>` | `<paths the receipt records>` | met / not met |
| T<n> order | checks, then commit, then Done | `<receipt where the commit first appears>` | met / not met |

#### Artifacts

| Path | Change | Owning todo | Status |
| --- | --- | --- | --- |
| `path` | modified / added / deleted / renamed / mode / symlink / binary | T2 | planned / extra / owner-work |

#### Differences

1. **<kind> — <clause>.** Changed part: <location>. Expected: <…>. Actual: <…>. Reason: <…> (source: approved <where> / inferred <evidence> / unknown). Impact: <…>. Disposition: <…>. Next: <…>.

#### Owner work

- `path`: <baseline layers> → <current layers>; preserved | changed (difference <n>)

#### Unverified

- <missing evidence, what it blocks, and the next check>, or None.

#### Checked

- Inventory: helper | manual — <paths>, <layers>.
- Requirements: <met>/<total>; artifacts: <planned>/<total>.
- Checks run in a disposable copy: <commands and results>.
````

## Guardrails

MUST:

- MUST compare from the build baseline snapshot, or an explicit base the caller gave, and say which.
- MUST inventory committed, staged, unstaged, untracked, deleted, renamed, binary, mode, and symlink changes, plus every baseline and receipt path.
- MUST read the contents of every changed artifact, not only its name.
- MUST map every requirement to a change or existing code, and every changed artifact to a todo or a difference.
- MUST check that the owner's pre-build staged, unstaged, and untracked work survived.
- MUST compare the branch, each planned commit, and each pass receipt's recorded checks and each todo's commit order with the plan, and each receipt's changed paths with its snapshots.
- MUST record for every difference its clause, changed part, expected and actual result, reason, reason source, impact, disposition, and next step.
- MUST return INCOMPLETE when required evidence, such as a readable baseline, is missing and no unapproved difference is proven.
- MUST keep approved deviations listed, with the record of the owner's approval.
- MUST run checks that execute code only in a disposable copy of the project.

NEVER:

- NEVER guess a base such as `HEAD~1`, or review only the last commit.
- NEVER change code, tests, configuration, or any part of the plan outside `## Result review`.
- NEVER invent a reason, or mark a reason `approved` without the owner's recorded decision.
- NEVER treat a reason, a receipt, or a passing test as a waiver of a violated requirement.
- NEVER report MATCH with an unexplained artifact, an unmapped requirement, or changed owner work.
- NEVER claim the build is complete; MATCH certifies only the compared implementation.

## QA checklist

- [ ] The baseline is the Build record's snapshot or an explicit base, and the record says which.
- [ ] The inventory covers all layers, deletions, renames, binaries, modes, symlinks, and every baseline and receipt path.
- [ ] Every requirement and todo has a row in Requirements, and every changed path has a row in Artifacts.
- [ ] Every owner-work path at the baseline is listed under Owner work.
- [ ] The branch, each planned commit, each Done todo's recorded checks and commit order, and each receipt's changed paths have a row in Commitments.
- [ ] Every difference has all its fields, and no reason is marked approved without a recorded owner decision.
- [ ] The verdict follows MISMATCH, then INCOMPLETE, then MATCH, and its count equals the unapproved differences.
- [ ] Only `## Result review` changed in the plan, and nothing changed in the project.
- [ ] The saved section was re-read and matches the reply.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
