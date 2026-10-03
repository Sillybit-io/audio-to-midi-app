---
name: plan-builder
description: Builds a reviewed plan in the coding agent's own session, keeping a durable, resumable receipt trail as it goes. Captures a byte-exact baseline snapshot before touching anything, runs each todo's real Acceptance and QA, commits only that todo's owned paths, and never claims Done without a passed receipt. Resumes an interrupted build from its last recorded state, recovering from an unrecorded edit instead of guessing past it. Hands off to an independent result review before reporting complete. Use when asked to build this plan, implement this reviewed plan, or resume this plan.
license: CC-BY-ND-4.0
metadata:
  version: "0.1.0"
  category: planning
  suggested-model: anthropic/claude-opus-5-5
  suggested-effort: max
---

# plan-builder

## Purpose

plan-builder turns a reviewed plan into a durable, resumable build: every todo gets a start receipt before its effects, a checkpoint after them, and a passed receipt only after its real Acceptance and QA run and any required commit lands. Each receipt names a byte-exact snapshot of the project, captured by [scripts/capture-build-state.ts](scripts/capture-build-state.ts), so a crash, a host restart, or a fresh session can resume from the last recorded state instead of guessing at what happened. A build never claims a todo Done on a receipt it did not earn, never commits a path it does not own, and never reports complete without a fresh independent result review. Loading the skill is enough; the optional persona runs the identical workflow as a subagent. The `suggested-model` hint is advisory.

## When to use / when NOT to use

Use plan-builder when you:

- Are told to build, implement, or resume a plan with `status: reviewed` (or an in-progress `## Build` section from an earlier session).
- Need to pick up an interrupted build safely, without repeating completed work or guessing at what already happened.
- Need every todo's real Acceptance and QA run and recorded, not assumed from the plan text.

Do NOT use plan-builder when you:

- Have a plan that is not `status: reviewed` and has no existing `## Build` section. Send it to `plan-review` first.
- Want to write the plan's implementation todos differently. That is `plan-writer`.
- Only want to check a finished build against its plan without building anything. That is `plan-result-review`.
- Want a fully automated multi-round loop across writer and reviewer. That is `plan-loop`; this skill only builds.

## Workflow

1. Resolve the plan path from the request or conversation. Read it whole from disk, including `## Review` and any existing `## Build`. Ask for a path only if it cannot be resolved.
2. Decide the mode. No `## Build` section: **new build**. An existing `## Build` section: **resume**. Read [references/receipts.md](references/receipts.md) before either.
3. **New build preflight.** Run `bun <plan-review-base>/scripts/validate-plan.ts <plan> --review --root <project> --json`, where `<plan-review-base>` is the plan-review skill directory installed beside this one. Require `gateEligible: true`. If not, report the validator's `errors`/`gaps` and stop; a structurally valid but unapproved plan is not buildable. Exit 0 from the validator is a structural pass, never approval by itself.
4. **Resume preflight.** Run the same command with `--resume` added. Require `resumeEligible: true`. If `recoveryRequired`, follow the Recovery steps in the reference before any further progress. If `reconcileBoxes` is non-empty, fix those boxes only; do not repeat their receipts' work. If `drift` is non-empty with no recovery yet recorded, stop and investigate; do not advance past unexplained state.
5. **Baseline.** New build: capture it with `capture-build-state.ts` to a fresh, durable run directory (`git rev-parse --git-path silly-skills/plan-builds/<run-id>` in a git project; a durable path outside the project otherwise — never temporary storage). Verify the baseline's cited source bytes still equal the approval's `sources` digests; a changed source needs a new review, not a build. Resume: the existing baseline is already durable; verify it with the validator's own resume check from step 4, and do not recapture it.
6. Write or update `## Build` with the fenced `### Build record` the reference names: identity, approval snapshot, baseline reference, loaded skill identity (this skill's `SKILL.md` path and its SHA-256), and the receipts array (empty on a new build).
7. Run T0 exactly as it says: copy the plan into `docs/plans/` only if it is not already there, and continue in that copy from here on.
8. For each wave in the plan's listed order, for each todo in that wave: read [references/receipts.md](references/receipts.md)'s receipt sequence and follow it exactly — a start receipt (with any prerequisite recheck the reference requires) before any effect, the todo's actual edits, a checkpoint receipt after those known effects, the todo's real Acceptance and every QA scenario run for real with their actual output recorded, the todo's commit if it says `Commit: yes` (owned paths only, per the reference's collision rule), then a passed receipt only after checks and any required commit, then flip that todo's box to `- [x] Done` in the plan text. Continue to the next todo immediately; the plan's own `## Execution strategy` says not to stop between waves or ask for a routine continue. If a check fails, fix the todo and rerun its checks until they pass, then continue — never rewrite Acceptance or QA to make a failure disappear.
9. Run the final wave exactly as `## Final verification wave` describes: F1 plan compliance, F2 code quality (the project's real test/lint/build commands plus a slop pass), F3 every QA scenario, and the automated UI QA todo when `ui: yes`. F4 is the independent result review: spawn `plan-result-review` as a fresh child (the `plan-result-reviewer` subagent where the host supports it). If you cannot spawn a fresh child, stop and return a delegation handback to the primary agent; never run the review inline as yourself, and never report a result review that did not run. Mark each gate's box Done only once its own work, including F4's real subagent run, is complete.
10. **Completion** requires every final gate Done and the F4 result review at `PLAN-RESULT: MATCH` (or an accepted state per its own guardrails) for the current code and spec identities. A stale result review from before further changes is not reusable; request a fresh one. Report the Done block only then.
11. A genuinely unavailable input — Bun, a dependency, the plan-review or plan-result-review skill, network access a todo's check needs — is a checkpoint with the missing input named, never a reason to print Done or paper over the gap.

### Recovery

Read [references/receipts.md](references/receipts.md)'s Recovery section before acting on any drift, unexpected edit, or a crash after an effect the last receipt does not record. Investigate what actually changed, rerun the checks that change affects, and record a `recovery` receipt with the observed effects before resuming forward progress. Never replay a commit or another irreversible command merely because its outcome was not recorded; check the actual current state first.

## Output format

The reply starts with exactly one verdict line:

```text
PLAN-BUILD: DONE
PLAN-BUILD: CHECKPOINT (<todo or gate>; <reason>)
PLAN-BUILD: BLOCKED (<missing input>)
PLAN-BUILD: HANDBACK (<why the result reviewer could not be spawned>)
```

```markdown
PLAN-BUILD: DONE
<plan path>. All todos and final gates are Done. F4 result review: PLAN-RESULT: MATCH (round <n>). Baseline: `<snapshot>`. Branch: `<branch>`. Commits: <n>.
```

```markdown
PLAN-BUILD: CHECKPOINT (T<n>; <reason>)
<plan path>. Receipts through seq <n>. <n> of <total> todos Done. Next: <what resumes this, or what the caller must supply>.
```

## Guardrails

MUST:

- MUST require `gateEligible: true` (new build) or `resumeEligible: true` (resume) from the real validator run before any application edit; a structurally valid record is not the same as an approved or resumable one.
- MUST capture the baseline, and every checkpoint/pass snapshot, with `capture-build-state.ts`, never by hand or by skipping verification.
- MUST persist a start receipt before a todo's effects, a checkpoint after them, and a passed receipt only after its real checks and any required commit.
- MUST run every todo's actual Acceptance and QA scenario and record the real command and result; a planned check is not evidence until it runs.
- MUST commit only a todo's owned paths, and checkpoint instead of whole-file staging when initial owner content or unaccounted edits collide with an owned path.
- MUST investigate drift and record a recovery receipt before resuming forward progress after an unexplained state change.
- MUST spawn a fresh `plan-result-review` child for F4 and require its current MATCH before reporting Done.
- MUST continue through every wave and the final wave without stopping to ask for a routine continue, per the plan's own execution strategy.
- MUST name the missing input and checkpoint when Bun, a dependency, an approval, or a required snapshot is unavailable.

NEVER:

- NEVER treat validator exit 0, or any check's mere completion, as approval or a passing result by itself.
- NEVER commit an unrelated initial or unaccounted change together with a todo's owned paths.
- NEVER rewrite a todo's Acceptance or QA to make a failing check pass; fix the implementation instead, or checkpoint if the check itself is wrong and needs a new review.
- NEVER report a final result review that did not actually run, or reuse a stale one after further changes.
- NEVER replay a commit or another irreversible command because its outcome was not recorded; investigate the real current state first.
- NEVER push.
- NEVER mark a todo Done without its own durable passed receipt.
- NEVER rely on temporary storage, an unreferenced Git blob, or any location that will not survive a session end for a baseline or a receipt snapshot.

## QA checklist

- [ ] The preflight ran the real validator and required `gateEligible`/`resumeEligible` before any edit.
- [ ] A durable baseline snapshot exists, captured by `capture-build-state.ts`, and its location is recorded in `## Build`.
- [ ] Every todo has a start, a checkpoint, and a passed receipt in that order, each with a real snapshot reference.
- [ ] Every passed receipt's checks are the todo's actual Acceptance and QA commands, run for real, with their actual results.
- [ ] Every `Commit: yes` todo's commit touches only its owned paths, and a collision with unrelated content checkpoints instead of force-staging.
- [ ] Every todo's box is `- [x] Done` only after its passed receipt, and every gate's box is `- [x] Done` only after its own work.
- [ ] F4 ran a fresh `plan-result-review` child and recorded its current verdict; Done was reported only on MATCH (or an accepted state).
- [ ] No temporary directory, unreferenced blob, or non-durable location holds a baseline or receipt snapshot.
- [ ] Nothing was pushed.
- [ ] A genuinely unavailable input produced a named checkpoint, not a claimed Done or a routine continue prompt.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
