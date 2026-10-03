---
name: issue-refiner
description: Turns a vague ticket into a decision-complete brief and writes that brief back to the ticket itself, so the tracker stays in sync instead of the refinement living in a chat log. It fetches the ticket through a Linear MCP tool, gh, glab, or a Jira tool, then writes Problem, Desired outcome, Acceptance criteria, Out of scope, Risks and dependencies, Test notes, and Open questions for the reporter. The brief goes above the original text, and the original survives verbatim under an "Original request" heading. Use when you refine this vague ticket, turn this issue into a decision-complete brief, flesh out this ticket and update it, write acceptance criteria for this ticket, make this issue actionable before planning, or sync a refined brief back to Linear, Jira, GitHub, or GitLab. Unknowns become open questions for the reporter, never invented acceptance criteria.
license: CC-BY-ND-4.0
metadata:
  version: "0.1.0"
  category: workflow
---

# issue-refiner

## Purpose

issue-refiner takes a ticket nobody can start work on and turns it into a brief somebody can. It names the problem, states the outcome, writes acceptance criteria a tester can check, and parks every genuine unknown in a question list addressed to the reporter. Then it writes the brief back to the ticket. The write-back is the point. A refinement that lives in a chat window helps one person once, while the next person to open the ticket still finds the original two-line complaint. A refinement written into the ticket is what the assignee reads, what the reviewer checks the work against, and what the reporter corrects. The original text always survives underneath, because the reporter's own words are the evidence of what they actually asked for, and a brief that quietly replaces them turns an interpretation into a fact.

## When to use / when NOT to use

Use issue-refiner when you:

- Have a ticket too vague to estimate, start, or test, and you want it made actionable.
- Need acceptance criteria written before planning, so the work has a definition of done.
- Want the refinement stored on the ticket instead of in a chat log or a side document.
- Have a bug report missing its reproduction, its expected behaviour, or its scope.
- Want the unknowns in a ticket separated from the settled parts and sent back to the reporter.

Do NOT use issue-refiner when you:

- Want the work done. This skill writes a brief; it changes no code and opens no branch.
- Want the ticket triaged, prioritised, assigned, or scheduled. It does not touch those fields.
- Have a ticket that is already decision-complete. Rewriting a clear ticket adds noise and buries its history.
- Want a pull request described. That is `pr-description`'s job.
- Cannot reach the tracker and the user cannot paste the ticket. Without the original text there is nothing to preserve and nothing to refine.

## Workflow

1. Identify the ticket and the platform. Take the identifier from the user, or from the branch name when it carries one.
2. Fetch the ticket using the preference order below. Fetch the description and the comments, not the description alone.
3. Confirm the thing you fetched is an issue. On GitHub the issue commands also resolve pull requests, so check the returned URL before going further.
4. Read the whole thread. Reporters routinely put the reproduction, the deadline, or the real requirement in a comment rather than in the description.
5. Separate what the ticket settles from what it leaves open. Every statement you cannot trace to the ticket text or a comment is an unknown.
6. Draft the seven brief sections in the order given in Output format.
7. Route every unknown into "Open questions for the reporter". Never resolve one by choosing a plausible answer.
8. Decide the write-back mode from the platform capability table below.
9. Build the new body: the brief first, then `## Original request`, then the original text byte for byte.
10. Apply the confirmation gate when the platform keeps no visible edit history.
11. Write back with a command that touches the description only.
12. Verify the original text survived, compare it against what you captured before the write, then produce the run report and walk the QA checklist.

### Fetching: preference order

Try these in order and stop at the first one available. Each fetch is read-only.

| Order | Platform | Fetch the body | Fetch the comments |
| --- | --- | --- | --- |
| 1 | Linear | A Linear MCP issue-read tool | The same tool, or a comment-list tool |
| 2 | GitHub | `gh issue view <number> --json number,title,body,url,state` | `gh issue view <number> --comments` |
| 3 | GitLab | `glab issue view <id>` | `glab issue view <id> --comments` |
| 4 | Jira | A Jira CLI or MCP tool, if one is installed | The same tool |
| 5 | None of the above | Ask the user to paste the ticket text | Ask for the comments too |

Tool names differ between Linear MCP server builds and between Jira CLIs, so list the tools you actually have rather than assuming a name. No Jira command is given here because none was verified; read the help output of whichever Jira tool is present before you use it.

Two platform facts worth knowing before you fetch:

- `gh issue view <number>` accepts a pull request number and returns the pull request. The `url` field is the discriminator: an issue's URL contains `/issues/`, a pull request's contains `/pull/`. Refining a pull request as though it were an issue, then writing the brief into its description, overwrites the author's description.
- A pull request carries three separate comment surfaces, while an issue carries one. If step 3 tells you this is a pull request, stop and confirm with the user rather than continuing with a one-surface read.

### Unknowns go to open questions

An acceptance criterion is a promise that someone will check the work against it. A criterion invented to fill a gap is a promise nobody agreed to, and it is indistinguishable from a real one once it is written down. The assignee builds to it, the reviewer enforces it, and the reporter discovers weeks later that the ticket committed them to something they never asked for.

So when the ticket does not say which users are affected, what the expected behaviour is, whether an edge case is in scope, or what "fast" means, that goes in "Open questions for the reporter" as a question. Ask it in a form the reporter can answer in one line. A brief with six criteria and four open questions is more useful than one with ten criteria, four of which are guesses, because the second one hides which four.

A guess is still allowed as a guess. Write it inside the question — state what you assumed and ask the reporter to confirm — so the reader can see both the assumption and the fact that it is unconfirmed.

### Write-back: the four body states

Enumerate the state of the ticket body before you write, because each state fails differently and one of them must not be written at all.

- No `## Refined brief (issue-refiner)` heading and no `## Original request` heading: this is a first run. Write the brief, then `## Original request`, then the existing body verbatim underneath.
- Both headings present from an earlier run: replace only the content under the brief heading. Leave everything from `## Original request` onward byte-identical. Never re-wrap, re-indent, or re-quote it.
- Exactly one of the two headings present: stop, change nothing, and report it. One heading without the other means somebody edited the body by hand and you cannot tell which part is the original, so any write risks destroying it.
- Body empty: there is no original text. Write the brief and record in the run report that the body was empty. Do not create an `## Original request` section with content you supplied.

### Write-back: platform capability

| Capability | Platforms | Action |
| --- | --- | --- |
| Description is editable and the platform shows edit history | GitHub, GitLab, Linear | Update the description directly |
| Description is editable but no edit history is visible | Varies by tracker and configuration | Apply the confirmation gate, then update |
| Description is not editable, or the available token or MCP endpoint is read-only | Any | Post the brief as a comment and say so in the run report |

Linear's MCP server offers a read-only endpoint alongside the read-write one, so a connected Linear tool is not proof of write access. When the update fails on permissions, fall back to a comment rather than retrying.

### Write-back: the commands

Every command below carries exactly one content flag. That is the enforcement mechanism for the metadata guardrail: a command that only passes a description cannot change a label, an assignee, or a milestone.

| Platform | Update the description | Post a comment instead |
| --- | --- | --- |
| GitHub | `gh issue edit <number> --body-file <path>` | `gh issue comment <number> --body-file <path>` |
| GitLab | `glab issue update <id> --description-file <path>` | `glab issue note <id> --message "<text>"` |
| Linear | A Linear MCP issue-update tool, description field only | A Linear MCP comment-create tool |

Flag details that are verified and easy to get wrong:

- Write `--body-file` and `--description-file` in full. The short form `-F` means `--body-file` on `gh issue edit`, `--field` on `gh api`, and `--output` on `glab`. Three tools, three meanings, one letter.
- On both `gh issue edit --body-file` and `glab issue update --description-file`, a path of `-` reads from standard input.
- On `glab issue update`, the similar-looking `--description -` does not read standard input. It opens an editor, which hangs a non-interactive run. Use `--description-file` for file or piped input.
- `glab issue update` rejects `--description` and `--description-file` together; the two flags are mutually exclusive.
- `gh issue edit` has no flag that opens or closes an issue, because `gh issue close` and `gh issue reopen` are separate commands. It does have `--add-label`, `--add-assignee`, `--milestone`, and `--add-project`. Pass none of them.
- `glab issue update` does accept `--label`, `--assignee`, and `--milestone` in the same invocation as a description change. Pass none of them.

### The confirmation gate

When the platform keeps no visible edit history, an overwrite cannot be inspected or undone by the reporter, and a mistake is indistinguishable from data loss. So before writing, show the user the complete new body, state which platform it is going to and that the change will not be recoverable from the tracker's own history, and wait for an explicit yes. Silence is not consent, and a previous approval does not carry to a second ticket.

Keep the captured original text until the write-back is verified. It is the only copy if the write goes wrong.

## Output format

Write this into the ticket description. The brief is one H2 with seven H3 sections; the original is the second H2 and is never edited.

````markdown
## Refined brief (issue-refiner)

### Problem

<What is wrong or missing, and why it matters. Two to four sentences. Trace every claim to the ticket.>

### Desired outcome

<The state of the world once this is done, in one or two sentences. Not a task list.>

### Acceptance criteria

- [ ] <A testable statement. Someone can check it and answer yes or no.>
- [ ] <Another. Name the observable behaviour, not the implementation.>

### Out of scope

- <Something a reader might reasonably assume is included, and is not.>

### Risks / dependencies

- <A dependency, a blocking ticket, a migration, or a risk. Name what it blocks.>

### Test notes

- <How to verify this: the reproduction, the data needed, the edge cases to cover.>

### Open questions for the reporter

1. <A question answerable in one line. State the assumption you would otherwise make.>

## Original request

<The original ticket text, byte for byte, unedited.>
````

Then hand back this run report. It is a report to the user, not something written to the ticket.

````markdown
## Ticket refined — <identifier>

- Platform: `<Linear | GitHub | GitLab | Jira | pasted by user>`. Fetched with: `<tool or command>`.
- Verified issue, not a pull request: `<yes | not applicable>`.
- Sources read: description plus `<N>` comments.
- Body state before the write: `<first run | both headings present | one heading only, stopped | body empty>`.
- Write-back mode: `<description update | comment, because ...>`.
- Original text: `<N>` characters, preserved verbatim, compared before and after.
- Metadata: status, assignee, priority, and labels unchanged.
- Acceptance criteria: `<N>`, each testable. Open questions raised: `<N>`.
- Confirmation gate: `<not required, platform shows edit history | requested and granted>`.
````

## Guardrails

MUST:

- MUST preserve the original ticket text byte for byte under `## Original request`, below the brief.
- MUST place the refined brief above the original text, under `## Refined brief (issue-refiner)`.
- MUST capture the original body before writing and compare it against the ticket afterwards.
- MUST fetch the comments as well as the description, and say how many were read.
- MUST confirm a GitHub ticket is an issue and not a pull request by checking the URL path before writing.
- MUST stop and report when exactly one of the two headings is present, changing nothing.
- MUST put every unknown in "Open questions for the reporter", phrased so one line answers it.
- MUST state an assumption as an assumption, inside the question it belongs to.
- MUST write acceptance criteria that a person can check and answer yes or no.
- MUST pass exactly one content flag on the write-back command, and no metadata flag.
- MUST post the brief as a comment, and say so in the run report, when the description is not editable or the available access is read-only.
- MUST show the full new body and get an explicit yes before writing when the platform shows no edit history.
- MUST write flag names in full, because `-F` means a different thing in each of the three tools.

NEVER:

- NEVER delete, truncate, summarise, reword, or reformat the original ticket text. It survives verbatim or the run failed.
- NEVER move the original text into a comment and leave only the brief in the description.
- NEVER invent an acceptance criterion to fill a gap the ticket leaves open.
- NEVER answer an open question on the reporter's behalf, however obvious the answer looks.
- NEVER change status, assignee, priority, labels, milestone, project, due date, or estimate unless the user asks for that change in this run.
- NEVER close, reopen, lock, transfer, or delete a ticket.
- NEVER overwrite a description on a history-less platform without the user's explicit yes in this run. An earlier approval does not carry over.
- NEVER discard the captured original text before the write-back has been verified.
- NEVER treat a connected tracker tool as proof of write access. Fall back to a comment when a write is refused.
- NEVER refine and write back to a pull request through the issue commands.
- NEVER copy a credential, token, or key found in the ticket into the brief. Name where it appeared and what kind of value it is, and tell the user to rotate it.
- NEVER copy a personal email address, phone number, customer name, or account identifier into the brief. Refer to the reporter by their tracker handle.
- NEVER carry an internal hostname, a local development address, or an absolute path from your own machine into the brief.

## QA checklist

Run this list before you hand the ticket back.

- [ ] The ticket was fetched with the first available option in the preference order, and the run report names it.
- [ ] The description and the comments were both read, and the comment count is in the run report.
- [ ] A GitHub ticket was confirmed to be an issue by a `/issues/` URL, not a pull request.
- [ ] The body state was identified as one of the four cases before anything was written.
- [ ] A one-heading-only body stopped the run, and nothing was written.
- [ ] The brief has all seven sections, in the required order, under one `## Refined brief (issue-refiner)` heading.
- [ ] Every acceptance criterion is testable and answerable yes or no.
- [ ] Every unknown is an open question, and no unknown became an acceptance criterion.
- [ ] Every assumption is stated as an assumption inside its question.
- [ ] The original text sits under `## Original request`, below the brief, byte for byte identical to what was captured.
- [ ] The original text was compared before and after the write, not inspected by eye.
- [ ] The write-back command passed exactly one content flag and no metadata flag.
- [ ] Status, assignee, priority, labels, milestone, project, due date, and estimate are unchanged.
- [ ] A read-only or non-editable target resulted in a comment, and the run report says so.
- [ ] A history-less platform received an explicit yes in this run before the write.
- [ ] Flag names are written in full in every command used.
- [ ] The brief contains no credential, no personal email address, no phone number, no customer name, no account identifier, no internal hostname, and no absolute local path.
- [ ] The run report states the platform, the sources read, the body state, the write-back mode, the original-text comparison, the metadata statement, the two counts, and the confirmation status.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
