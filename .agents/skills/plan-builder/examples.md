## Prompt

> Build this plan: docs/plans/2026-09-28-greeter-shout.md. Follow the plan-builder skill exactly. When you finish or reach a checkpoint, reply with its verdict block.

The project was the E5 fixture: a reviewed, two-todo plan (end greetings with
punctuation, then add a `--shout` flag) on a fresh clone with real
pre-existing owner work outside the plan's files — a staged deletion, an
unstaged deletion, a mixed staged/unstaged README edit, an unstaged notes
edit, and an untracked file. This is an excerpt from a real run, not a
hypothetical one: `plan-builder` 0.1.0 on `claude-fable-5-1`, with a fresh
`plan-result-reviewer` child on `claude-opus-5-5` for F4.

## Without skill

Nothing to contrast here: this skill's whole purpose is the receipt trail and
the independent F4 review, which a normal coding agent given the same request
would not produce on its own — it would edit the files, run the tests once,
and say done. The interesting comparison is between what a bare "build this"
request yields and what this skill's discipline adds; that gap is the reply
below.

## With skill

The build ran T0 through T2, then F1 through F4, without stopping to ask for
a routine continue. Its final reply:

```text
PLAN-BUILD: DONE
docs/plans/2026-09-28-greeter-shout.md. All todos and final gates are Done.
F4 result review: PLAN-RESULT: MATCH (round 1). Baseline:
`silly-skills/plan-builds/2026-09-28-greeter-shout-r1/baseline`. Branch:
`feat/greeter-shout`. Commits: 2.
```

Thirteen receipts chained from the baseline, each with its own snapshot:

```text
1 T0 start    2 T0 checkpoint    3 T0 pass  (test -f, QA)
4 T1 start    5 T1 checkpoint    6 T1 pass  (unittest, greet assertion, QA happy/failure)
7 T2 start    8 T2 checkpoint    9 T2 pass  (shout assertion, unittest, QA happy/failure)
10 F1 pass (MH1, MH2, MN1)    11 F2 pass (unittest, slop pass)
12 F3 pass (every QA scenario)    13 F4 pass (the result review itself)
```

T1 and T2 each committed only their own owned files:

```text
03b89ce feat: end greetings with punctuation   (greet.py, test_greet.py)
94359d1 feat: add a shout flag                 (cli.py, test_greet.py)
```

The owner's five pre-existing changes — the staged and unstaged deletions,
the mixed README edit, the notes edit, and the untracked file — were never
touched. The validator's own `--review --resume` check on the finished plan
reports zero errors, no drift, and no remaining todo.

F4 spawned a fresh `plan-result-reviewer` child, which independently traced
every requirement to its commit and rerun its checks, then returned:

```markdown
**Verdict:** PLAN-RESULT: MATCH
**Inventory:** 4 paths changed — committed 3, staged 0, unstaged 0, untracked
1 (this plan, administrative), removed 0; owner-work paths 5, preserved 5

| Requirement | Satisfied by | Evidence | Status |
| --- | --- | --- | --- |
| MH1 `greet(name)` ends with `!` by default, and `punctuation=""` keeps the old text | `greet.py:4-5`; tests `test_greet.py:10-14` | `python3 -c '...'` → `Hello, Ana!`; `... punctuation="")` → `'Hello, Ana'` | met |
| MH2 `--shout` upper-cases the greeting | `cli.py:8-12`; test `test_greet.py:19-22` | `python3 cli.py --shout Ana` → `HELLO, ANA!`; 4 tests ok | met |
```

The build's own reply was honest about two small issues it found in itself: a
duplicate baseline directory from an early attempt at `--output` that
included a leading `.git/` (since fixed with a clear rejection in
`capture-build-state.ts`, rather than the silent double-resolution that
produced the stray copy), and one recorded check command that did not
byte-for-byte match what was actually run, corrected and rerun under F4
rather than edited into the earlier receipt — receipts are append-only, so a
mistake is corrected forward, never rewritten in place.
