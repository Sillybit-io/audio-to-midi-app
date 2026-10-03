## Prompt

> Write a new skill called `changelog-drafter` that turns a list of merged PR titles into a changelog entry.

## Without skill

An agent with no house style still writes a usable file. It reaches for the frontmatter shape it has seen in other agent-skill catalogues — `name` and `description`, plus whatever else looks useful — and invents a body outline that suits the topic. The prose below is competent and the instructions are sound. What is missing is the contract: nothing in it is checkable by a validator, and nothing matches the other skills already in this repository.

````markdown
---
name: changelog-drafter
description: Drafts changelog entries from merged pull requests.
version: 1.0.0
author: platform-team
tags: [changelog, release, git]
---

# Changelog Drafter

## Overview

This skill helps you generate a polished changelog from your merged pull requests. It is a fast way to keep release notes current without chasing every author for a summary.

## Instructions

1. Collect the merged PR titles for the release.
2. Group them into Added, Changed, Fixed, and Removed.
3. Rewrite each title so it reads as a user-facing change.
4. Output the entry under a version heading.

## Examples

Input: `feat(api): add pagination to the users endpoint`

Output: `- Added pagination to the users endpoint.`

## Tips

- Keep entries short.
- Mention breaking changes first.
````

Measured against this repository's contract, that draft deviates in eight ways:

- `version` sits at the top level instead of under `metadata`, and it is unquoted.
- `license` is absent, so the file claims no licence at all.
- `metadata.category` is absent, so nothing ties the skill to a category directory.
- `author` and `tags` are invented keys that nothing in this repository reads.
- The body headings are `Overview`, `Instructions`, `Examples`, and `Tips` — none of the six required headings, in none of the required order.
- There is no `Guardrails` section and no `QA checklist` section, so the skill states no hard limits and hands the agent nothing to self-check against.
- The attribution footer is missing, so `bun run validate` fails with `FOOTER`.
- No `examples.md` was written, so `bun run validate` also fails with `MISSING_EXAMPLES`.

## With skill

Following skill-writer against the same request produces the same idea inside the contract: the five required frontmatter keys, the six H2 sections in the fixed order, and the footer as the final line. The section bodies below are abbreviated. The structure is not.

````markdown
---
name: changelog-drafter
description: Turn merged pull request titles into one changelog entry. Use when you draft release notes, write the CHANGELOG entry for a release, summarise merged pull requests for users, or decide which SemVer bump a set of merges deserves.
license: CC-BY-ND-4.0
metadata:
  version: "0.1.0"
  category: docs
---

# changelog-drafter

## Purpose

changelog-drafter turns a list of merged pull request titles into one Keep a Changelog entry. It sorts each merge into a change group, rewrites the title in the language a user of the software would recognise, and names the SemVer bump the set of changes forces. It serves the person cutting a release.

## When to use / when NOT to use

Use changelog-drafter when you:

- Cut a release and need the `CHANGELOG.md` entry for it.
- Hold a list of merged pull request titles and no changelog text yet.
- Need to know whether a release is a patch, a minor, or a major.

Do NOT use changelog-drafter when you:

- Write the announcement or blog post for a release.
- Write commit messages or pull request titles.
- Edit a changelog entry that already shipped.

## Workflow

1. Collect the merged pull request titles for the release range.
2. Drop every merge that changes nothing a user can observe.
3. Sort each remaining merge into Added, Changed, Deprecated, Removed, Fixed, or Security.
4. Rewrite each title as one sentence describing the change from the user's side.
5. Mark every breaking change and list it first inside its group.
6. Name the SemVer bump. Major for a breaking change, minor for a new capability, patch for fixes only.
7. Write the entry under a version heading carrying the release date.

## Output format

```markdown
## [<version>] - <YYYY-MM-DD>

### Added

- <One sentence per change, written from the user's side.>

### Fixed

- <One sentence per change, written from the user's side.>

Suggested bump: <major | minor | patch> — <the single change that forces it>
```

Omit any group that has no entries. Never print an empty heading.

## Guardrails

MUST:

- MUST write every entry from the point of view of someone using the software.
- MUST mark a breaking change and place it first within its group.
- MUST state the suggested bump and name the one change that forces it.

NEVER:

- NEVER invent a change that no merged pull request made.
- NEVER paste a raw commit message or a bare pull request number as the entry text.
- NEVER edit a version entry that already shipped.

## QA checklist

- [ ] Every merge in the range is either represented or deliberately dropped.
- [ ] No entry names a file, a function, or an internal module.
- [ ] Breaking changes are marked and listed first.
- [ ] The suggested bump matches the most severe change in the entry.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
````

Two consequences reach past the file itself. `metadata.version` starts at `"0.1.0"` because the skill is new, so no `CHANGELOG.md` bump line is owed for it yet. And `changelog-drafter` would need its own `examples.md` beside that `SKILL.md` before it could be committed: one worked scenario, a real list of merged pull request titles as the shared input, the flat ungrouped list an unguided agent returns under `## Without skill`, and the grouped entry with its SemVer verdict under `## With skill`.
