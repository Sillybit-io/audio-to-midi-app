## Prompt

> Add a release-notes skill to this repository. It should turn merged pull requests into a human-focused changelog and recommend the SemVer bump that goes with it.

This is the real Roadmap entry in this repository's `README.md`. Both runs were fresh OpenCode child sessions on 2026-09-29, each on its own clone of this repository at commit `3c14f1a`, told to work non-interactively and record assumptions. Both ran on `openai/gpt-6-sol` at variant `high`, OpenCode's model for its General subagent there. The with-skill run read plan-writer 0.5.0 from `.agents/skills/plan-writer/`. The without-skill run was told not to follow any `SKILL.md` as planning instructions. The outputs below are excerpts of the files each run wrote.

## Without skill

The baseline wrote a 71-line plan. It is a good plan: it read the release tooling, noticed that the release workflow infers the bump from commit messages, and drew a diagram. Its evidence section:

```markdown
## Repository evidence and integration points

- `README.md:140-142` already names `release-notes` on the roadmap, so the change should replace that placeholder with an entry in the skills table and overview; the badge at `README.md:6` must change from 14 to 15.
- `scripts/validate.ts:86-93,917-950,1113-1135,1161-1170,561-625` establishes allowed categories, required companion `examples.md`, exact attribution footer, layout, and badge count. Use `skills/workflow/release-notes/` (release preparation is a workflow), with `metadata.version: "0.1.0"` and `metadata.category: workflow`.
- `skills/workflow/skill-writer/SKILL.md:34-49,52-96,126-163` records the existing six-section skill shape, worked-example shape, bounded work and feedback convention. This is format evidence for the new skill, not planning instructions.
- `CHANGELOG.md:7-9` has an empty `[Unreleased]` section. `CONTRIBUTING.md:7-13` requires a matching changelog entry when adding a skill.
- `RELEASING.md:7-9,37-50,52-68,72-88` distinguishes per-skill version bumps from repository releases and describes `[Unreleased]` as the source moved by `prepare-release`. `scripts/prepare-release.ts:14-29` confirms the release preparer moves that section to a dated version and prints the GitHub Release body.
- `.github/workflows/release.yml:52-135` currently infers the repository bump from Conventional Commit messages, with patch as a fallback. The new skill must identify its proposal as advice, explain when an impact-based recommendation differs, and not promise that a workflow run with blank `version` will use its recommendation. A maintainer can enter the recommended version manually.
- `.github/workflows/ci.yml:14-19` runs validation, Bun tests, and Markdown lint on pull requests.
```

It names the README badge but not the second hard-coded count in `scripts/validate.test.ts`, so adding a fifteenth skill would pass `bun run validate` and fail `bun test`. Its citations carry no excerpts or digests, so nothing can check them mechanically.

## With skill

The run wrote a 281-line plan with 27 quoted citations and 6 coverage rows, and the bundled validator reported `docs/plans/2026-09-29-add-release-notes-skill.md: plan mode; 0 errors`. Its TL;DR and ledger:

```markdown
## TL;DR

- Effort: M — a new skill and worked example, catalogue and changelog updates, and one existing count test.
- Risk: medium — incomplete PR selection or title-based guesses can misstate a release; the catalogue count currently has two independent checks.
- Decisions made: the request is concrete, so early refinement was skipped; use `docs` because the output is release documentation; print a draft without editing a project's changelog; use a supplied verified PR list or GitHub merged PRs for an explicitly bounded release range; omit a model hint and persona because none is required. These are non-interactive defaults.
- Owner decisions pending: none — defaults recorded under Questions; revise on explicit direction.
- Cut from scope: a new release script, auto-publishing, a GitLab adapter, and changes to released changelog sections; these add integration or write risk beyond a drafting skill.
- Branch: `feat/add-release-notes-skill` — matches the observed `feat/<slug>` repository branches; no ticket is attached.

### IS / GAP ledger

| Gap | IS today (evidence) | GAP |
| --- | --- | --- |
| G1 | `README.md:141` calls release-notes a roadmap item; `RELEASING.md:62` says automation infers versions from commits, not user impact | No reusable, PR-grounded, human-focused release-notes drafting procedure with a defensible SemVer recommendation and uncertainty handling. |
| G2 | `skills/workflow/skill-writer/SKILL.md:38` sets new-skill version; `skills/workflow/skill-writer/SKILL.md:41` requires six sections; `scripts/validate.ts:943` rejects invalid examples | The new skill and its worked example must meet the house format and exercise success and missing/ambiguous-input cases. |
| G3 | `README.md:6` advertises 14; `scripts/validate.test.ts:710` asserts 14; `scripts/validate.ts:622` rejects a mismatched badge | Adding the 15th skill needs both the catalogue and the count test updated. |
| G4 | `CHANGELOG.md:7` has an empty `[Unreleased]`; `CONTRIBUTING.md:11` requires an entry when a skill is added | The addition must be recorded under `[Unreleased]` without altering published entries. |
```

The count test came from following the validator's consumers, recorded as a coverage row and a quoted citation:

```json
{
  "id": "V3",
  "paths": [
    "scripts/validate.ts",
    "scripts/validate.test.ts",
    "package.json",
    ".github/workflows/ci.yml"
  ],
  "searches": [
    "rg -n 'BADGE_COUNT|MISSING_EXAMPLES|skillCount|validate' scripts package.json .github/workflows/ci.yml"
  ],
  "producers": [
    "catalogue files"
  ],
  "consumers": [
    "validation",
    "hard-coded skill count test",
    "CI"
  ],
  "citationIds": [
    "C9",
    "C10",
    "C11",
    "C17",
    "C18"
  ],
  "state": "inspected"
}
```

```json
{
  "id": "C11",
  "kind": "source",
  "path": "scripts/validate.test.ts",
  "startLine": 710,
  "endLine": 710,
  "excerpt": "    expect(result.skillCount).toBe(14);",
  "sha256": "4df1f4d31d5f82103c6228b0001525476618a246b091320fce606b8a9b4c14fd"
}
```

Its baseline records the commands as they actually ran, including the one that failed:

```json
[
  {
    "command": "bun run validate",
    "exit": 0,
    "result": "14 skills validated, 0 errors",
    "limitations": "structure, not release-note quality"
  },
  {
    "command": "bun test",
    "exit": 0,
    "result": "115 pass, 0 fail across 4 files",
    "limitations": "current count assertion is fixed at 14"
  },
  {
    "command": "gh pr list --state merged --limit 2 --json number,title,body,mergedAt,baseRefName,url",
    "exit": 1,
    "result": "no git remote points to a known GitHub host",
    "limitations": "no live PR fixture available in this checkout"
  }
]
```

The todo that closes the count gap:

```markdown
### T2 — Register the skill and update the hard-coded count

- [ ] Open
- Do: update the `README.md` skill-count badge to 15, add the `docs` skill row, remove its fulfilled roadmap bullet, and update the existing 14-skill assertion/description in `scripts/validate.test.ts` to 15.
- Must not: change the validator's counting logic, the existing installer, or unrelated documentation.
- Closes gap: G3
- Depends on: T1, T3
- References: `README.md:6`, `README.md:71`, `README.md:141`, `scripts/validate.ts:622`, `scripts/validate.test.ts:710`, `package.json:5`, `CHANGELOG.md:7`.
- Acceptance: `bun run validate` exits 0 and prints `15 skills validated, 0 errors`; `bun test` exits 0 and reports `115 pass` and `0 fail`.
- QA scenario: happy — README row resolves to the new skill, roadmap has no release-notes bullet, badge and count assertion both equal 15. Failure — before changing the count assertion, `bun test scripts/validate.test.ts` fails on the existing 14-skill assertion; after fixing it, rerun and expect 0 failures.
- Commit: yes — `feat(docs): add release-notes skill` (include T1 and T3 files in this one commit).
```

<!-- markdownlint-disable-next-line MD024 -->
## Prompt

> Change app/core/rate_limit.py to a sliding-window limit instead of fixed windows. Keep check_rate_limit's signature.

A small Python service whose limiter has 23 relevant producers and consumers, including a plugin loaded by string, key-format readers, an ops script, and docs. Both runs were fresh OpenCode child sessions on 2026-09-29 on `openai/gpt-6-sol` at variant `high`, with identical copies of the project, told to work non-interactively. Scoring used an evaluator-only key that neither run could see.

<!-- markdownlint-disable-next-line MD024 -->
## Without skill

The baseline wrote a 206-line plan with `status: planned`. Its text names 9 of the 23 relevant paths. It never mentions the plugin registry and its `config/plugins.json` entry, the scheduler, the CLI, the route modules, or `config/limits.json`. It has no record of what was searched, so a reviewer cannot tell an unread consumer from an irrelevant one.

<!-- markdownlint-disable-next-line MD024 -->
## With skill

The run wrote a 776-line plan whose Evidence index cites all 23 relevant files with quoted excerpts and file digests, in 7 inspected coverage rows, with an empty frontier and three traced critical flows. The validator reported `0 errors`. One of its flows:

```json
{
  "id": "FL1",
  "requirementIds": [
    "MH1",
    "MH2",
    "MH3"
  ],
  "todoIds": [
    "T1",
    "T2"
  ],
  "evidenceIds": [
    "C8",
    "C6",
    "C1",
    "C7",
    "C2"
  ],
  "entry": "dispatch /messages, /search or /uploads",
  "startingState": "client has fewer than max_requests accepted timestamps in the prior window_seconds",
  "effects": [
    "middleware calls check_rate_limit with the client and current time",
    "store prunes timestamps outside (now-window_seconds, now], admits and records one timestamp only if capacity remains",
    "on admission response carries X-RateLimit-Remaining",
    "on denial RateLimited carries earliest legal retry and middleware returns 429 with safe integer Retry-After, with no handler invocation"
  ],
  "recovery": "client waits Retry-After and retries; next request prunes the oldest event and succeeds when capacity exists",
  "counterexample": "100 requests at t=59.9 then another at t=60.0 must be denied until t=119.9; boundary equality must admit"
}
```

A resumed run on the fixture's paused draft, whose frontier listed only the throttle callers and `RateLimited` importers, also reached 23 of 23. Its transcript shows the frontier searches and file reads before its first write to the plan. It excluded the plugin registry with a boundary reason:

```json
{
  "id": "V6",
  "paths": [
    "app/plugins/registry.py",
    "config/plugins.json",
    "app/plugins/audit.py",
    "app/jobs/cleanup.py"
  ],
  "searches": [
    "rg -n rate_limit|load_enabled|cleanup|audit app config"
  ],
  "producers": [
    "config/plugins.json",
    "app/jobs/scheduler.py"
  ],
  "consumers": [],
  "citationIds": [
    "C19",
    "C21",
    "C20",
    "C15"
  ],
  "state": "excluded",
  "reason": "Registry dynamically imports the limiter module but calls none of its functions; audit and cleanup use no limiter state. Registration name remains unchanged."
}
```
