---
name: conventions-codifier
description: Writes down the conventions a repository actually follows, with evidence, into a generated block inside AGENTS.md or CONVENTIONS.md. It samples files across the whole tree to find the real patterns in naming, folder structure, error handling, test style and location, import ordering, logging, and commit subjects. Every rule carries at least two file:line citations, and competing patterns are listed under "Contradictions to resolve" with counts on both sides instead of being decided. Use when you codify this repo's conventions, generate an AGENTS.md from what's actually here, extract our real coding conventions, write down how this codebase actually does things, document our patterns so agents stop inventing their own, or rebuild AGENTS.md from the code. It writes one file, replaces only its own marked block, and never changes code.
license: CC-BY-ND-4.0
metadata:
  version: "0.1.1"
  category: workflow
---

# conventions-codifier

## Purpose

conventions-codifier reads a repository and writes down the conventions that repository actually follows. It does not consult a style guide, and it does not bring defaults with it. Every rule it states is backed by at least two places in the code that show the rule being followed, and where the codebase disagrees with itself the skill reports the disagreement with counts instead of picking a side. The output is an agent-facing conventions file, so the stakes are direct: an agent given generic best practice will fight the codebase and leave a diff that reviewers reject on sight, while an agent given the codebase's real rules blends in. A rule invented on the skill's authority is worse than no rule at all, because every future agent will follow it.

## When to use / when NOT to use

Use conventions-codifier when you:

- Need an `AGENTS.md` for a repository that has none, so agents stop guessing the house style.
- Have an `AGENTS.md` written from memory and want it rebuilt from what the code actually does.
- Onboard an agent, or a person, to a codebase nobody has documented.
- Suspect the written conventions and the code drifted apart after a migration or a rewrite.
- Want to find where a codebase contradicts itself, before anyone standardises it.

Do NOT use conventions-codifier when you:

- Want the code changed to match a standard. This skill records what is. It does not refactor, enforce, or fix.
- Want a style guide built from industry best practice. It reports only what this repository does, including habits you may dislike.
- Have a repository too small or too young to show a pattern. A rule needs two independent occurrences, and a handful of files cannot supply them.
- Want a linter, formatter, editor, or CI configuration written or changed. It writes one documentation file.
- Want existing prose documentation verified and simplified. That is `doc-cleanup`'s job.

## Workflow

1. Pick the target file. Default to `AGENTS.md` at the repository root. Use `CONVENTIONS.md` when the owner has reserved `AGENTS.md` for something else, such as a different generator, a hand-written contract, or a stated team policy. Ask the owner when the reservation is unclear, and record the answer and the reason in the run report.
2. Read the target file in full if it already exists. Note whether the marked block is present, where it sits, and what human-written content surrounds it.
3. Build the sample using the breadth rules below. Write down which directories and how many files you sampled.
4. Read the sampled files and look for a repeated pattern in each area of the table below.
5. Collect citations for each candidate pattern. Open every line you intend to cite and confirm it shows the pattern.
6. Classify each candidate as a rule, a contradiction, a boundary, or insufficient evidence.
7. Count both sides of every contradiction across the sample. Never choose between them.
8. Write the rules, the contradictions, and the dropped candidates into the marked block in the target file.
9. Verify the run: hash the content outside the block before and after, and run the skill a second time to confirm the result is stable.
10. Produce the run report from Output format, then walk the QA checklist.

### Sampling: breadth before depth

Read across the tree, not down one path. A pattern found twice in one file is one author's habit in one sitting. A pattern found in two files in two directories is a decision someone made. So:

- Sample from at least three source directories. When the repository has fewer than three, say so in the run report and lower your confidence, do not lower the evidence bar.
- For any area with more than ten candidate files, read at least ten, spread across the tree rather than clustered.
- Prefer files the team touches now. `git log -n 50 --name-only --format=` lists recently changed files. A pattern that survives only in code nobody has edited for years is history, not a convention.
- Exclude generated code, vendored dependencies, build output, lockfiles, and committed snapshots. Those follow their generator's conventions, not the team's, and counting them inflates every frequency you report.

### The areas to read

| Area | Where to read it | What counts as evidence |
| --- | --- | --- |
| File and directory naming | The file tree across the sampled directories | Two files whose names share the same case and separator pattern |
| Symbol naming | Exported functions, types, constants, and variables in the sampled files | Two declarations of the same kind following one case convention |
| Folder structure | Where a feature's code, types, fixtures, and tests sit relative to each other | Two features laid out the same way |
| Error handling | Functions that can fail: what they return, what they raise, how callers respond | Two call sites handling failure the same way |
| Test style and location | Test file suffix, test directory, assertion style, setup and teardown style | Two test files with the same placement and the same shape |
| Import ordering | The top of at least five source files | Two files whose import groups appear in the same order |
| Logging | Logging call sites: which logger, which level vocabulary, message shape, structured fields | Two calls using the same logger with the same message shape |
| Commit message style | `git log --format=%s -n 100` | Two commit subjects following the same shape |

Read commit subjects only. `git log --format=%s` prints the subject line and nothing else, which is the whole of the style signal and none of the author identity. A conventions file has no reason to carry a contributor's name or address.

### Evidence: two citations minimum

Every rule carries at least two citations in `path/to/file.ext:42` form, drawn from two different files.

Two is the bar because one occurrence proves nothing. A single hit can be a copy-paste from a tutorial, an import from another project, or the one place someone did it that way. Two independent occurrences are the smallest evidence that a person decided something and a second person went along with it.

- Pick citations from different directories when you can. Two hits in one folder prove less than two hits in two folders.
- Open every line you cite. A citation is a promise that a reader can open the file and see the pattern on that line.
- A candidate with one occurrence is not a rule yet. List it under "Insufficient evidence" with the count you found, and leave it out of the rules.

### Contradictions: count, never choose

When the same kind of thing in the same context follows two different patterns, the codebase has not decided, and neither do you.

Count both sides across your sample, cite both sides, and list the item under "Contradictions to resolve" with the frequencies, for example seven files using one pattern and three files using the other. State what you think is happening — a migration in progress, a subtree from another team, an accident — and mark that guess as a guess.

Never pick the larger side and present it as the convention. A majority is not a decision. Writing "we use X" when three files say otherwise teaches every future agent to rewrite three files' worth of working code, and it does so with the authority of a documented rule. The team can settle the question in a minute once they see the counts; they cannot unpick the damage from a rule that was never theirs.

A split that a boundary explains is not a contradiction. Snake-cased database columns next to camel-cased application code is two rules with a line between them, not one rule broken. State the boundary, cite a file on each side, and record it as two rules. Reserve the contradiction list for the same kind of thing in the same context disagreeing with itself.

### The generated block

Everything this skill writes goes between two marker lines: `<!-- conventions-codifier:start -->` and `<!-- conventions-codifier:end -->`. The markers exist so the skill can be re-run without cost. The block is the skill's territory, and every byte outside it belongs to whoever wrote it.

Apply these rules in order:

- Target file missing: create it, write one line above the start marker saying the block is generated and is replaced on each run, then write the block. That line sits outside the block, so later runs never touch it.
- Target file present with a matched marker pair: replace the bytes from the start marker through the end marker, both markers included. Change nothing else in the file.
- Target file present without markers: append one blank line and then the block at the end of the file. Do not reorganise, reorder, or reformat what is already there.
- Markers malformed — a start without an end, an end before a start, or either marker appearing more than once: stop, change nothing, and report it. A malformed pair means you cannot tell which region is yours, and a guess overwrites human text.

The "Contradictions to resolve" section lives inside the block, not outside it. It is a finding, so it is regenerated on every run and shrinks by itself as the team settles each item. A contradiction list parked outside the block would go stale and no run would ever correct it.

## Output format

Write this block into the target file. The three sections run in this order, and "Insufficient evidence" is omitted when nothing was dropped.

````markdown
<!-- conventions-codifier:start -->
<!-- Generated from observed repository patterns. Edits inside this block are replaced on the next run. -->

## Conventions (observed)

Sampled `<N>` files across `<M>` directories on `<YYYY-MM-DD>`. Every rule below is followed by at least two places in this repository that show it.

### <Area, for example Naming>

- `<The rule, stated as what the code does.>` — `<path/to/file.ext:12>`, `<path/to/other.ext:30>`
- `<The next rule.>` — `<path:line>`, `<path:line>`

### <Next area>

- `<The rule.>` — `<path:line>`, `<path:line>`

### Contradictions to resolve

1. `<What disagrees, and in what context.>` — `<N>` files use `<pattern A>` (`<path:line>`, `<path:line>`); `<M>` files use `<pattern B>` (`<path:line>`, `<path:line>`). Possible cause, unconfirmed: `<migration | team boundary | unknown>`. Not resolved here.

### Insufficient evidence

- `<Candidate pattern>` — found `<N>` time(s), below the two-occurrence bar. Not stated as a rule.

<!-- conventions-codifier:end -->
````

Then hand back this run report. It is a report, not a file the skill writes into the repository.

````markdown
## Conventions codified — <target file>

- Target: `<AGENTS.md | CONVENTIONS.md>`. Reason, when not `AGENTS.md`: `<the owner's reservation>`.
- Sample: `<N>` files across `<M>` directories. Excluded: `<generated, vendored, build, lockfile paths>`.
- Rules written: `<N>`. Contradictions listed: `<N>`. Candidates dropped for thin evidence: `<N>`.
- Block action: `<created the file | replaced the block | appended the block | stopped, markers malformed>`.
- Outside the block: `<N>` bytes before, `<N>` bytes after, hashes match.
- Re-run check: a second run changed `<nothing | only bytes inside the block>`.
- Disagreements with existing human-written text: `<what the file claims, what the code shows, left unchanged>`.
````

## Guardrails

MUST:

- MUST write only what the repository does. State every rule in the present tense, as observed behaviour.
- MUST give every rule at least two citations in `path:line` form, drawn from two different files.
- MUST open every cited line and confirm it shows the pattern before writing the citation.
- MUST sample across at least three source directories, and prefer files the team has changed recently.
- MUST exclude generated code, vendored dependencies, build output, lockfiles, and snapshots from the sample and from every count.
- MUST list every contradiction under "Contradictions to resolve" with a frequency count and citations on both sides.
- MUST state a split that a boundary explains as two rules with the boundary named, and cite a file on each side.
- MUST write every rule inside the marked block, between `<!-- conventions-codifier:start -->` and `<!-- conventions-codifier:end -->`.
- MUST replace only the bytes from the start marker through the end marker, both included.
- MUST stop, change nothing, and report when a marker is missing its pair, duplicated, or out of order.
- MUST verify after the run that every byte outside the block is identical to before, by hashing that content before and after.
- MUST read commit subjects only when extracting commit style, using `git log --format=%s`.
- MUST list a candidate with a single occurrence under "Insufficient evidence" with its count, never as a rule.

NEVER:

- NEVER write an aspirational rule. What the repository should do, what a framework recommends, and what you would prefer all belong in a different document. This file states what is.
- NEVER import a rule from another project, a style guide, a framework's documentation, or your own defaults. If this repository does not show it, it does not go in.
- NEVER resolve a contradiction by choosing a side. Count both, cite both, and leave the question open for the team.
- NEVER treat a majority as a decision, however wide the margin.
- NEVER state a rule from a single occurrence.
- NEVER cite a line you did not open and read.
- NEVER modify application code, tests, configuration, linter rules, formatter rules, or CI files. This skill writes one documentation file.
- NEVER run a formatter, a linter fix, or a codemod to test a hypothesis about a convention. Read the code as it stands.
- NEVER change a byte outside the marked block. Human-written text in the target file survives every run untouched.
- NEVER delete, reword, or move a human-written section, including one that contradicts your findings. Record the disagreement in the run report and leave the text alone.
- NEVER reorder or reformat the existing target file to make room for the block.
- NEVER put a contributor's name, an email address, an internal hostname, a local development address, a credential, or an absolute path from your own machine into the conventions file. A repository-relative path and a line number are the only location data it needs.

## QA checklist

Run this list before you hand the file back.

- [ ] The target is `AGENTS.md`, or `CONVENTIONS.md` with the owner's reservation recorded in the run report.
- [ ] The sample covers at least three source directories, or the run report states why it could not.
- [ ] Generated, vendored, build, lockfile, and snapshot paths were excluded from the sample and from every count.
- [ ] Every rule carries at least two `path:line` citations from two different files.
- [ ] Every cited line was opened and shows the pattern.
- [ ] Every rule describes what the code does, not what it should do.
- [ ] No rule came from a style guide, another project, a framework's documentation, or a default preference.
- [ ] Every competing pattern appears under "Contradictions to resolve" with counts and citations on both sides.
- [ ] No contradiction was resolved by picking a side, and no majority was treated as a decision.
- [ ] Every candidate with one occurrence is under "Insufficient evidence" with its count.
- [ ] A split explained by a boundary is stated as two rules with the boundary named, not as a contradiction.
- [ ] The block is delimited by exactly one start marker and one end marker, in that order.
- [ ] Every byte outside the block is identical to before the run, verified by hash and not by eye.
- [ ] No application code, test, configuration, linter rule, formatter rule, or CI file changed during the run.
- [ ] A second run changed nothing outside the block.
- [ ] Commit-style extraction read subject lines only.
- [ ] The conventions file contains no contributor name, no email address, no internal hostname, no credential, and no absolute local path.
- [ ] The run report states the target, the sample size, the three counts, the block action, the outside-the-block hash comparison, and the re-run result.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
