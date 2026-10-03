## Prompt

> Review this PR. It is commit `77335a5` on this repository — "feat(validate): require a non-blank examples.md for every skill". Two files changed: `scripts/validate.ts` and `scripts/validate.test.ts`.

## Without skill

An agent with no review skill loaded answers in the register the diff invites. The change is well made — one focused feature, a doc-comment kept in sync, four new tests — and the reply mirrors that back. The result is not lazy in the sense of being short. It runs to a couple of hundred words, it summarises the change accurately, every sentence in it is true, and it even offers a suggestion. What it never does is open a file the diff did not put in front of it.

````markdown
Looks good to me overall — clean, well-scoped change.

**What it does:** adds a `MISSING_EXAMPLES` error code to the validator so every skill
directory must ship a non-blank `examples.md` beside its `SKILL.md`. Zero-byte and
whitespace-only files are both rejected.

**Things I like:**

- The check is placed before the `SKILL.md` read, so an unreadable `SKILL.md` doesn't
  mask a missing companion file. Nice attention to detail.
- Test coverage is thorough — absent, zero-byte, whitespace-only, and the happy path
  are all covered.
- The error-code table in the header comment was updated, so the docs stay in sync
  with the code.
- Defaulting the fixture helper to write a valid `examples.md` keeps existing tests
  unaffected. Good backwards-compatible fixture design.

**Minor suggestion:** if more codes get added later, consider pulling the error message
strings out into constants.

The 9 errors this now raises on the shipped skills are expected and are called out in
the commit message. LGTM 👍
````

Everything above is accurate, and none of it required reading the code. The four bullets under "Things I like" are the commit message reordered, so the review would read exactly the same if the code did not match the message — which is the one thing a reviewer is there to check. No claim carries a `file:line`, so nothing in it is checkable by the author. Nothing separates what the code does from what the reviewer prefers. The single suggestion was not tested against the file. And because no record of what was examined exists, a reader cannot tell this review from a skim of the commit subject line.

## With skill

Following ai-review against the same commit: step 1 derived the report id `commit-77335a5` and found no existing `reports/ai-review-commit-77335a5.md`, so this is the first run for this target; step 2 counted 2 changed files, under the 300 limit, so the review continued; the stated intent then gathered with `git show -s --format=%B 77335a5`, the single-commit form step 4 gives, and treated as claims to verify; conventions gathered next under step 5 — no `AGENTS.md` and no `CONVENTIONS.md` at the repository root or in `scripts/`, so the patterns came from the changed files themselves; the diff read with `git show 77335a5` in step 6; the queue written in step 7 as two `(path, status)` rows, both `modified`, and at two files no batching was needed; all seven axes asked of each file in step 8; and every candidate finding checked at its line in `scripts/validate.ts` before it was written down, per step 9. `readTextFile` and the `validate` entry point are not in the diff; they were opened because two candidate findings depended on what they do. Once the body below was written, step 13 wrote it into `reports/ai-review-commit-77335a5.md`.

````markdown
## AI code review

> AI-generated review. An automated agent read the diff and wrote these findings. Each item is a claim to check, not a verdict.

**Reviewed:** local commit `77335a5` on the local working branch, read with `git show 77335a5` — 2 files (2 reviewed, 0 skipped), 3 findings.
**Stated intent:** the commit message — "feat(validate): require a non-blank examples.md for every skill".
**Conventions source:** no `AGENTS.md` and no `CONVENTIONS.md` at the repository root or in `scripts/`; patterns observed in `scripts/validate.ts` and `scripts/validate.test.ts`.

### Findings

#### 1. [minor] An oversized `examples.md` is reported as missing — `scripts/validate.ts:504`

- **Type:** fact
- **Axis:** edge cases
- **What:** line 504 collapses every `null` from `readTextFile` into one branch and reports `examples.md is missing, unreadable, or not UTF-8 text`. `readTextFile` (`scripts/validate.ts:234-244`) returns `null` for four different reasons: the path is not a regular file, the file is larger than `MAX_SCAN_BYTES`, a NUL byte appears in the first 8192 bytes, or the read threw. The size guard is line 237; `MAX_SCAN_BYTES` is 1 MiB at line 96.
- **Why it matters:** an `examples.md` that exists, is valid UTF-8, and is merely over 1 MiB fails the gate with a message saying it is missing. The author then goes looking for a file that is sitting in the directory. The other three causes are at least gestured at by the words "unreadable" and "not UTF-8 text"; size is named nowhere. 1 MiB is a generous ceiling for a worked example, so this is unlikely rather than impossible — but the failure mode is a misdirected author, not a clear error.
- **Suggested fix:** `stat` the path before the read and split the message. Report "not found" only when the file is absent, and name the byte limit when the file exists but exceeds it.

#### 2. [minor] The ordering the comment justifies has no test — `scripts/validate.ts:500`

- **Type:** fact
- **Axis:** correctness
- **What:** the comment at lines 500-501 states the block sits above the `SKILL.md` read so a skill whose `SKILL.md` is unreadable still reports its missing companion. That behaviour depends on the early `return null` at line 528. None of the four new tests reach it. Every one of them calls `writeSkill`, which always writes a readable `SKILL.md` at `scripts/validate.test.ts:82` before it touches `examples.md`, and the `Overrides` type at `scripts/validate.test.ts:32-40` has no switch for an unreadable `SKILL.md`.
- **Why it matters:** the placement is the one non-obvious decision in this diff, and it is the only part of it with no regression test. Move the block below line 528 and all four new tests still pass, so a later refactor can undo the decision silently and the suite will stay green.
- **Suggested fix:** add a `skill?: "valid" | "unreadable"` override to the fixture, add a case with a zero-byte `SKILL.md` and no `examples.md`, and assert that both `FRONTMATTER` and `MISSING_EXAMPLES` come back.

#### 3. [nit] Error codes are bare strings, so a typo compiles — `scripts/validate.ts:99`

- **Type:** opinion — confidence: high
- **Axis:** extensibility
- **What:** `Finding.code` is typed `string` at line 99. This change adds `MISSING_EXAMPLES` as a hand-written literal at lines 506 and 513, which is exactly how every other code in the file is written.
- **Why it matters:** `MISSING_EXAMPLE`, or the same string with a trailing space, would compile and ship, and would surface only in whichever test greps for the exact text. Each code added raises that cost a little. This is a `nit` rather than a `minor` because the author followed the convention the file already sets — changing the convention is a separate call, and it is theirs to decline.
- **Would change my mind:** a reason to keep the field open, such as a plan to let another script push findings into the same list with codes this file does not know about.
- **Suggested fix:** declare a string-literal union of the codes and type `Finding.code` as that union.

### What I checked

| File | Status | Axes | Result |
| --- | --- | --- | --- |
| `scripts/validate.ts` | modified | all seven | findings 1, 2, 3 |
| `scripts/validate.test.ts` | modified | all seven | finding 2 |

### Needs human judgment

- No test run. `scripts/validate.test.ts` was read, not executed, so this reports the shape of the four new cases and not their result.
- Finding 1 was reasoned from the size guard at `scripts/validate.ts:237`. No oversized `examples.md` was built to watch the validator misreport it.
- With no `AGENTS.md` and no `CONVENTIONS.md`, the standardization axis was judged against the two files in the diff alone. A convention this repository keeps elsewhere and breaks here would not have been caught.
- The commit message predicts 9 `MISSING_EXAMPLES` errors against the shipped skills. That count was not verified against the tree at this commit.
- Look beyond these findings: the parts of `scripts/validate.test.ts` outside the four new cases got the least attention. The `writeSkill` fixture helper and the `Overrides` type were opened only to trace finding 2, and the pre-existing test cases that call the same helper were not walked one by one to see how the new `examples.md` default changes what they exercise.
````

One candidate finding did not survive step 9 and so is absent above. Line 502 rebuilds the companion path from `category` and `dirName` rather than deriving it from `rel`, which would point at the wrong directory for a misplaced `SKILL.md`. Opening the caller settled it: the `LAYOUT` guard at `scripts/validate.ts:713-720` runs `continue` before `validateSkill` is reached unless `rel` splits into exactly four segments, so the reconstruction cannot diverge from the real directory. The suspicion was reasonable from the diff alone and wrong against the code, which is the case the verification step exists for.

<!-- markdownlint-disable-next-line MD024 -->
## Prompt

> Review pull request 88. It changes 320 files. None of them match the repository `.gitignore`.

<!-- markdownlint-disable-next-line MD024 -->
## Without skill

The agent starts reading. It asks for the diff, then works through the file list from the top: a workflow change, a generated client, a migration, a test helper. After a long pass over the first directories it writes a short review of the files it reached and says the rest look consistent with them. The unread files are not named. Nothing in the reply says the review stopped.

<!-- markdownlint-disable-next-line MD024 -->
## With skill

The count is 320, which is over 300, so the run stops before the diff. The reply is the stop note, posted when the target is a pull request, and written to `reports/ai-review-pr-88.md`.

````markdown
## AI code review

> AI-generated note. The review stopped before reading the diff because this change is over the file limit. Nothing here is a finding.

Sorry — this change is too big to review. It touches 320 files after gitignore matches are removed, and ai-review stops automatically above 300 files. No files were reviewed.

Split the change into smaller pieces, or ask again on a smaller slice.
````
