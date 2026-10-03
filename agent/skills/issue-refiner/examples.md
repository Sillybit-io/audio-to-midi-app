## Prompt

> Make this ticket actionable before we plan on Thursday.

The ticket as fetched — a GitHub issue, `#412`, description plus both comments:

```text
Title:  Search results are wrong for some users
State:  open
URL:    <elided>/issues/412

Body:
Search is returning the wrong results for some people. A few of them have complained. Can we fix this before the end of the month?

--- comments (2) ---

@reporter-a:
I tried it again just now — when I search for a two-word phrase I get back
things that only have one of the words in them. Doesn't happen every time
though.

@teammate-b:
Is this the same thing as the complaint from last week, or something different?
```

This ticket is invented for this example. The number identifies no real issue, there is no repository behind it, and `@reporter-a` and `@teammate-b` are placeholders rather than people. Both branches below are given exactly this input.

## Without skill

The request is "make this actionable", and an agent with no skill loaded does exactly that. It reads the ticket, forms a theory of what is happening, and writes the theory up as a plan. The output is well-organised, confident, and mostly not in the ticket.

````markdown
## Search results are wrong for some users — refined

**Problem**

Multi-word search queries are returning results that match only one of the
search terms instead of all of them. This is hitting users on the web app and
has already generated several support complaints.

**Likely root cause**

The search terms are being combined with OR rather than AND before the query
reaches the index, so any document containing a single term comes back. The
intermittency is most likely caching — users who hit a warm cache still see the
previous, correct result set.

**Acceptance criteria**

- [ ] A multi-word query returns only results that contain all of the search terms.
- [ ] Behaviour is consistent across page reloads and across Chrome, Firefox, and Safari.
- [ ] Verified on both the free and the paid tier.
- [ ] Search results return in under 500 ms.
- [ ] Single-word search is unchanged.

**Estimate:** small. Probably a one-line change in the query builder plus a regression test.

**Priority:** raise to high — the reporter has asked for it by the end of the month.
````

Nothing in that brief is marked uncertain, and eight of its statements cannot be traced to the ticket:

1. **The root cause.** Nobody has opened the query builder. OR-versus-AND is a guess, and it arrives labelled "likely root cause" rather than as a question.
2. **The cache theory.** Invented to explain "doesn't happen every time". The ticket offers no evidence for it, and it is the kind of claim that sends the first day of work to the wrong layer.
3. **The AND rule as a requirement.** The ticket never says a two-word query should require both words.
4. **"the web app".** The reporter did not say where they searched.
5. **The three browsers.** No browser is named anywhere in the ticket.
6. **Free and paid tiers.** The ticket does not mention tiers, and nothing establishes that this product has them.
7. **The 500 ms budget.** Nobody reported slowness. A latency requirement has been attached to a correctness bug.
8. **The priority change.** This is metadata, and the brief moves it on the strength of a deadline nobody has claimed.

Items 3 through 7 are the expensive ones, because four of the five acceptance criteria now state a requirement the reporter never gave. A reader opening this ticket next week cannot tell which criteria came from the reporter and which came from the agent — an invented criterion and a real one look identical once they are written down, and the assignee builds to both. Item 3 is the worst of them: it silently decides that the reporter's report is a defect, which is the one thing the ticket does not establish.

## With skill

issue-refiner is given the identical ticket. It reads the description and both comments, and before writing anything it checks the `url` path segment — `/issues/`, not `/pull/` — because `gh issue view` resolves a pull request number as happily as an issue number, and writing a brief into a pull request would overwrite the author's description. Then it sorts every statement into settled and not-settled. The second pile is larger than the first, and none of it is allowed to become an acceptance criterion.

This is the body it builds. The brief goes first; the reporter's own text survives underneath.

````markdown
## Refined brief (issue-refiner)

### Problem

Search returns results the reporter judges wrong. The one reproduction on the ticket is a two-word query that came back with items containing only one of the two words, and the reporter says it does not happen every time. More than one person has raised it; the ticket does not say how many, and `@teammate-b`'s question about whether last week's complaint is the same issue was never answered. The reporter has asked for a fix before the end of the month.

### Desired outcome

A multi-word query returns the same result set every time it is run, and the rule the search applies to multi-word queries is written down, so a tester can predict a query's result set before running it. Whether the reporter's specific case is a defect is settled on this ticket rather than assumed.

### Acceptance criteria

- [ ] The reporter's two-word query, run twice in succession by the same user, returns the same result set both times.
- [ ] The rule the search applies to a multi-word query is recorded on this ticket, and a tester can use it to predict the result set for a query before running it.
- [ ] The case in `@reporter-a`'s comment — a two-word query returning items containing only one of the two words — has a written verdict on this ticket: defect or intended behaviour, with the reason.
- [ ] A test covers the reporter's query and fails if its result set changes.

### Out of scope

- Ranking and relevance ordering. "Wrong results" reads as a ranking complaint to some readers; the only reported symptom is which items came back, not the order they came back in.
- Every search entry point other than the one the reporter used, until question 3 names it.
- Search latency. Nothing in the ticket reports slowness.

### Risks / dependencies

- The symptom is intermittent, so one successful query does not confirm a fix. This blocks acceptance criteria 1 and 4 until there is a reproduction that fails reliably, or a recorded failure rate.
- The matching rule for multi-word queries applies to everyone, not only the people who complained. A narrow fix to the reported case and a change to the rule are different-sized changes with different blast radii, and question 2 decides which one this ticket is asking for.
- The end-of-month date has no owner on the ticket. If it tracks an outside commitment it constrains scope; if it does not, it should not. See question 5.

### Test notes

- Reproduction to start from, taken from `@reporter-a`'s comment: run a two-word query and check whether the returned items contain both words or only one.
- Run each query several times and record every run, including the ones that behave correctly. The report says it does not happen every time, so a single passing run is not evidence and the negative runs are part of the data.
- Keep the reporter's exact query. "A two-word query" is a category; the query they ran is the evidence.
- Two answers are needed before this can be tested properly: which users are affected (question 1) and which search entry point was used (question 3).

### Open questions for the reporter

1. Which users are affected, and what do they have in common? I would otherwise assume any user running the same query sees the same thing — please confirm, or name the group.
2. For a two-word query, must a result contain both words, or is one enough when the result is otherwise a good match? I would otherwise assume both words are required. This decides whether your report is a defect or the current design, so please answer it before anything is estimated.
3. Where did you search — which page, or which search box? I would otherwise assume the main search.
4. "Doesn't happen every time": did anything differ between the attempts that looked right and the ones that did not — a different query, a different day, signed in versus signed out? I would otherwise assume nothing differed and the variation is inside the system.
5. Is "before the end of the month" tied to something specific, or is it a preference? I would otherwise treat it as a preference and not cut scope for it.
6. How many people have reported this, and do they all describe the two-word symptom? `@teammate-b` asked whether last week's complaint is the same issue and nobody answered. I would otherwise assume the other reports match yours.

## Original request

Search is returning the wrong results for some people. A few of them have complained. Can we fix this before the end of the month?
````

Then the run report, which goes to the user and not to the ticket:

````markdown
## Ticket refined — #412

- Platform: `GitHub`. Fetched with: `gh issue view 412 --json number,title,body,url,state` and `gh issue view 412 --comments`.
- Verified issue, not a pull request: `yes`.
- Sources read: description plus `2` comments.
- Body state before the write: `first run`.
- Write-back mode: `description update`.
- Original text: `130` characters, preserved verbatim, compared before and after.
- Metadata: status, assignee, priority, and labels unchanged.
- Acceptance criteria: `4`, each testable. Open questions raised: `6`.
- Confirmation gate: `not required, platform shows edit history`.
````

Three things in that run are worth naming.

**The write-back is described here, not performed.** The mode is `description update`: GitHub's issue description is editable and GitHub shows edit history on an edited body, so the capability table sends the brief into the description rather than into a comment, and the confirmation gate does not apply. The command would be `gh issue edit 412 --body-file refined-brief.md` — exactly one content flag, with no `--add-label`, no `--add-assignee`, and no `--milestone`, and with `--body-file` written in full because `-F` abbreviates `--body-file` here, `--field` on `gh api`, and `--output` on `glab`. Had the token been read-only or the description not editable, the rule is to post the same brief as a comment with `gh issue comment 412 --body-file refined-brief.md` and record that in the run report. No command was run for this example. The ticket is invented and has no tracker behind it, so there was nothing to write to; the body and the run report above are the artefacts the skill produces, shown as it would produce them.

**The comments are read and not moved.** `## Original request` holds the description only, byte for byte. Both comments were read — between them they supply the reproduction, the intermittency, and question 6 — and both stay where their authors left them. A description edit does not touch them, which is why the comment count in the run report is the only evidence that they were read at all.

**Four criteria and six questions is the honest ratio here, not a thin brief.** The ticket settles less than it appears to. Reaching ten criteria would have required roughly six inventions, and each one would have been indistinguishable from a requirement the reporter gave. The criterion a reader most expects — "a two-word query returns only results containing both words" — is deliberately absent, because the ticket never says so. It is question 2 instead. If the reporter answers "both words are required", that sentence becomes an acceptance criterion on the next pass and carries the reporter's authority rather than the agent's guess; if they answer "one is enough when it ranks well", the ticket was never a defect, and the four days of work the baseline brief had already scoped were about to be spent building the wrong rule.
