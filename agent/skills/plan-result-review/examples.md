## Prompt

> Compare the implementation with `docs/plans/2026-09-28-greeter-shout.md`. Reply with only the verdict block the plan-result-review skill's Output format names.

Both runs received an identical copy of a reviewed two-todo plan (add trailing
punctuation to a greeting, then a `--shout` flag) with a completed build: two
commits, four recorded checks, and five snapshots under the Git directory.
One receipt was deliberately wrong: T2's checkpoint recorded that only
`cli.py` changed between its snapshots, when `test_greet.py` had changed too.
The implementation itself was correct — the omission was in the receipt, not
the code.

These are excerpts from actual evaluation outputs, not hypothetical weaker and
stronger answers. The no-skill run loaded no plan-result-review instructions
and ran on `claude-fable-5-1`; its edit tool was declined, so it reported
findings in its reply instead of the plan. The with-skill run loaded version
0.1.0 as the `plan-result-reviewer` subagent on `claude-opus-5-5` and wrote
its findings to the plan's `## Result review` section, which is the only
change either run made.

## Without skill

The no-skill reviewer independently reconstructed the build's history and
found seven real differences, none of them the seeded receipt error: a
baseline revision mismatch caused by the owner's post-review commit, two
consumers the Evidence index misses, uncommitted owner edits in the working
tree, the still-open final wave, the plan's own fixture disclosure, and an
unreproducible spec digest. Its reply, trimmed to the header and first two
rows of its table:

```text
Bottom line: the code matches the plan exactly. Both build commits do what T1
and T2 say, touch only the files they name, and carry the specified messages.
Every acceptance and QA command reproduces its recorded output, and the test
suite runs 4 tests green. All seven differences are in the surrounding
state, not the implementation.

| # | Plan says | Actual | Reason |
| --- | --- | --- | --- |
| D1 | Baseline is `d4b9056` with only the plan dirty | Build started from
`96f101f` ("Owner files") | The owner committed run.sh, a `latest` symlink,
HISTORY, LICENSE and logo.bin after review and before build. |
| D2 | Evidence index "records every reader of greet" | run.sh and `latest`
are readers it omits | Both arrived in the owner's commit; the plan's search
cannot find them. |
```

This baseline was a valid, thorough report. It reconstructed the receipt
chain's hashes and confirmed the chain reproduces — it just never compared
each receipt's `changedPaths` against what its own before/after snapshots
show changed, so the one seeded defect never surfaced.

## With skill

The skill-guided reviewer built the same requirement and commitment tables,
then, following the skill's step on receipt changed paths, diffed every
receipt's recorded `changedPaths` against its own before/after snapshots. One
row failed:

```markdown
#### Commitments

| Commitment | Plan | Observed | Status |
| --- | --- | --- | --- |
| Receipt 7 changed paths | `cli.py` [worktree], plan [worktree], `test_greet.py` [worktree] | `cli.py` [worktree], plan [worktree] | not met (difference 1) |
| T2 order | checks, then commit, then Done | commit a522e4b first appears in receipt 8 (with checks); `final` snapshot HEAD = a522e4b | met |
```

Its reply was:

```text
PLAN-RESULT: INCOMPLETE
Result round 1 — docs/plans/2026-09-28-greeter-shout.md. Approval withheld:
one receipt does not account for a changed path.
Next check: builder corrects or annotates Build record receipt 7 (T2
checkpoint), which omits `test_greet.py`'s recorded change; or the owner
accepts the record as-is with a stated reason.
```

Its full Difference entry, saved to the plan:

```markdown
#### Differences

1. **unverified — T2 receipt changed paths (skill step 7).** Changed part:
Build record receipt seq 7 (T2 checkpoint), snapshots `T1` → `T2-edited`.
Expected: `changedPaths` lists every path that differs between the
snapshots: `cli.py [worktree]`, plan `[worktree]`, `test_greet.py
[worktree]`. Actual: the receipt lists only `cli.py [worktree]` and the
plan; `test_greet.py` worktree went from 385 B `08fb9a3b…` to 642 B
`987d425b…` (the `test_shout_upper_cases` test) without being recorded.
Reason: unknown (nothing in the Build record states it). Impact: the
receipt misattributes T2's test edit; the file itself is T2-owned and the
final content matches the plan, so no code is wrong, but the receipt chain
is not a faithful account of the build. Disposition: needs-evidence. Next:
builder corrects or annotates receipt 7, or the owner accepts the record
with a stated reason.
```

The saved round also recorded every requirement met (G1/MH1, G2/MH2, MN1,
T0–T2's Do/Must-not/Acceptance/QA, F4's file-scope check), the branch and
both commits confirmed against the plan, and an inventory of preserved owner
work (5 of 5 paths). `## Result review` was the only section either run
changed; the implementation and its history were untouched by both.
