---
name: create-agent
description: Writes or updates a persona folder under agents/ for one existing skill, with a Claude Code file, an OpenCode file, and a Cursor file. Sets the description, the mode (agent, subagent, or all), a system prompt that loads the skill, the matching model per tool, delegation to named child personas, and the tool permissions each product can enforce. Use when creating an agent, adding or updating a persona, or wrapping a skill for Claude Code, Cursor, or OpenCode.
license: CC-BY-ND-4.0
metadata:
  version: "0.2.0"
  category: workflow
---

# create-agent

## Purpose

create-agent writes the persona that runs a skill. The skill stays the procedure. The persona is the role a person switches to or invokes: `tech-writer` for the `tech-writing` skill, `plan-reviewer` for `plan-review`. It writes three tool files and a one-line sidecar, or updates an existing persona's files. It does not copy the skill body into the prompt, and it does not edit `SKILL.md`. A persona can run as a primary session, as a child another agent launches, or both. A child cannot ask the user a question in every tool, so the persona says where its questions go.

## When to use / when NOT to use

Use create-agent when you:

- Add a persona for a skill that already exists under `skills/`.
- Set `metadata.suggested-model` on a skill and need the matching `agents/<persona>/` folder.
- Change a persona's mode, system prompt, model, delegation, or tool permissions.

Do NOT use create-agent when you:

- Author or review the skill's own `SKILL.md`. That is `skill-writer`.
- Install a persona into a tool. That is `scripts/agent-install.sh`.
- Edit the validator, the installer, or repository docs.

## Workflow

1. Take the persona name. It is lowercase words separated by hyphens, 1 to 64 characters, and a role (`tech-writer`). It may equal the skill name when that name is already a role (`plan-writer`). If `agents/<persona>/` already exists, continue only when the request asks to update that persona. Read all four of its files first and change only what the request needs; otherwise refuse the name.
2. Take the skill it loads. The directory `skills/<category>/<skill>/` must already exist. Read that `SKILL.md` once. If it does not exist, stop and say so.
3. Take the mode: `agent`, `subagent`, or `all`. `agent` is written as OpenCode `mode: primary`, a session the user switches to. `subagent` runs only as a child that another agent launches. `all` runs either way, so another persona can launch it and a user can still switch to it. `subagent` and `all` are written unchanged. Write `mode` only in `opencode.md`. Claude Code and Cursor run every custom persona as a subagent; say so in their bodies.
4. Write a system prompt that names the persona, says which contexts it runs in, and tells the agent to load the skill and follow its Workflow. As a primary session (`agent`, or `all` launched by the user), follow the steps the skill marks interactive. As a child (`subagent`, `all` launched by an agent, and every Claude Code or Cursor persona), follow the skill's non-interactive run. When the skill needs an owner answer there, return the question to the parent in the reply instead of asking. Claude Code children cannot use its question tool. Do not paste the skill body. Do not invent a section name the skill does not have.
5. Allow only the tools that workflow uses. OpenCode gets a `permissions` list: a broad deny first, then exceptions, with `skill` denied on `*` and then allowed for the named skill plus any skill the workflow loads by name. Scope `edit` to a directory only when the workflow writes to that directory and nowhere else. In that list, `*` already matches `/`, so a directory limit looks like `docs/plans/*`. A second asterisk is a literal `*` and would block the write. Use the directory that workflow writes to, not `docs/plans/`, unless that is the directory. When the workflow runs commands, set `shell` to `ask` on `*` and allow only the read-only commands it names. A prompt that says "only temporary files" is not a sandbox; say what the rules cannot stop. Claude Code gets a `tools` allowlist and no `permissionMode`. Cursor gets `readonly: false` when the workflow writes a file, and `readonly: true` when it does not.
6. When the workflow delegates to named child personas, allow exactly those children. OpenCode: `subagent` denied on `*`, then allowed for each child persona. Claude Code: add `Agent` to `tools`. Inside a Claude Code subagent, `Agent(<type>)` lists are not enforced, so name the allowed children in the prompt and say that the prompt, not the tool list, holds that rule. Cursor: name the children in the prompt. Nesting has limits: Claude Code allows three child levels by default, and a Cursor child's own child cannot launch another. When a child cannot launch the next persona, it returns a handback to its parent: the next persona, its inputs, and the reason.
7. When the skill sets `metadata.suggested-model`, pin `model` from it in each tool's own form:
   - **Claude Code** takes an alias: `haiku`, `sonnet`, `opus`, or `fable` for `anthropic/claude-haiku-*`, `anthropic/claude-sonnet-*`, `anthropic/claude-opus-*`, or `anthropic/claude-fable-*`. Claude Code runs Claude models only, so any other provider gets `opus`, and the file says which model it stands in for. Write `effort:` only when the skill sets `metadata.suggested-effort`.
   - **OpenCode** takes `provider/model`, plus `#<effort>` when `metadata.suggested-effort` is set: `openai/gpt-6-astra#max`. Never write a separate `reasoningEffort` line.
   - **Cursor** takes the model id without the provider, plus `[effort=<level>]` when the effort is set and that model offers it. When the model does not offer that effort, omit the bracket and say so in the file.

   When the skill has no hint, omit `model` in every file and say that no model is pinned. When the hint has a model but no effort, write no effort anywhere.
8. Write `agents/<persona>/skill` as one line, the skill directory name. Write `claude-code.md`, `opencode.md`, and `cursor.md`. All three or none. Claude Code and Cursor `name` equal the persona folder. OpenCode has no `name` field.

### Handling feedback

A hedged remark about a permission or a mode — "I'm not sure this should be a subagent" — never changes the folder by itself. Restate the workflow step that needs the tool or the mode, give a recommendation, and ask a yes/no question. A plain instruction — "make it primary" — is applied directly.

## Output format

```text
agents/<persona>/skill            one line: the skill directory name
agents/<persona>/claude-code.md
agents/<persona>/opencode.md
agents/<persona>/cursor.md
```

Claude Code and Cursor frontmatter include `name` (the persona), `description`, and `model` when a hint exists. Claude Code also includes `tools`, `skills: [<skill>]`, and `effort` only when a suggested effort exists. Cursor also includes `readonly`. OpenCode frontmatter includes `description`, `mode` (`primary`, `subagent`, or `all`), `model` as `provider/model` or `provider/model#<effort>` when a hint exists, and a `permissions` list of `action`, `resource`, and `effect`. The body of each file names the skill as its own word, says where questions go when it runs as a child, and does not paste the skill.

## Guardrails

MUST:

- MUST set `name` to `create-agent` and `metadata.version` to a quoted SemVer string.
- MUST keep `license` at `CC-BY-ND-4.0`.
- MUST write the persona under `agents/<persona>/`, never under `skills/<category>/<skill>/agents/`.
- MUST load the skill from the prompt or from Claude Code's `skills` field. Never paste the skill body.
- MUST write all three tool files, or none.
- MUST keep Claude Code and Cursor `name` equal to the persona folder.
- MUST write OpenCode `mode` as `primary` when the requested mode is `agent`.
- MUST map the Claude Code model to the alias of the same Claude family, and say so when the hint is not a Claude model.
- MUST route a child's owner questions back to its parent.
- MUST keep the description in third person and under 700 characters.

NEVER:

- NEVER set `metadata.suggested-model` on this skill. It does not ship a persona of its own.
- NEVER set Claude Code `permissionMode`.
- NEVER put `model`, `effort`, or `context` in a `SKILL.md`.
- NEVER write a separate `reasoningEffort` line in a new or updated OpenCode file.
- NEVER pin an effort the skill does not suggest, or one the tool's model does not offer.
- NEVER claim that a Claude Code subagent's `Agent(<type>)` list restricts which children it launches.
- NEVER invent a tool name. Claude Code tool names are `Read`, `Grep`, `Glob`, `Edit`, `Write`, `WebSearch`, `WebFetch`, `Bash`, `Skill`, and `Agent`. An unknown name stops the agent from launching.
- NEVER commit a secret, personal data, an internal URL, or an absolute local path.

## QA checklist

- [ ] `agents/<persona>/skill` is one line and names a skill directory that exists.
- [ ] `claude-code.md`, `opencode.md`, and `cursor.md` all exist.
- [ ] Claude Code and Cursor `name` equal the persona folder.
- [ ] OpenCode `mode` is `primary`, `subagent`, or `all`, and matches where the persona runs.
- [ ] Each body names the skill as its own word and does not paste the skill.
- [ ] Each child context says where owner questions go.
- [ ] OpenCode `permissions` use `allow`, `ask`, or `deny`, with broad rules before exceptions; delegation allows only the named children.
- [ ] Claude Code has a `tools` allowlist, `Agent` only when the workflow delegates, and no `permissionMode`.
- [ ] Cursor `readonly` matches whether the workflow writes a file.
- [ ] The Claude Code alias matches the hint's Claude family; OpenCode has no `reasoningEffort` line; no effort appears without a suggested effort.
- [ ] `bun run validate` reports 0 errors.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
