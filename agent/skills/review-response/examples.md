## Prompt

> Here are the review comments on my PR, help me respond.

The pull request is #14 on this repository, `feat(validate): require a non-blank examples.md for every skill`. It adds the `MISSING_EXAMPLES` error code to `scripts/validate.ts` and four cases to `scripts/validate.test.ts`. Four comments came back, across three surfaces:

```text
[inline] scripts/validate.ts:509 — @reviewer-a
readTextFile returns null for four different reasons: the path is not a regular
file, it is larger than MAX_SCAN_BYTES, it has a NUL byte in the first 8 KiB, or
the stat threw. This message leads with "is missing". When the file is open in
front of you, being told it is missing sends you hunting for the wrong problem.
Please separate "not there" from "there but unreadable".

[inline] scripts/validate.ts:500 — @reviewer-a
This block would read better as its own validateExamples(root, category,
dirName, errors). validateSkill already covers frontmatter, name, version,
category and footer; a fourth concern bolted to the top of it makes the function
harder to follow.

[review summary, COMMENTED] — @reviewer-b
Non-blank is a thin bar for a file the house style says must carry ## Prompt,
## Without skill and ## With skill in that order. As written, a skill can ship an
examples.md containing the word "todo" and pass. Either check the three sections
here, or say in the error message that structure is not checked.

[conversation] — @reviewer-c
What happens if someone drops a SKILL.md straight into skills/review/? Do they
get a MISSING_EXAMPLES for skills/review/examples.md on top of the layout error?
That pair would be confusing.
```

## Without skill

An agent with no triage contract writes replies that are polite, ordered, and prompt. It answers all four, it does not argue, and it sounds like a reasonable colleague. The problem is not the tone. It is that the agent has agreed to everything and checked nothing.

````markdown
Thanks for the review! Responses below.

**On the error message:** Good catch — you're right that it's misleading. I'll fix it.

**On extracting the helper:** Sure, that makes sense. I'll pull it out into its own
function.

**On checking the section structure:** Agreed, non-blank is too weak. I'll add the
section check to the validator.

**On a misplaced SKILL.md:** I think that should be fine — the layout check runs
first, so it shouldn't be an issue.

Will push an update shortly.
````

Measured against what this skill requires, that set of replies falls short in seven ways:

- No comment carries a classification, so nothing in the output separates the one real defect from the one preference. All four arrive at the reviewer with equal weight.
- The second comment is a preference about function structure. Taking it is a legitimate choice. Agreeing to it in four words, with no reason offered in either direction, is the silent caving this skill exists to prevent.
- The third comment asks for an expansion of what the validator owns. "Agreed, I'll add the section check" commits the author to a scope decision the author never actually made, inside a pull request that was about presence, not structure.
- The fourth comment is a question, and it is answered with "I think" and "shouldn't be an issue". The walk in `validate()` settles it in one read. A guess was published instead.
- No reply names a file, a line, or a specific change, so the reviewer has to re-review the whole diff to discover what "I'll fix it" turned into.
- There is no count and no checklist. Four comments were in fact answered here, but nothing in the output proves it, so neither the author nor the reviewer can tell a complete pass from a partial one.
- The four comments were pasted in by hand. Nothing in this reply set tells the author that a review summary body is a separate surface from the conversation, so the next time they fetch comments themselves with `gh pr view --comments`, @reviewer-b's comment will not be in the list at all.

## With skill

Following review-response against the same four comments produces a plan first and reply text second. Every cited location was opened before its comment was classified, which is what moves comments 1 and 4 off their first-impression readings.

````markdown
## Review response plan

**Target:** PR #14 `feat(validate): require a non-blank examples.md for every skill` — 4 comments across 4 threads.
**Surfaces fetched:** conversation 1, inline 2, review summaries 1.
**Already resolved upstream:** 0 threads, skipped.

### Response plan

| # | Comment | Type | Planned action | Drafted reply |
| --- | --- | --- | --- | --- |
| 1 | "This message leads with \"is missing\" ... Please separate \"not there\" from \"there but unreadable\"." — `scripts/validate.ts:509` (@reviewer-a) | must-fix | Split the null branch into an existence test and an unreadable test, each with its own message. Add the missing test case. | You're right, the message names the wrong cause — full text below. |
| 2 | "Either check the three sections here, or say in the error message that structure is not checked." — review summary (@reviewer-b) | valid-suggestion | Take the message half now. Raise the section check as its own decision rather than settling it in this PR. | Agreed that non-blank is a thin bar — full text below. |
| 3 | "This block would read better as its own validateExamples(root, category, dirName, errors)." — `scripts/validate.ts:500` (@reviewer-a) | opinion | Push back. Keep the block inline, because its position is load-bearing. | I'd rather keep it where it is, because the ordering is load-bearing — full text below. |
| 4 | "Do they get a MISSING_EXAMPLES for skills/review/examples.md on top of the layout error?" — conversation (@reviewer-c) | question | Answer from the walk in `validate()`. No code change. | No — you get the layout error only, and nothing else. |

### Drafted replies

#### 1 — `scripts/validate.ts:509` — must-fix

> readTextFile returns null for four different reasons ... This message leads with "is missing". When the file is open in front of you, being told it is missing sends you hunting for the wrong problem. Please separate "not there" from "there but unreadable".

You're right, the message names the wrong cause. I'll split the null branch in two: an existence test that keeps the current "examples.md is missing" wording, and a second branch for a file that is present but `readTextFile` refuses, which will say that and name the reason — over the 1 MiB `MAX_SCAN_BYTES` at `scripts/validate.ts:96`, or not UTF-8 text. Both keep the `MISSING_EXAMPLES` code, so CI behaviour and the error count do not change. I'll also add a fifth test case for present-but-unreadable, which none of the four new cases covers today.

#### 2 — review summary — valid-suggestion

> Non-blank is a thin bar for a file the house style says must carry ## Prompt, ## Without skill and ## With skill in that order. As written, a skill can ship an examples.md containing the word "todo" and pass. Either check the three sections here, or say in the error message that structure is not checked.

Agreed that non-blank is a thin bar, and you are right that an `examples.md` containing "todo" passes today. I'm going to split your two options rather than pick one. The message half is cheap and lands in this PR: the error will say that only presence is checked. The section check is not cheap — it would move the `examples.md` contract in `skills/workflow/skill-writer/SKILL.md` from something review enforces to something the validator enforces, and that is a change in what this script owns. I don't want to decide that inside a PR scoped to presence, so I'll open a follow-up issue for it and link this thread there.

#### 3 — `scripts/validate.ts:500` — opinion

> This block would read better as its own validateExamples(root, category, dirName, errors). validateSkill already covers frontmatter, name, version, category and footer; a fourth concern bolted to the top of it makes the function harder to follow.

I'd rather keep it inline, and the reason is the position rather than the size. The block has to run before the `readTextFile` on the `SKILL.md` and the early return underneath it: that branch pushes `code: "FRONTMATTER"` at `scripts/validate.ts:523` and returns `null`, so a skill whose `SKILL.md` is unreadable would never be told its `examples.md` is missing as well. The comment two lines above the block records exactly that. Extracting it into `validateExamples` preserves the behaviour today but moves the ordering constraint to the call site, where the next person to reorder `validateSkill` has nothing in front of them to warn against it. `validateSkill` also already owns every per-skill-directory check, so `examples.md` is not a foreign concern inside it. If the function grows again I'll revisit, and I'd rather split it on a seam that is not order-dependent.

#### 4 — conversation — question

> What happens if someone drops a SKILL.md straight into skills/review/? Do they get a MISSING_EXAMPLES for skills/review/examples.md on top of the layout error? That pair would be confusing.

No — you get the layout error only, and nothing else. `validate()` tests `parts.length !== 4` before it calls `validateSkill`: `skills/review/SKILL.md` splits into three parts, so it takes the `LAYOUT` branch at `scripts/validate.ts:715` and `continue`s, and the `validateSkill` call at line 725 is never reached. `MISSING_EXAMPLES` can only be raised for a path that already passed the layout check, so the confusing pair you're describing cannot occur.

### Resolution checklist

- [ ] 1 — `scripts/validate.ts:509` — must-fix — addressed in code
- [ ] 2 — review summary — valid-suggestion — needs author decision
- [ ] 3 — `scripts/validate.ts:500` — opinion — replied only
- [ ] 4 — conversation — question — replied only

### Counts

must-fix 1 · valid-suggestion 1 · opinion 1 · question 1 — total 4, which equals the 4 comments fetched.
````

Three of those outcomes are only reachable by opening the code first. Comment 1 reads like a wording nit and is a real defect, because `readTextFile` at `scripts/validate.ts:237` returns `null` on a size check as well as on a missing file. Comment 4 reads like a bug report and is a question with a "no" answer, settled by the `continue` above the `validateSkill` call. Comment 2 reads like a defect and is a scope decision, so it goes to the author marked `needs author decision` rather than being agreed to in passing. Nothing is posted at this point: the plan and all four replies go to the user first, and the posting mode runs only after they approve the text.
