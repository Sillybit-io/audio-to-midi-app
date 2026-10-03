## Prompt

> Audit the AI surfaces in `skills/review/` for prompt-engineering health. Keep it to the three frontmatter `description` fields — line 3 of each `SKILL.md` — and nothing else. The target model is `claude-opus-5`.

## Without skill

An agent with no skill loaded reads the three files and answers in the register the request invites: a tidy per-file verdict followed by a short list of improvements. Nothing in it is dishonest. It is confident, it is readable, and a reviewer skimming it would accept it.

````markdown
### AI surface review — skills/review/

I read the frontmatter descriptions on all three review skills. Overall these
are in good shape — they are clear, they explain what each skill does, and they
set boundaries.

**ai-review** — Clear and descriptive. States the persona, the seven review
axes, and the hard limits (never edits code, never approves or merges). Good.

**pr-description** — Well structured. Enumerates everything the skill produces
and closes with an explicit scope limit. Good.

**review-response** — Thorough. Covers the four-way classification and the
approval gate before anything is posted. Good.

**Suggestions**

1. All three descriptions run to several hundred characters. Consider trimming
   them to one or two sentences so they are easier to scan.
2. The trigger-phrase lists are repetitive and could be cut down.
3. Consider adding a short usage example to each description.

Overall the AI surfaces here look healthy. No blocking issues.
````

Three things are absent, and one thing is wrong.

Absent: no checklist is named, so there is no way to tell what the pass was measured against; no finding carries a severity, so a reader cannot sort by what to fix first; and there is no accounting of what was examined, so "looks healthy" covers the surfaces that were read and the ones that were not, indistinguishably.

Wrong: suggestion 1 recommends cutting on length alone. The upstream checklist's keep list rules that out in as many words — "Cruft != length. The harm comes from specific outdated instructions, not from volume. Never justify a deletion by character count alone." Acting on it would shorten three descriptions that are 716, 843, and 889 characters against a 1024-character cap, none of which is over budget, and would strip routing text from skills that the same checklist notes already under-trigger.

And the one defect actually present on this surface goes unmentioned. Finding it requires reading each description against the body of its own skill, which a per-file skim does not do.

## With skill

Following ai-audit against the identical three fields runs the research step before any judgement is made. Mastra is skipped because `package.json` declares no dependency at all. The two Anthropic pages, the prompt-engineering overview and the model deprecations page, both return 200; neither serves an `etag`, so each is recorded by its UTC fetch timestamp. The upstream `model-migration.md` is fetched because a Claude model is the target, and its `gh api` handle is a commit sha. The OpenRouter top thirty by weekly usage is fetched with its UTC timestamp, and the per-model lookup for `anthropic/claude-opus-5` returns 200 with a null `expiration_date`. The checklist fetch then returns the same sha the previous run recorded, and every quoted checklist phrase is re-checked against the freshly fetched file rather than assumed. The inventory is derived from `find skills/review -name SKILL.md`, which lists three files, and gains a Target-model row because step 7 judges the target as well as every routed model. That judgement, made only from the fetched pages, finds the target current and fit on every source, and a newer same-author entry at a lower price in the same top thirty, which the step-7 mapping files as `minor`. Three findings, all `minor`, no surface clean.

````markdown
# AI health audit — silly-skills — 2026-09-26

> AI-generated audit. An automated agent read this project's AI surfaces and wrote these findings. Each item is a claim to check, not a verdict.

**Scope:** the three `description` fields at line 3 of `skills/review/ai-review/SKILL.md`, `skills/review/pr-description/SKILL.md`, and `skills/review/review-response/SKILL.md`
**Target model:** `claude-opus-5` — resolved from request
**Checklist:** upstream prompt-audit at `53048666b05b4799081517d00e09e0a2dd688678`, kind `sha`
**Mastra audit:** skipped, dependency absent
**Sources:**

- Mastra docs: skipped, dependency absent
- Vendor guidance (Anthropic): `https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/overview` (200), `https://platform.claude.com/docs/en/about-claude/model-deprecations` (200) — no `etag` served; UTC fetch timestamps 2026-09-26T14:17:54Z and 2026-09-26T14:17:55Z, kind `timestamp`
- Upstream model-migration: `33375500bcea98d610eb30ce10ac4e59b89c390d`, kind `sha`
- OpenRouter catalogue: top 30 by weekly usage — 2026-09-26T14:17:58Z; lookups: `anthropic/claude-opus-5` — 200

## Health summary

| Area | Verdict | critical | major | minor | info |
| --- | --- | --- | --- | --- | --- |
| Prompts | Out of scope this run. No prompt literals were read. | 0 | 0 | 0 | 0 |
| Skills | Three routing descriptions read. One systemic pattern across all three, one contract mismatch on one. | 0 | 0 | 2 | 0 |
| Config files | Out of scope this run. | 0 | 0 | 0 | 0 |
| Tool descriptions | Out of scope this run. No MCP or tool definitions in scope. | 0 | 0 | 0 | 0 |
| Models | Target model current and fit on every fetched source. A newer same-author entry at a lower price sits in the fetched top thirty. | 0 | 0 | 1 | 0 |

## Inventory

| Surface | Path | Read |
| --- | --- | --- |
| Skill routing description | `skills/review/ai-review/SKILL.md:3` | yes |
| Skill routing description | `skills/review/pr-description/SKILL.md:3` | yes |
| Skill routing description | `skills/review/review-response/SKILL.md:3` | yes |
| Target model | `claude-opus-5` — resolved from request; no routed model pin inside the audited scope | yes |

## Findings

### 1. [minor] Trigger-case enumeration in all three routing descriptions — `skills/review/ai-review/SKILL.md:3`

- **Area:** skills
- **Evidence:** each description closes on a run of near-synonymous example queries. `ai-review:3` lists six — "review this PR, review this merge request, act as another developer and review this, do an AI code review, give me a second opinion on this diff, or tell me what is wrong with this branch". `pr-description:3` lists eight and `review-response:3` lists five, in the same shape.
- **Checklist item:** Group 2, Brittle skill files — trigger-case enumeration. "Descriptions ride in every request; enumeration taxes every token budget and generalizes worse than intent categories."
- **Why it matters:** the cost is generalization, not size. A user who types "can you look over this branch before I open the PR" matches no listed phrase on any of the three, and the router has to fall back to the first sentence anyway. Against the target model the enumerated list earns little that the opening sentence does not already carry, and it is paid on every request.
- **Counter-consideration, recorded rather than suppressed:** keep-list item 6 protects load-bearing trigger text, and Group 3 states that skills currently under-trigger. Both cut against this finding. What survives them is that intent categories are being proposed as a replacement for the enumeration, not as a deletion of it — routing strength is not reduced. The usual corroborating signal is also absent here: the checklist's tell is "descriptions that only ever grow in git history", and these three have carried the same text since `0.1.0`. That absence is why this is filed `minor` and not higher.
- **Proposed change:** replace each enumerated run with two or three generalized intent categories, keeping the opening capability sentence and the closing scope limit untouched. The root cause sits outside this scope: `skills/workflow/skill-writer/SKILL.md` step 5 instructs every author to "list the trigger phrases a user would actually type", so the pattern will regenerate on the next skill unless that house rule is revisited first. Not applied.

### 2. [minor] Description promises a diagram the skill itself makes conditional — `skills/review/pr-description/SKILL.md:3`

- **Area:** skills
- **Evidence:** the description states that the skill "draws a Mermaid diagram of what actually changed", unconditionally, in a list of seven outputs. The skill body contradicts it in four places: `:44` — "Skip the diagram for a trivial change"; `:86` — "Omit the diagram for a trivial change such as a one-line fix"; `:166` — "MUST keep the diagram near 20 nodes or fewer, and drop it for a trivial change"; `:194` — the QA checkbox "The diagram is omitted when the change is trivial".
- **Checklist item:** Group 3 — contract accuracy. "Description must precisely match actual behavior (a contract/behavior mismatch sends the model down paths no prompt text can fix)." The rubric is written for tool descriptions; a skill's frontmatter `description` is the same kind of text, read before the body is loaded.
- **Why it matters:** the description is the only text available at routing time. An agent that loaded this skill for a one-line fix has been told to expect seven sections and will find the body withholding one of them, which is the point at which a model either invents the missing section or stalls on the discrepancy. The two sibling descriptions have no equivalent gap: `ai-review:3` claims it "posts the review through gh or glab, or writes a report file when neither tool is available", which matches its posting modes at `:46` and `:117`; `review-response:3` claims "nothing is posted until you approve the text" and that it "never resolves threads", which match `:48`, `:236`, `:242`, and `:244`.
- **Proposed change:** make the clause conditional in the description — "draws a Mermaid diagram of what actually changed, unless the change is trivial" — so the routing text and the body state the same contract. Nine words. Not applied.

### 3. [minor] A newer same-author entry at a lower price sits in the fetched catalogue — `claude-opus-5` (target)

- **Area:** models
- **Evidence:** `anthropic/claude-opus-5` is the target model, resolved from the request; nothing inside the three-field scope routes to it. Vendor lifecycle page, fetched 200: the row reads "claude-opus-5 Active N/A Not sooner than July 24, 2027". Upstream `model-migration.md` at `33375500bcea98d610eb30ce10ac4e59b89c390d`: the ID appears in neither the "Retired Model Replacements" table nor the "Deprecated Models (retiring soon)" table, and the destination-model table names `claude-opus-5` as the current Opus target. OpenRouter lookup, 200: `expiration_date: null`, `context_length: 1000000`, `architecture.input_modalities: ["text", "image", "file"]`, `pricing.prompt: "0.000005"`, `pricing.completion: "0.000025"`, `created: 1784912544`, rank 26 of 30. Same author, later entry in the same top thirty: `anthropic/claude-opus-5.5`, `created: 1790094732`, rank 30, `context_length: 1000000`, identical `input_modalities` and `supported_parameters`, `pricing.prompt: "0.000004"`, `pricing.completion: "0.00002"`, `expiration_date: null`; its vendor row reads "claude-opus-5-5 Active N/A Not sooner than September 22, 2027".
- **Checklist item:** model currency and fit (step 7) — better option.
- **Why it matters:** nothing is urgent. The target is current on every fetched source, and the three descriptions are plain routing text that either model reads without any modality or context constraint coming into play. What the data shows is a successor from the same author, four days old at fetch time, priced lower per token on both input and output, with no fit constraint lost. The upstream migration document does not yet mention it and still names `claude-opus-5` as the default upgrade target, which is why this is filed `minor` and not as a recommendation to move today.
- **Proposed change:** re-run this audit with `claude-opus-5.5` as the target once the upstream migration document carries a section for it, and compare the two verdicts on finding 1, since which model reads a description decides what counts as inert filler. Not applied.

## What I checked

| Surface | Checklist areas | Result |
| --- | --- | --- |
| `skills/review/ai-review/SKILL.md:3` | Group 2 brittle skill files; Group 3 contract accuracy; keep list items 2 and 6 | finding 1 |
| `skills/review/pr-description/SKILL.md:3` | Group 2 brittle skill files; Group 3 contract accuracy; keep list items 2 and 6 | findings 1 and 2 |
| `skills/review/review-response/SKILL.md:3` | Group 2 brittle skill files; Group 3 contract accuracy; keep list items 2 and 6 | finding 1 |
| `claude-opus-5` (target) | model currency and fit | finding 3 |

Checked and deliberately not raised: description length. The three fields measure 877, 770, and 886 characters against the validator's 1024-character cap. Keep-list item 2 rules out a finding grounded in volume, and none of the three is over budget.

## Not covered by this audit

- Every AI surface outside the three named fields. The bodies of the three `SKILL.md` files were opened only to verify whether each description matches the behaviour it promises; they were not themselves audited.
- The other six skills in this repository, `AGENTS.md`, `.cursor/rules/`, `opencode.json`, `.claude/` settings, and CI workflow text. All out of the requested scope.
- Whether the enumerated trigger phrases actually under-perform intent categories on this repository's routing. Finding 1 rests on the upstream checklist's reasoning, not on a trigger eval run here. No such eval exists in the project.
- No runtime-assembled prompt and no routed model pin exist inside the three-field scope, so the assembly, stored-values, and Routed-model inventory rows are empty by scope, not by omission.
- Vendor guidance for providers other than Anthropic. No OpenAI or Google model is routed or targeted, so neither vendor's pages were fetched.
````

Two notes on how the guided run reached that output. The report is shown here for illustration only; a real run writes it to `reports/ai-audit-2026-09-26.md` inside the audited project and nothing else changes there. And the checklist fetch succeeded, so the "Checklist areas" column names real sections of the upstream file — `all ten` belongs there only when the fetch failed and the skill's embedded fallback was the checklist in play.
