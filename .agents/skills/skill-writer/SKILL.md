---
name: skill-writer
description: Authors and reviews SKILL.md files for the silly-skills repository. Defines the frontmatter contract, the six-section body order, the tone rules, the 700-character description budget, version-bump rules, the optional suggested-model hint, references/ for long detail, and the attribution footer. A suggested model becomes a persona through create-agent, under agents/. Use when writing a new skill, creating SKILL.md, adding a skill to skills/<category>/, bumping a skill version, or reviewing this skill for silly-skills standards.
license: CC-BY-ND-4.0
metadata:
  version: "0.4.0"
  category: workflow
---

# skill-writer

## Purpose

skill-writer defines the house style for every skill in this repository. It gives you the frontmatter contract, the fixed six-section body order, the tone rules, the version-bump rules, and the attribution footer. The description budget and the `references/` directory follow the Agent Skills specification, cited under references below. Use it when you author a new skill and when you review an existing one. Every other skill here conforms to the format described in this file, so a change to this file is a change to the whole catalogue.

## When to use / when NOT to use

Use skill-writer when you:

- Create a new `SKILL.md` under `skills/<category>/`.
- Review a skill before you commit it.
- Rename or move a skill directory.
- Bump a skill version or edit a skill description.
- Need to read a validator error and fix the file it points at.

Do NOT use skill-writer when you:

- Write repository documentation such as `README.md` or `CONTRIBUTING.md`.
- Change the validator, the CI workflows, or the license files.
- Write application code, tests, or scripts.
- Edit any file that is not a `SKILL.md`, its `examples.md`, or a file under its `references/`. A persona folder under `agents/` is `create-agent`.

## Workflow

1. Pick the category directory. It must be one of `review`, `ai-health`, `docs`, `engineering`, `planning`, or `workflow`.
2. Pick the skill name. It must be lowercase-hyphenated, must match `^[a-z0-9]+(-[a-z0-9]+)*$`, and must be 1-64 characters.
3. Create the file at `skills/<category>/<skill-name>/SKILL.md`. The directory name must equal the frontmatter `name` exactly.
4. Write the frontmatter shown in Output format. Set `metadata.category` to the parent category directory. Set `metadata.version` to `"0.1.0"` for a new skill.
5. Write the `description` in third person, from its first word to its last. State what the skill does in the first sentence. Then list the trigger phrases a user would actually type. Keep it under 700 characters. When you edit an existing description, bring it under 700 on that edit. The description sits in the system prompt of every session whether or not the skill runs, so its cost is paid constantly, while the workflow belongs in the body and loads only when the skill is used. Do not pad it. Write `Processes Excel files and generates reports`. Never write `I can help you process Excel files`. Never write `You can use this to process Excel files`. Never open on a bare imperative such as `Process Excel files` while the rest of the sentence stays third person, because that mixes two voices inside one description.
6. Optionally set `metadata.suggested-model` (a `provider/model` id, for example `anthropic/claude-fable-5-1`) and `metadata.suggested-effort` (`low`, `medium`, `high`, `xhigh`, or `max`) as an advisory hint for whoever configures the agent; no tool reads either key, and setting `suggested-effort` without `suggested-model` is an error. When you set the hint, run `create-agent` so the persona folder exists at `agents/<persona>/`. Never put a tool's `model:`, `effort:`, or `context:` key inside `SKILL.md` itself. Never put the persona files inside the skill directory.
7. Write the six body sections in the fixed order. Never add a seventh top-level section, never drop one, never reorder them. Keep the `SKILL.md` body under 500 lines. When a step needs detail that other steps do not, put that detail in `references/<topic>.md` and point to it from the workflow step that reads it. Follow the references rules in Output format.
8. Write in simple English. Use short sentences, active voice, and one instruction per sentence.
9. State a numbered work budget for any step that reads, searches, or renders an open-ended number of things (files explored, references opened, screenshots taken, review rounds run), and say what the skill does when it hits the budget: write what it has, and list what it skipped. Never leave a step as an unbounded "explore until done" or "review until it passes" with no ceiling.
10. If the skill produces an artefact a user can comment on, add the `### Handling feedback` rule described in Output format so a hedged remark never silently changes the artefact.
11. Verify every command, CLI flag, and URL you wrote. Run the command or open the link. Delete anything you could not verify.
12. Add the attribution footer as the last non-empty line, character for character.
13. Write `examples.md` beside the `SKILL.md`. Give it at least one worked scenario built from exactly three H2 sections in this order: `## Prompt`, `## Without skill`, `## With skill`. Feed both branches the identical input. Write the "Without skill" branch as the genuine baseline a competent agent reaches without the skill, and never weaken it to make the skill look better. Produce the "With skill" branch by following the new skill's own Workflow and Output format against that same input, not by paraphrasing the result you hoped for.
14. Run `bun run validate` from the repository root. Fix every `ERROR` line. Warnings do not block a commit.
15. Bump `metadata.version` and add a `CHANGELOG.md` line in the same change whenever you edit a published skill.
16. Walk the QA checklist below. Commit with a Conventional Commits message such as `feat(<category>): add <skill-name> skill`.

## Output format

Every `SKILL.md` in this repository uses this exact skeleton: the frontmatter block, one H1 that repeats the skill name, then exactly six H2 sections in this order, then the attribution footer.

````markdown
---
name: <skill-name>
description: <what the skill does, then the trigger phrases a user would type>
license: CC-BY-ND-4.0
metadata:
  version: "0.1.0"
  category: <review | ai-health | docs | engineering | planning | workflow>
  suggested-model: <provider/model, optional>
  suggested-effort: <low | medium | high | xhigh | max, optional>
---

# <skill-name>

## Purpose

<One paragraph. What the skill does and who it serves.>

## When to use / when NOT to use

<Two short lists. Name concrete situations, not feelings.>

## Workflow

<Numbered, imperative steps. One instruction per step.>

## Output format

<The exact shape the skill must produce. Show a skeleton, not prose.>

## Guardrails

<Hard MUST and NEVER rules. No soft advice.>

## QA checklist

<Checkboxes an agent can self-verify before it commits.>

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
````

The footer contains a bare URL, so `markdownlint` rule MD034 fires on it. The footer string is fixed and cannot be rewritten as a markdown link. Keep the `markdownlint-disable-next-line MD034` comment directly above it. The comment is a comment, not content, so the footer stays the last non-empty line.

Frontmatter field rules:

- `name` — required. Lowercase-hyphenated, matches `^[a-z0-9]+(-[a-z0-9]+)*$`, 1-64 characters, and exactly equal to the skill directory name.
- `description` — required. Under 700 characters in this repository. The validator still accepts 1-1024, which is the specification ceiling. A description you edit is brought under 700 on that edit. Must explain what the skill does and must include the trigger phrases that should load it. It is loaded in every session, so do not pad it.
- `license` — required. Exactly `CC-BY-ND-4.0`. No other value is accepted.
- `metadata.version` — required. A valid SemVer string. Quote it so it stays a string.
- `metadata.category` — required. Exactly the parent category directory name.
- `metadata.suggested-model` — optional. A `provider/model` id, matching `^[a-z0-9-]+/[a-z0-9.-]+$`. Advisory only; no tool reads it.
- `metadata.suggested-effort` — optional. One of `low`, `medium`, `high`, `xhigh`, `max`. Requires `metadata.suggested-model` to be set.

Section rules:

- The six H2 headings are fixed in wording and in order: `Purpose`, `When to use / when NOT to use`, `Workflow`, `Output format`, `Guardrails`, `QA checklist`.
- Use H3 headings inside a section when you need more structure. Never promote them to H2.
- The footer is the last non-empty line of the file. Nothing may follow it.

### references/

The [Agent Skills specification](https://agentskills.io/specification) is the source of these limits. It loads `name` and `description` for every skill, loads the `SKILL.md` body when the skill runs, and loads a file under `references/` only when a step reads it. Three numbers stay distinct:

- The specification caps `description` at 1024 characters. This repository uses 700 so a description stays clear of that ceiling.
- The specification's 500-character cap is the optional `compatibility` field. Skills here do not use that field.
- The specification says to keep the `SKILL.md` body under 500 lines.

Put detail that only some steps need in `references/<topic>.md`. Link it from `SKILL.md` with a relative path, one level deep. The workflow step names when to read the file. Do not link from one reference file to another.

### examples.md

Every skill directory ships an `examples.md` beside its `SKILL.md`. The file holds at least one worked scenario in exactly this shape:

````markdown
## Prompt

<The request a user typed, or the input the skill was handed, quoted as given.>

## Without skill

<What a competent agent produces from that input with no skill loaded.>

## With skill

<What the same agent produces from the same input after following this skill.>
````

`examples.md` rules:

- The three H2 headings are fixed in wording and in order: `Prompt`, `Without skill`, `With skill`. The file opens on `## Prompt`; it needs no H1 and no preamble.
- Both branches take the identical input. Change the input between branches and the comparison proves nothing.
- Show the artefact each branch produced, not a description of it. Put it in a fenced block so the reader sees its real shape.
- A second scenario repeats the same three headings in the same order. Put `<!-- markdownlint-disable-next-line MD024 -->` on the line directly above each repeated heading. MD024 treats those repeats as duplicate siblings, and the headings themselves stay fixed.

### Personas

A skill that sets `metadata.suggested-model` is named by exactly one `agents/<persona>/skill` sidecar. `create-agent` writes that folder. A skill with no suggested model ships no persona. `bun run validate` fails with `AGENT_WRAPPERS` when the sidecar is missing, when more than one persona names the skill, or when `skills/<category>/<skill>/agents/` still exists.

List-valued frontmatter inside `SKILL.md` stays in flow style, `key: [item-one, item-two]`. A YAML block list (`- item`) is an error there. OpenCode's `permissions` list is the exception, and it belongs only in `agents/<persona>/opencode.md`.

### Handling feedback

Any skill whose Output format produces something a user can comment on states this rule in its own Workflow: a hedged or uncertain remark — "I'm not sure", "I think", "maybe", "probably", "could we", "what if", "should we", or anything ending in a question mark — never changes the artefact by itself. Answer it with the skill's own opinion, the evidence behind it, a recommendation, and a yes/no question, then change the artefact only after the user confirms. A plain instruction ("remove step 3", "use the primary colour") is applied directly; if it conflicts with evidence the skill already gathered, state the conflict in one line and apply the instruction anyway — the user's stated intent wins once it is plain, but a guess should never be read as intent.

### Work budgets

Any skill whose Workflow reads, searches, or renders an open-ended number of things states a numeric budget for that step and what happens at the ceiling: stop, write what was gathered, and list what was skipped under the section the skill's Output format names for open items. A budget is a stop condition with a named fallback, not a hard error — the run still produces its artefact. Never write a step as "explore until you have enough" or "keep reviewing until it passes" with no number attached; that is exactly the pattern that let the framework this repository replaces burn tokens on runaway loops.

## Guardrails

MUST:

- MUST use the five required frontmatter keys above, plus `metadata.suggested-model` and `metadata.suggested-effort` only when the skill sets a model hint.
- MUST set `license` to `CC-BY-ND-4.0` and nothing else.
- MUST keep the frontmatter `name` identical to the skill directory name.
- MUST write the `description` in third person throughout, opening on a third-person present-tense verb such as "Reviews" or "Generates" so the first verb agrees with the rest of the sentence, and keep every description you write or edit under 700 characters.
- MUST keep the `SKILL.md` body under 500 lines. Put detail that only some steps need in `references/<topic>.md`, linked one level deep from `SKILL.md`.
- MUST place the file at `skills/<category>/<skill-name>/SKILL.md`, exactly three levels under `skills/`.
- MUST include the six sections in the exact order given in Output format.
- MUST end the file with the attribution footer as the last non-empty line, matched character for character.
- MUST ship a non-empty `examples.md` in every skill directory, beside the `SKILL.md`.
- MUST build each `examples.md` scenario from the three H2 sections `Prompt`, `Without skill`, and `With skill`, in that order.
- MUST give both branches of a scenario the identical input: the same prompt, the same diff, the same ticket text.
- MUST stay tool-agnostic. The skill has to work in Claude Code, Cursor, and OpenCode.
- MUST point at `create-agent` whenever `metadata.suggested-model` is set, so exactly one `agents/<persona>/skill` sidecar names this skill.
- MUST state a numbered work budget for any open-ended read, search, or render step, and name what happens at the ceiling.
- MUST answer a hedged remark with an opinion and a yes/no question before changing an artefact, for any skill that produces one.
- MUST verify every executable claim before you write it. A command, a CLI flag, or a URL goes in the file only after you ran it or opened it.
- MUST bump `metadata.version` and add a `CHANGELOG.md` line in the same change. Patch means a wording-only fix. Minor means a new capability was added. Major means the workflow or the output contract changed.
- MUST keep the tone direct. Write short sentences, active voice, one instruction per sentence.

NEVER:

- NEVER commit a secret. No API keys, no access tokens, no private key blocks, no passwords.
- NEVER include personal data. No personal email addresses, no names of private individuals, no account identifiers.
- NEVER include an internal URL, an internal hostname, or a local development address.
- NEVER include an absolute path from your own machine. Use repository-relative paths.
- NEVER invent a command, a flag, a file path, or a URL. Delete what you cannot verify.
- NEVER use tool-exclusive syntax or assume one agent's file layout, slash commands, or settings format in `SKILL.md` itself; tool-specific fields such as `model:`, `effort:`, or `context:` belong only in `agents/<persona>/`.
- NEVER put a YAML block list in `SKILL.md` frontmatter. Write list values in flow style.
- NEVER create `skills/<category>/<skill>/agents/`. Personas live at `agents/<persona>/`.
- NEVER add filler praise, marketing language, or emphasis words such as "powerful" or "seamless".
- NEVER add, remove, or reorder the six top-level sections.
- NEVER commit a skill without its `examples.md`. A missing or blank file fails `bun run validate` with `MISSING_EXAMPLES`.
- NEVER weaken the "Without skill" branch to flatter the skill. Write the baseline a competent agent actually reaches, however good that baseline is.
- NEVER let the "With skill" branch drift from what the skill's own Output format specifies. Follow the skill, then record what came out.
- NEVER bump a version without a matching `CHANGELOG.md` line.
- NEVER republish a modified copy of a skill from this catalogue. The content is source-available and free to use with attribution, and modified redistribution needs written approval.

## QA checklist

Run this list before you commit a skill.

- [ ] The file is at `skills/<category>/<skill-name>/SKILL.md` and the category is `review`, `ai-health`, `docs`, `engineering`, `planning`, or `workflow`.
- [ ] Line 1 is `---` and the frontmatter has a closing `---`.
- [ ] `name` is lowercase-hyphenated, is 1-64 characters, and equals the directory name.
- [ ] `description` is under 700 characters, says what the skill does, and lists trigger phrases. The validator still accepts up to 1024.
- [ ] The `SKILL.md` body is under 500 lines. Any `references/` file is linked one level deep from `SKILL.md`, and no reference links onward to another file.
- [ ] `description` is written in third person throughout, including its opening verb, with no first-person or second-person wording.
- [ ] `license` is exactly `CC-BY-ND-4.0`.
- [ ] `metadata.version` is a quoted, valid SemVer string.
- [ ] `metadata.category` equals the parent category directory.
- [ ] If set, `metadata.suggested-model` matches `provider/model` and `metadata.suggested-effort` is one of `low`, `medium`, `high`, `xhigh`, `max`; `suggested-effort` never appears without `suggested-model`.
- [ ] No frontmatter key is declared twice.
- [ ] The body has exactly six H2 sections, correctly worded and in the required order.
- [ ] If `metadata.suggested-model` is set, exactly one `agents/<persona>/skill` sidecar names this skill, and `create-agent` wrote the three tool files.
- [ ] Every step that reads, searches, or renders an open-ended number of things states a numbered budget and a named fallback.
- [ ] Every skill that produces a user-facing artefact states the hedged-feedback rule in its Workflow.
- [ ] Every command, flag, and URL in the file was verified by running or opening it.
- [ ] The file contains no secret, no personal data, no internal URL, and no absolute local path.
- [ ] The tone is direct, with short sentences and no marketing language.
- [ ] The skill makes no assumption that is specific to one agent tool, and `SKILL.md` itself carries no `model:`, `effort:`, or `context:` key.
- [ ] `metadata.version` was bumped and `CHANGELOG.md` gained a line in this same change, if the skill already existed.
- [ ] The last non-empty line is the attribution footer, matched character for character.
- [ ] `examples.md` sits beside the `SKILL.md`, is not blank, carries the sections `Prompt`, `Without skill`, and `With skill` in that order, and feeds both branches the identical input.
- [ ] `bun run validate` reports 0 errors.
- [ ] The `markdownlint-disable-next-line MD034` comment sits directly above the footer.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
