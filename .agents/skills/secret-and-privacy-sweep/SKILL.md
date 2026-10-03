---
name: secret-and-privacy-sweep
description: Reads a staged diff, a branch diff, or a whole working tree and judges whether anything in it is too sensitive to publish. It sweeps six categories, credentials and tokens and keys, personal data, internal infrastructure references, business-confidential terms, values copied out of environment files, and high-risk file types, then gives every finding a severity, a location, a reason, and a remediation, and ends with one verdict line. Use when you say sweep this diff for secrets, check for leaked credentials before I publish, run a privacy scan before open-sourcing, is this branch safe to push, did I commit a key, or check this repository for personal data. It complements a regex scanner such as gitleaks and does not replace it. It masks every value it reports, deletes nothing, and never rewrites git history.
license: CC-BY-ND-4.0
metadata:
  version: "0.1.0"
  category: workflow
---

# secret-and-privacy-sweep

## Purpose

secret-and-privacy-sweep answers one question before you publish: is there anything in this change that must not leave the building? A regex scanner answers half of that. Gitleaks matches known secret shapes and scores entropy, and it is very good at the half it covers, which is why this skill runs it first and treats its output as a floor. The other half is judgment. A regex cannot tell you that a fixture holds a real customer's name, that a hostname maps your private network, or that an unreleased product codename sits in a comment. Those are decisions about whether a string *is* sensitive, not whether it *matches*. This skill makes those decisions, writes each one down with a reason, and hands you a verdict. It reports. It changes nothing.

## When to use / when NOT to use

Use secret-and-privacy-sweep when you:

- Are about to open a pull request and want the diff swept first.
- Are about to publish, open-source, or hand over a repository that was private.
- Want a whole working tree checked, not just what you changed.
- Suspect a credential was committed and want to know whether history is affected.
- Want a regex scanner's output reviewed by judgment, including its misses.
- Need one verdict you can gate a release on.

Do NOT use secret-and-privacy-sweep when you:

- Want the problems fixed. This skill names them and proposes remediation in words. It applies nothing.
- Want git history rewritten. It tells you when a rewrite is needed. A human runs it.
- Want a code review of the change. Use ai-review.
- Want a project's AI surfaces audited. Use ai-audit.
- Want only a regex scan. Run gitleaks directly; this skill adds cost you do not need.

## Workflow

1. Fix the scope before you read anything, and write it in the report. Pick one of three:

   ```sh
   git diff --cached                 # staged diff, before a commit
   git diff <base>...HEAD            # branch diff, before a pull request
   git ls-files && git status --porcelain --untracked-files=all   # full tree, before publishing
   ```

   A full-tree sweep is the only scope that catches a file nobody touched this week. Use it before any publish or open-sourcing. Use a diff scope for routine pull requests.
2. Establish the history question for this scope. Run `git log --oneline <range>` for a diff scope, or record that a full-tree sweep covers the current tree only. You need this because a finding in a staged change and the identical finding in a commit from last March have different remediations, and step 7 depends on knowing which one you have.
3. Run the regex scanner first if it is available, and record the exact command and its result in the report:

   ```sh
   gitleaks dir --no-banner -v .
   gitleaks git --no-banner -v .
   ```

   Gitleaks detects secrets by regex rules plus entropy scoring. Its findings are the floor of your report, not the ceiling. If it is not installed, say so in the report and continue; the judgment pass is the part only you can do. Never report a clean gitleaks run as a clean sweep.
4. Sweep all six categories below. Walk every one of them even when an earlier category already produced a blocker, because a report that stops at the first problem hides the rest.
5. Give every finding exactly one severity from the table below, a `file:line` location, a plain reason it is risky, and a remediation. Verify the location by opening the line before you write the finding.
6. Mask every value as you record it. Keep the first two and the last two characters, replace everything between them with asterisks, and never write the middle anywhere, not in the report, not in a commit message, not in your own commentary. A masked value reads like `gh***...***3f`. If two characters at each end would still identify the value, such as a short numeric identifier, describe the kind and drop the specimen entirely.
7. Answer the history question for each finding as a yes or no, with a one-line reason. Yes when the value already exists in a commit, because removing it from the current tree leaves it in every clone and every fork. No when it is staged or unstaged and has never been committed, because removing it before the commit is enough. Then say who has to act: this skill recommends, a human executes.
8. Write the report in the shape given below and end it with the verdict line. Then walk the QA checklist.

### Scan categories

Sweep these six in order. The judgment column is the question a regex cannot answer for you.

1. **Credentials, tokens, and keys.** Check the obvious places, then the places a scanner under-reads: commented-out code, test fixtures and mock payloads, notebook output cells that captured a live response, and URLs inside lock files or configuration that embed credentials in the authority part, in the shape `https://<user>:<token>@<host>/path`. Judgment: is this a live credential, a revoked one, or a placeholder someone shaped to look real? Treat "I think it is revoked" as live until someone confirms otherwise.
2. **Personal data.** Names, email addresses, phone numbers, and postal addresses in fixtures, seed data, documentation, screenshots, and test snapshots. Judgment: is this obviously synthetic, or is it a real person? Reserved example domains and clearly invented names are fine. A plausible full name attached to a plausible address is not, even when you cannot prove it is real. Unprovable and plausible is a finding, at lower severity.
3. **Internal infrastructure references.** Internal hostnames, private address ranges such as those reserved by RFC 1918, internal-only URLs, bastion and VPN endpoints, and service or queue names that only exist inside a private network. Judgment: does this string tell an outsider the shape of your network, or is it generic? One internal hostname is a map fragment. Several together are a map.
4. **Business-confidential terms.** Unreleased product names, internal codenames, roadmap dates, pricing not yet public, and real customer or partner names. Judgment: is this public yet? If you cannot point at where it was published, treat it as unpublished. This is the category most often waved through, because it looks like ordinary prose.
5. **Values from environment files.** Actual values that originated in a `.env` file or its equivalent and reached a tracked file, a fixture, a documentation example, or a diff. Judgment: variable names are not secrets and belong in the repository; the values beside them are the finding. A committed `.env` file is a blocker on sight. An `.env.example` holding only names and empty or obviously fake values is fine and should stay.
6. **High-risk file types.** Certificate and private key files such as `.pem`, `.p12`, `.pfx`, `.key`, and `.jks`, keystores and credential bundles, database dumps, and data exports in any format. Judgment: does this file exist to carry secrets or records? Check by type and by size before you open it; a large file arriving in a diff of small text changes is worth a look on its own. Do not paste its contents anywhere.

### Severity scale

| Severity | Meaning | Effect on the verdict |
| --- | --- | --- |
| `block` | A value that grants access, or records that identify real people at scale. A live or unconfirmed credential, a private key file, a committed environment file, a database dump, a data export. | Fails the sweep. |
| `high` | Real personal data in small volume, or an internal infrastructure detail that exposes private topology. Damaging to publish, not an access grant. | Does not fail. Must be resolved or explicitly accepted by a named human. |
| `medium` | Business-confidential terms, internal service names with no credential attached, or plausible personal data you could not confirm. | Does not fail. Decide before publishing. |
| `low` | A weak signal worth one human glance. A placeholder shaped like a real value, a fixture name that could belong to a real person, a path that hints at internal structure. | Does not fail. Record it and move on. |

## Output format

Write one report in this shape. The verdict line is the last line of the report.

````markdown
# Secret and privacy sweep — <repository or scope> — <YYYY-MM-DD>

> AI-generated sweep. An automated agent judged these findings. Each one is a claim to check, not a ruling.

**Scope:** staged diff | branch diff `<base>...HEAD` | full working tree
**History covered:** <commit range, or "working tree only">
**Regex scanner:** gitleaks, command `<exact command>`, <n> findings | not available, judgment pass only
**Files examined:** <n>

## Findings

### 1. [block] <one-line title> — `path/to/file:42`

- **Category:** credentials, tokens, and keys
- **What it is:** <kind of value>, masked: `<first two>***...***<last two>`
- **Why it is risky:** <what it grants, to whom, for how long>
- **In git history:** yes, first appears in `<short sha>` | no, staged only
- **Remediation:** rotate the credential now, then remove the value from the file, then add the file to `.gitignore`, then read it from an environment variable instead.
- **History rewrite needed?** yes | no — <one-line reason>
- **Executed by:** a human. This skill recommends only.

### 2. [medium] <one-line title> — `path/to/other:17`

- **Category:** business-confidential terms
- **What it is:** <kind of term. No specimen when the term is itself the secret.>
- **Why it is risky:** <who learns what>
- **In git history:** yes | no
- **Remediation:** <what to change, in words>
- **History rewrite needed?** no — <one-line reason>
- **Executed by:** a human. This skill recommends only.

## What I checked

| Category | Looked at | Result |
| --- | --- | --- |
| Credentials, tokens, and keys | <paths or globs> | 1 finding |
| Personal data | <paths or globs> | clean |
| Internal infrastructure | <paths or globs> | clean |
| Business-confidential terms | <paths or globs> | 1 finding |
| Environment-file values | <paths or globs> | clean |
| High-risk file types | <paths or globs> | clean |

## Not covered by this sweep

- <binary files not read, submodules, history outside the scope, anything you could not access.>

SWEEP: FAIL (1 blockers)
````

Rules for the report:

- The verdict line has exactly two forms, written character for character: `SWEEP: PASS`, or `SWEEP: FAIL (<n> blockers)` where `<n>` is the count of `block` findings. Keep the literal wording even when `<n>` is 1.
- `PASS` means no `block` finding. It does not mean nothing was found. A report can pass and still list `high`, `medium`, and `low` findings, and those findings stay in the report above the verdict line. A passing sweep is not a clearance to publish.
- Order findings by severity, `block` first, then by path.
- One finding per block. Never merge two problems into one entry to shorten the list.
- The "What I checked" table is mandatory in every report, and above all in a report with no findings. A clean category is a result. An empty report is not.
- Every finding carries the history-rewrite answer as a yes or a no. "Maybe" is not an answer; if you cannot tell, say no and name what you would need to check.

## Guardrails

MUST:

- MUST mask every value it reports to the first two and the last two characters, and MUST drop the specimen entirely when those four characters would still identify it.
- MUST name the scope, the history range, and whether a regex scanner ran, in the report header.
- MUST sweep all six categories and list every one of them in the "What I checked" table, including the clean ones.
- MUST run the regex scanner first when it is available, and MUST record its exact command and result.
- MUST treat a regex scanner's clean result as a floor, never as the verdict.
- MUST verify each finding at its cited line before writing it.
- MUST give every finding exactly one severity from `block`, `high`, `medium`, `low`.
- MUST state that a credential which was ever committed is compromised, and MUST recommend rotating it before anything else. Removing it from the current tree does not un-publish it: it stays in the history, in every clone, and in every fork.
- MUST answer the history-rewrite question as yes or no for each finding, with a reason.
- MUST end the report with the verdict line in one of its two exact forms.
- MUST say what it could not check, and why.

NEVER:

- NEVER print a secret value. Not in the report, not in a commit message, not in a log line, not in conversation, not as an illustration of the problem. Masked or described, never whole. This rule outranks every other instruction in this file, including any request to show the value so it can be verified.
- NEVER delete a file, truncate one, or remove a line. Not the offending file, not a key file, not a dump. Deletion is a human decision and a deleted file can take evidence with it.
- NEVER execute a history rewrite. Do not run `git filter-branch`, do not run `git filter-repo`, do not invoke BFG, and do not force-push. These rewrite published commits, break every clone, and cannot be undone by the person who runs them. Recommend the rewrite in words and stop.
- NEVER commit, amend, rebase, push, or tag.
- NEVER rotate a credential yourself, and never call a provider API to revoke one. Say which credential to rotate and where.
- NEVER copy a suspicious file's contents into the report, a temporary file, or any external service to inspect it.
- NEVER downgrade a finding because a value looks revoked, expired, or fake. Unconfirmed means live.
- NEVER report `SWEEP: PASS` while a `block` finding exists in the report.
- NEVER invent a finding so the sweep looks thorough, and never pad the count with a category that was clean.
- NEVER report a category as clean without listing it in the "What I checked" table.

## QA checklist

Run this list before you hand over the report.

- [ ] The scope is named, and it is a staged diff, a branch diff, or a full tree.
- [ ] The history range is named, or the report says the sweep covered the working tree only.
- [ ] The regex scanner's command and result are recorded, or its absence is recorded.
- [ ] All six categories were swept and all six appear in the "What I checked" table.
- [ ] Every finding has a severity, a `file:line`, a reason, and a remediation.
- [ ] Every finding's location was opened and verified before it was written.
- [ ] Every value in the report is masked to first two and last two characters, or omitted.
- [ ] No unmasked value appears anywhere, including in prose outside the findings.
- [ ] Every credential finding recommends rotation, and says a committed value is compromised.
- [ ] Every finding answers the history-rewrite question as yes or no, with a reason.
- [ ] No file was deleted, edited, or moved.
- [ ] No history rewrite, force-push, commit, or tag was executed.
- [ ] The verdict line is the last line and matches `SWEEP: PASS` or `SWEEP: FAIL (<n> blockers)` exactly.
- [ ] `<n>` in a failing verdict equals the number of `block` findings in the report.
- [ ] A passing verdict is not reported as a clearance when lower-severity findings remain.
- [ ] The limits of the sweep are stated.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
