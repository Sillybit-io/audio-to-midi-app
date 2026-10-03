---
name: ai-audit
description: Runs a full read-only health audit of how a project uses AI. It inventories every AI surface, including prompts embedded in code, skill files, agent configuration files, tool and MCP descriptions, and every model ID the project references, judges whether every model the project routes to is current, fit for its task, and the best available choice, using Mastra docs, vendor guidance, and the OpenRouter catalogue it fetches before judging anything, checks each surface against a checklist fetched from upstream, assigns each finding a severity from critical to info, and writes one deep-dive report file. Use when you say audit this project's AI usage, check our prompts and skills for problems, run an AI health check, are our prompts out of date for the current model, review our agent configuration, or find the dead prompt instructions in this repository. It also audits against Mastra guidance when the project depends on Mastra. It reads the audited project and writes nothing there except its own report.
license: CC-BY-ND-4.0
metadata:
  version: "0.2.0"
  category: ai-health
---

# ai-audit

## Purpose

ai-audit inspects how a whole project uses AI and writes one deep-dive report about it. The surfaces it reads are the ones nobody owns: a system prompt assembled across three files, a skill file that grew one line per incident, a tool description that no longer matches what the tool returns, a model ID pinned two releases ago. Each of those is text that reaches a model on every request, and none of them fail loudly. This skill finds them, gathers the vendor guidance, the model lifecycle pages, and the public catalogue entries for every model the project routes to before it judges anything, judges each surface against a published checklist, gives every finding a severity, and reports the result. It audits the project you point it at, which is usually not this repository. It reads that project and changes nothing in it except the single report file it creates.

## When to use / when NOT to use

Use ai-audit when you:

- Want a full audit of a project's prompts, skills, agent configuration, tool descriptions, and the models it routes to.
- Are about to change the model a project targets, or just changed it.
- Inherited a repository whose prompt text nobody can justify.
- Want findings ranked by severity and kept in a file you can act on later.
- Want a per-area verdict on prompts, skills, config files, tool descriptions, and models.

Do NOT use ai-audit when you:

- Want one pull request or diff reviewed. Use ai-review.
- Want the findings fixed. This skill reports and proposes in words. It applies nothing.
- Want prose documentation rewritten. Use doc-cleanup.
- Want only a credential and privacy scan. Use secret-and-privacy-sweep.
- Are looking at a project with no prompts, no skill files, no agent config, and no model IDs. Say so and stop.

## Workflow

1. Fix the scope and name the target model before you read anything. Scope covers whatever path the user points you at; absent such a pointer, treat the entire audited project as in scope. Which model reads the surface decides what counts as cruft — wording an older generation truly depended on can turn into inert filler once a stronger successor reads it — so no finding is valid until a target model has been named. Settle that target by looking first at the request itself, next at any migration the project has written down, and last at the freshest model identifier appearing anywhere in the project's source or prose. Record the scope and the resolved model in the report header before anything else.
2. Research before you judge anything. In this step read only the manifest, the lockfile, and the output of a grep for model IDs across router, config, and environment-default files; every other project file is read in step 5. Create the temporary directory now, outside the audited project, and keep every download from the whole audit under it:

   ```sh
   audit_tmp="$(mktemp -d)"
   ```

   Gather three sources, and record every fetch attempted in this step in the report with its exact URL and the HTTP code it returned, 200 or otherwise.

   - (a) Mastra. If the manifest depends on `mastra` or on any `@mastra/*` package, record the declared version from the manifest and the resolved version from the lockfile, whichever of `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, or `bun.lock` is present. Then fetch the Mastra docs index and the agents, tools, workflows, memory, and MCP pages, one command per page, so that an `etag` handle exists for each:

     ```sh
     curl -sS --fail -D "$audit_tmp/mastra-index.headers" -o "$audit_tmp/mastra-index" https://mastra.ai/llms.txt
     curl -sS --fail -D "$audit_tmp/mastra-agents.headers" -o "$audit_tmp/mastra-agents" https://mastra.ai/docs/agents/overview.md
     curl -sS --fail -D "$audit_tmp/mastra-tools.headers" -o "$audit_tmp/mastra-tools" https://mastra.ai/docs/agents/tools.md
     curl -sS --fail -D "$audit_tmp/mastra-workflows.headers" -o "$audit_tmp/mastra-workflows" https://mastra.ai/docs/workflows/overview.md
     curl -sS --fail -D "$audit_tmp/mastra-memory.headers" -o "$audit_tmp/mastra-memory" https://mastra.ai/docs/memory/overview
     curl -sS --fail -D "$audit_tmp/mastra-mcp.headers" -o "$audit_tmp/mastra-mcp" https://mastra.ai/docs/connections/mcp.md
     ```

     Skip part (a) when the dependency is absent, and say in the report that it was skipped.
   - (b) Vendor guidance. For every provider that owns a routed model or the target model, fetch that provider's prompt-guidance page and its model lifecycle or deprecation page with the same `-D`/`-o` form. For Anthropic, fetch `https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/overview` and `https://platform.claude.com/docs/en/about-claude/model-deprecations`. For OpenAI, fetch `https://platform.openai.com/docs/guides/prompt-engineering` and `https://platform.openai.com/docs/deprecations`. For Google, attempt `https://ai.google.dev/gemini-api/docs/prompting-strategies` and `https://ai.google.dev/gemini-api/docs/deprecations`; cite either page only when it returned 200, and otherwise describe it in the report by its role, as Google's published prompting guidance or Google's published model deprecation page, with no URL. When any routed model or the target model is a Claude model, also fetch the upstream sibling `model-migration.md` from the same directory as the checklist, at `https://raw.githubusercontent.com/anthropics/skills/main/skills/claude-api/shared/model-migration.md`. That fetch is required, not optional, because its retired and deprecated tables are the Claude lifecycle source.
   - (c) The OpenRouter public catalogue. Fetch the top thirty models by weekly usage, which needs no API key, and then one per-model lookup for every routed model ID and for the target model ID. Capture the HTTP code on each call, so that a 404 for an unknown model is distinguishable from a network failure:

     ```sh
     curl -sS -D - -o "$audit_tmp/openrouter-top30.json" -w '%{http_code}\n' \
       'https://openrouter.ai/api/v1/models?sort=most-popular&limit=30'
     curl -sS -D - -o "$audit_tmp/openrouter-<provider>-<model>.json" -w '%{http_code}\n' \
       "https://openrouter.ai/api/v1/model/<provider>/<model>"
     ```

   State the Google outcome in the report explicitly: fetched with 200, or described by role because the page returned something other than 200.
3. Fetch the base checklist into `$audit_tmp`, the directory created in step 2, so that nothing lands in the audited project's working tree. Write both the body and the response headers into it:

   ```sh
   curl -sS --fail -D "$audit_tmp/headers.txt" \
     -o "$audit_tmp/prompt-audit.md" \
     https://raw.githubusercontent.com/anthropics/skills/main/skills/claude-api/shared/prompt-audit.md
   ```

   Then record which revision you fetched, so the report is reproducible. Use the first handle available:

   ```sh
   gh api 'repos/anthropics/skills/commits?path=skills/claude-api/shared/prompt-audit.md&per_page=1' \
     --jq '.[0] | {sha: .sha, date: .commit.committer.date}'
   ```

   If `gh` is absent or unauthenticated, record the `etag` value from `$audit_tmp/headers.txt`, which is a content hash of the bytes you actually received. If neither is available, record the UTC fetch timestamp. Put whichever handle you got in the report header and say which kind it is. The checklist also points at two sibling files, `model-migration.md` and `prompt-caching.md`, in the same upstream directory. Step 2 already fetched `model-migration.md` when a Claude model is in play; fetch `prompt-caching.md` into `$audit_tmp` the same way when a finding turns on cache ordering, and record the revisions of both. Everything downloaded during the audit stays under `$audit_tmp`; the audited project receives no file from this step.
4. If the fetch fails for any reason, a network block, a 404, a moved path, or a rate limit, use the embedded fallback checklist below instead. Say in the report that the fetch failed, give the reason, and name the fallback as the checklist that was used. Never continue silently on a failed fetch, and never reconstruct the upstream checklist from memory.
5. Inventory every AI surface in the audited project, and write the list into the report before you judge any of it. The inventory covers:

   - Prompts embedded in code. Look for string literals passed to an LLM API call, including prompts assembled from template files, f-strings, and conditional fragments.
   - Every skills directory that may exist: `skills/`, `.claude/skills/`, `.agents/skills/`, and `.opencode/skills/`.
   - `CLAUDE.md` and `AGENTS.md`, at the repository root and nested.
   - `.cursorrules` and every file under `.cursor/rules/`.
   - `opencode.json` and anything under `.opencode/`.
   - Claude Code settings, such as `.claude/settings.json` and its local variants.
   - Tool descriptions, including MCP server tool and parameter descriptions, wherever they are defined.
   - Every model ID referenced anywhere in the project, in code, in configuration, in documentation, and in lock files. Every model ID entry must also record which provider owns it, inferred from the ID's namespace or prefix or from the surrounding code, so that step 2's per-provider vendor-guidance fetch and step 7's per-model judgement always have a provider to work from. Record both the id and the provider on every row; if the provider cannot be determined, write that explicitly in the row rather than leaving the field out. A routed model ID with no step-2 catalogue lookup on record, or a provider with no step-2 vendor pages fetched, triggers a return to step 2 to perform that specific fetch before step 7 begins. Do not carry an unattempted lookup forward into step 7.

   Apply these rules to the inventory:

   - Counting. For every multi-file surface, meaning prompt modules, persona files, memory prompts, skill directories, rule files, and commands, derive the count from a listing command such as `git ls-files 'packages/**/memory.prompt.ts'` or `find <dir> -name SKILL.md`, and write both the command and the count into the inventory row. A count that no command produced is a guess, and a guess is not an inventory.
   - Read in full. Every inventoried file is opened and read in full before any judgement is made about it. The Read column holds exactly one of three values, `yes`, `yes — proxy`, or `no — <reason>`, and nothing else. The phrases `sampled`, `by size and form`, `not judged line by line`, and `inventoried but not reviewed` are forbidden as Read values, because each of them is a way of writing `no` without saying so. The only valid reasons for `no` are a stored value with no proxy, as described below, or a file the tooling cannot open, such as a binary, a missing path, or a permission denial.
   - Batching. When the inventory is large, work it in batches grouped by directory and record the batch boundaries in your notes. A batch boundary is never a reason to stop. Vendored third-party skill directories installed by a skills CLI are read in full too; mark their findings `vendor-owned` so the reader knows the fix lives upstream.
   - Runtime-assembled prompts are two surfaces, and both are inventoried. The assembly is the code that builds the prompt, meaning the template functions, the string concatenation, and the conditional fragments. It lives in the repository, so you MUST read it and judge it: list every fragment it splices, classify each fragment's origin as a static literal, a stored record, user input, retrieved memory, or a tool result, and record the splice order, the fencing or delimiters around untrusted fragments, any size cap, and what happens when a fragment is empty. The stored values are the records spliced in at run time. Read them through the proxies the repository holds, such as seed scripts, fixtures, eval cassettes, snapshot tests, and migration defaults, and name each proxy in the inventory row as `yes — proxy`. Only a stored value with genuinely no proxy anywhere goes to "Not covered by this audit", and that entry MUST name which proxy locations were searched, for example "searched seed scripts, fixtures/, and migration defaults; none found". A surface outside the repository, such as a live external service, still goes in the report as a gap in the traditional sense. Do not guess its contents. This two-surface split applies to runtime-assembled prompts specifically, not to every surface you cannot read.
6. If the audited project's `package.json`, or the equivalent manifest for its language, depends on `mastra` or on any `@mastra/*` package, audit its agent, tool, workflow, and memory definitions against the Mastra pages fetched in step 2. Compare the declared and resolved Mastra versions recorded in step 2 against what those pages document, and raise any guidance the pinned version cannot follow. Cite the specific Mastra pages fetched in step 2, by their Sources-block names, as the source for every Mastra-specific finding, and name the page and the guidance you applied. Skip this step entirely when the dependency is absent, and say in the report that it was skipped.
7. Judge every routed model and the target model, using only what step 2 fetched. Nothing in this step comes from memory: when a fetch for a page or catalogue entry was attempted and failed, the finding says so and the judgement is marked unsupported rather than filled in from recall. A fetch that was never attempted is a step-5 gap, and step 5 sends it back to step 2 before this step starts; if one still surfaces here, return to step 2 for it, and never fill the judgement in from recall in the meantime.

   - (a) Define the judged set first. A routed model is any ID that a live code path passes to a model call — a router default, a task pin, or an environment default resolved in code. The target model is the one step 1 resolved. An ID that appears only in tests, fixtures, comments, or eval provenance stays in the model ID inventory but is not judged for fit. Say which class every ID belongs to, so that the inventory carries one `Routed model` row per routed ID, exactly one `Target model` row, and a plain inventory row for everything else.
   - (b) Answer four questions for each judged model, from the files fetched in step 2 and from nothing else.
     - CURRENT. Does the vendor's own lineup or lifecycle page still list the ID as active? For a Claude model, also check the retired and deprecated tables in the upstream `model-migration.md` fetched in step 2. The OpenRouter lookup and its `expiration_date` are supporting evidence only; a catalogue 404 on its own is an observation that the catalogue does not list the ID, and nothing more.
     - FIT. Compare what the pinned task demands, as evidenced by its own prompt and schema — input modalities, expected output length, the context it must hold, tool calling, structured output — against the catalogue entry's `architecture.input_modalities`, `context_length`, and `supported_parameters`, and against the vendor's own description of the tier the model sits in.
     - BETTER OPTION. From the fetched top-thirty list and the provider's own lineup, is there a newer entry in the same family, meaning a later `created` value from the same author, or a higher-ranked entry that satisfies every fit constraint? Name any candidate by its `<provider/model>` ID and quote the fetched fields that make it better; a candidate named without those fields is an opinion, not a finding.
     - COST. Record `pricing.prompt` and `pricing.completion` per token from the catalogue entry, for the judged model and for any candidate named above.
   - (c) Map each model finding to a severity for Area `models`, in the same four names the severity scale below defines:
     - `critical` — the vendor's own page, or `model-migration.md` for a Claude model, lists the ID as retired while it sits on a live route.
     - `major` — the vendor lists the ID as deprecated with a retirement date, or the catalogue entry shows an `expiration_date`.
     - `major` — the model is clearly under-powered for its task, meaning a hard constraint such as an input modality or the context the task must hold goes unmet.
     - `minor` — a better option exists and nothing is urgent, because the current model still works.
     - `info` — a price-only observation, or an ID absent from the OpenRouter catalogue with no vendor signal either way. A lone catalogue 404 with no vendor confirmation is `info`, never `critical`.

     A model that is current and fit is reported as clean under "What I checked".
   - (d) Keep the restraint rule from step 8 here too: verify each model finding against the fetched data before you write it, open the catalogue entry or the vendor page and read the line the finding rests on, and drop the finding if it does not survive that check. Popularity alone never justifies recommending a switch; a high rank shows that a candidate exists, and fit against the task's own demands decides whether it belongs. A proposed replacement is a proposal in words in the report, never a change applied to the project.
8. Judge each inventoried surface against the checklist. Verify every finding against the file before you write it: open the line, read its context, and drop the finding if it does not survive that check. Keep the checklist's own restraint rule, because it is the part an audit gets wrong most often. Size is not the defect, and a word count is not an argument. Whatever the model has no way to work out for itself stays on the page: how the surrounding system actually behaves, the rationale that put each constraint there, what the product is for, the standard the output is judged by, and who ends up reading it. A prohibition that heads off a mistake the target model still makes stays. Where only one route through an operation avoids damage, spelling out each command verbatim is the right call. Tool descriptions usually fail by saying too little, not too much, so the fix there is often more text. An audit may end with no findings at all; when a surface holds up, log it as clean and leave every line of it alone.
9. Give every finding exactly one severity: `critical`, `major`, `minor`, or `info`. Use the table below. Then write the per-area health summary, one line for each of prompts, skills, config files, tool descriptions, and models, so a reader sees which area needs attention without reading every finding.
10. Write the report. Create `reports/` inside the audited project if it does not exist, then write to `reports/ai-audit-<YYYY-MM-DD>.md` using today's date. If that exact file already exists, append a numeric suffix and write `reports/ai-audit-<YYYY-MM-DD>-2.md`, then `-3`, and so on until the name is free. Never overwrite an existing report.
11. Say where the report is, which checklist revision it used, and how many findings it holds at each severity. Then walk the QA checklist.

### Embedded fallback checklist

Use this only when step 3's fetch failed. It is a shorter checklist built from the same ideas as the upstream one, restated in this project's own words, and it keeps the restraint rule from step 8. Put one test to every line of every surface ahead of all the others: would the model arrive at this unprompted? A line it would reach on its own is a candidate for removal; a line carrying knowledge that only the person who wrote the surface holds stays where it is.

| Area | Ask on every surface |
| --- | --- |
| Role and context clarity | Can a reader tell from the text who it serves, what is being built, what the runtime looks like, and what counts as good work? One sentence of persona costs nothing; raise it only where that sentence is standing in for all of the above. |
| Instruction specificity | Does the latitude the text allows track the cost of getting this particular task wrong? A numbered script imposed on a judgment call leaves too little room. Loose prose covering a deletion or a login flow leaves far too much. |
| Output-format contracts | Is the shape of the answer declared once, and checked by machinery rather than by prose wherever machinery can do it? Raise hand-built format scaffolding that a structured-output setting now handles, together with the stop sequences, re-parse loops, and trailing assistant turns that grew up around it. |
| Example quality | Do the samples span a range and announce themselves as samples, or does a single showcase answer lock in the cadence of whatever model it was written against? Samples survive where the output really does have to land in one exact shape. |
| Tool-description accuracy | Does the text promise exactly what the tool delivers and withholds, name every argument, and say where the tool is the wrong reach? Too little detail is the usual fault here, so expect the repair to lengthen the entry. Worked examples and nudges about conversational behaviour belong somewhere else. |
| Model fit | Was this written for the model named in step 1, or for the one before it? Piled-up emphasis now fires the behaviour more often than anyone wanted, and a softener such as try to or if possible sitting on top of a hard requirement now reads as permission to skip it. |
| Deprecated-model usage | Do retired model identifiers still sit in source, configuration, prose, or comments? Does any patch here exist to route around behaviour that only an earlier generation showed? Does the request carry arguments or headers the target model will refuse? |
| Model currency and fit | Is every routed model, and the target model, still listed as active by its vendor and present in the catalogue you fetched, without an expiration date? Does it meet the modality, context, and output demands of the task it is pinned to? Is there a newer or better-fitting model in the same fetched data, and at what price? |
| Token efficiency | Is each paragraph worth what it costs every time the surface loads? A skill pays its full size on each trigger. Raise copies of one rule that have drifted into disagreeing with each other, and raise restatements added to make a point land harder. A smaller file is never on its own a reason to cut. |
| Eval and regression coverage | Would anything notice if this text quietly stopped working? Raise instructions that no test, hook, or reviewer ever looks at, above all the ones the project's own logs show being ignored. Raise a missing per-surface cost breakdown too, since without one none of the other answers can be measured. |

### Severity scale

| Severity | Meaning |
| --- | --- |
| `critical` | The surface is broken or unsafe as written. A rejected parameter, a retired model ID on a live path, a tool description that contradicts the tool, or a prompt that leaks data into a place it must not reach. |
| `major` | A real defect that degrades output or will cost significantly more to fix later. Contradictory duplicated rules, a prompt calibrated for a retired generation, a materially under-described tool. |
| `minor` | A genuine improvement with a small cost. Stale wording, a narrow conditional that a principle would cover, mild redundancy. |
| `info` | An observation with no action attached. A gap you could not read, a low-confidence idiom match, or a surface confirmed clean. |

## Output format

Write one report file in this shape. Proposed changes are report text only. Nothing in the report is applied to the audited project.

````markdown
# AI health audit — <project name> — <YYYY-MM-DD>

> AI-generated audit. An automated agent read this project's AI surfaces and wrote these findings. Each item is a claim to check, not a verdict.

**Scope:** <paths audited, or "whole project">
**Target model:** <model ID> — resolved from <request | migration doc | repository reference>
**Checklist:** upstream prompt-audit at <commit SHA | etag | fetch timestamp UTC>, kind `<sha|etag|timestamp>`
**Mastra audit:** applied, citing <pages from the Sources block> for installed <version> | skipped, dependency absent
**Sources:**

- Mastra docs: <pages> — <handle> | skipped, dependency absent
- Vendor guidance (<provider>): <prompt-guidance page>, <lifecycle page> — <handle> | failed — <reason>
- Upstream model-migration: <sha|etag|timestamp> | not fetched, no Claude model routed or targeted
- OpenRouter catalogue: top <N> by weekly usage — <UTC timestamp>; lookups: <id — HTTP code> ... | none

## Health summary

| Area | Verdict | critical | major | minor | info |
| --- | --- | --- | --- | --- | --- |
| Prompts | <one line> | 0 | 1 | 2 | 0 |
| Skills | <one line> | 0 | 0 | 1 | 1 |
| Config files | <one line> | 1 | 0 | 0 | 0 |
| Tool descriptions | <one line> | 0 | 2 | 0 | 0 |
| Models | <one line> | 0 | 0 | 0 | 1 |

## Inventory

| Surface | Path | Read |
| --- | --- | --- |
| Prompt in code (<N> files; `<listing command>`) | `path/glob` | yes |
| Skill file | `path/to/SKILL.md` | yes |
| Agent config | `path/to/config` | yes |
| Tool description | `path/to/tools` | yes |
| Model ID | `path/to/file:12` | yes |
| Routed model | `path/to/router:12` — `<provider/model>` serves <task> | yes |
| Target model | `<provider/model>` — resolved from <request, migration doc, or repository reference> | yes |
| Runtime-assembled prompt (assembly) | `path/to/builder` | yes |
| Runtime-assembled prompt (stored values) | `path/to/seed-or-fixture` | yes — proxy |
| Runtime-assembled prompt (stored values) | <record kind> | no — searched <proxy locations> |

## Findings

### 1. [critical] <one-line title> — `path/to/file:42`

- **Area:** config files
- **Evidence:** the offending line, reproduced word for word.
- **Checklist item:** which checklist area or row it matches.
- **Why it matters:** the consequence for the target model, concretely.
- **Proposed change:** what to change, in words. Not applied.

### 2. [major] <one-line title> — `path/to/other:88`

- **Area:** tool descriptions
- **Evidence:** a verbatim quotation of the text in question.
- **Checklist item:** tool-description accuracy.
- **Why it matters:** the cost you expect, and when it lands.
- **Proposed change:** the text to add. Not applied.

### 3. [major] <one-line title> — `path/to/router:12`

- **Area:** models
- **Evidence:** `<provider/model>` pinned for <task>; vendor lifecycle status and catalogue fields quoted.
- **Checklist item:** model currency and fit (step 7).
- **Why it matters:** what the task loses on this model, and when the vendor's date lands.
- **Proposed change:** the `<provider/model>` to move to, with the fetched fields that make it fit. Not applied.

## What I checked

| Surface | Checklist areas | Result |
| --- | --- | --- |
| `path/to/file` | <areas of the checklist actually used> | finding 1 |
| `path/to/other` | <areas of the checklist actually used> | finding 2 |
| `path/to/third` | <areas of the checklist actually used> | clean |
| `<provider/model>` (route: <task>) | model currency and fit | clean |
| `<provider/model>` (target) | model currency and fit | finding 3 |

## Not covered by this audit

- <what you could not read, and why: a stored value with no proxy (name the proxy locations searched), an external service, no access.>
````

Rules for the report:

- Order findings by severity, `critical` first, then by path.
- One finding per block. Do not merge two problems into one entry to shorten the list.
- The health summary and the "What I checked" table are mandatory in every report, and above all in a report with no findings. Reporting a surface as clean is a real result; handing back nothing at all is not.
- Fill the "Checklist areas" column from whichever checklist step 3 actually produced. The upstream file is not organised into ten areas, so write `all ten` only where the embedded fallback was the checklist in play.
- Name the checklist revision and its kind in the header. A report that cannot say which checklist it used is not reproducible.
- State proposed changes in words. Do not attach a patch and do not apply one.
- The `**Sources:**` block is mandatory. It lists every fetch attempted in step 2, each with a handle or a failure reason, so a reader can tell what the judgements rest on.
- The health summary always has the five rows Prompts, Skills, Config files, Tool descriptions, and Models, in that order, even when a row reports nothing.
- Every routed model and the target model has its own "What I checked" row, with a `clean` result or the finding it produced.
- The Read column holds only `yes`, `yes — proxy`, or `no — <reason>`. No other value is allowed there.
- Every multi-file inventory row carries its listing command and the count it produced in the Surface cell.
- Every "Not covered" entry for a stored value names the proxy locations searched before it was declared a gap.

## Guardrails

MUST:

- MUST fix the scope and the target model up front, before opening a single file, and record both in the report.
- MUST attempt the pinned upstream fetch first, and MUST record which revision was fetched, as a commit SHA, an `etag`, or a UTC timestamp, naming which kind it is.
- MUST say in the report when the fetch failed, why it failed, and that the embedded fallback checklist was used instead.
- MUST inventory every surface named in the workflow, and MUST list the inventory in the report before any judgement.
- MUST record a surface it could not read as a gap rather than guessing its contents.
- MUST run the research step before judging any surface.
- MUST record every source it fetched, with a handle or a failure reason, in the report header.
- MUST read every inventoried file in full.
- MUST derive multi-file counts from a listing command recorded in the report.
- MUST read and judge the code that assembles a runtime prompt.
- MUST name the proxy locations searched for any stored value it reports as a gap.
- MUST audit against Mastra guidance when the manifest depends on `mastra` or `@mastra/*`, and MUST cite the specific Mastra pages fetched in step 2, by their Sources-block names, for each such finding.
- MUST judge every routed model and the target model for currency, fit, better option, and price from the fetched data.
- MUST give Models its own health-summary row.
- MUST give every finding exactly one severity from `critical`, `major`, `minor`, `info`.
- MUST include a per-area health summary covering prompts, skills, config files, tool descriptions, and models.
- MUST verify a finding against the file at its cited line before writing it.
- MUST write the report to `reports/ai-audit-<YYYY-MM-DD>.md` in the audited project, creating `reports/` if needed, and MUST use the next free numeric suffix when that name is taken.
- MUST describe a discovered credential by location and kind only. Point at `file:line`, name what kind of value it is, and never repeat the value itself.
- MUST report what it could not check, and why.

NEVER:

- NEVER change anything in the audited project except creating its one report file. No code, no prompts, no skill files, no configuration, no dependencies.
- NEVER overwrite an existing report, including one written earlier the same day. Add a numeric suffix instead.
- NEVER apply a proposed change, and never attach a patch that a later step could apply by accident.
- NEVER create a branch, a commit, or a tag, and never push.
- NEVER paste a secret value, a token, a private key, a password, a personal email address, or a customer identifier into the report. Location and kind only.
- NEVER argue for cutting text on the grounds that it shrinks the file. A long surface is not, by that fact, a padded one.
- NEVER file a finding against what the product is meant to do, the bar the work is measured against, the audience it is written for, the reasoning that put a constraint in place, or the operating realities of the system around it. None of that is recoverable by the model unaided, so it stays on the page.
- NEVER recommend trimming a tool description that is already too short. Say what to add.
- NEVER invent a finding so the report looks thorough, and never invent checklist content. Fetch it or use the embedded fallback.
- NEVER report a surface as clean without listing it in the "What I checked" table.
- NEVER sample an inventory.
- NEVER write `sampled`, `by size and form`, `not judged line by line`, or `inventoried but not reviewed` as a Read value.
- NEVER judge a model from memory. Judge it only from the catalogue and vendor pages fetched in this run.
- NEVER treat popularity alone, or absence from the OpenRouter catalogue alone, as a reason to recommend a switch.
- NEVER store, print, or require an API key. None is needed.
- NEVER pin a model ID or a checklist line into this skill. Both rot; read them from the project and from upstream at run time.

## QA checklist

Run this list before you hand over the report.

- [ ] The scope and the target model are named in the report header.
- [ ] The upstream fetch was attempted, and its revision handle plus kind is in the header.
- [ ] A failed fetch is reported with its reason, and the fallback checklist is named as the one used.
- [ ] Every surface in the workflow inventory was searched for, and the inventory table lists what was found.
- [ ] Surfaces that could not be read appear as gaps, not as guesses.
- [ ] The Mastra step was applied, citing the specific pages fetched in step 2, or reported as skipped.
- [ ] Every finding was verified at its cited line before it was written.
- [ ] Every finding carries exactly one severity from `critical`, `major`, `minor`, `info`.
- [ ] Findings are ordered by severity, `critical` first.
- [ ] The per-area health summary covers prompts, skills, config files, tool descriptions, and models.
- [ ] The "What I checked" table lists every inventoried surface, including the clean ones.
- [ ] No cut is defended on the grounds that it shrinks the file, and nothing the model had no way to reach on its own was raised as a finding.
- [ ] No under-described tool description was told to get shorter.
- [ ] The report contains no secret value, no personal data, and no customer identifier.
- [ ] The report is at `reports/ai-audit-<YYYY-MM-DD>.md`, or at the next free numeric suffix, and no prior report was overwritten.
- [ ] Nothing in the audited project changed except that one report file.
- [ ] The limits of the audit are stated.
- [ ] The Sources block lists every fetch from step 2 with a handle or a failure reason.
- [ ] Every routed model and the target model has a fit verdict and a "What I checked" row.
- [ ] Every multi-file inventory row shows its listing command and count.
- [ ] Every Read value is `yes`, `yes — proxy`, or `no — <reason>`, never `sampled`, `by size and form`, `not judged line by line`, or `inventoried but not reviewed`.
- [ ] Every runtime-assembled prompt has an assembly row.
- [ ] Every stored-values gap names the proxies searched.
- [ ] No model ID, price, or checklist line was pinned into the skill.
- [ ] No API key was used.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
