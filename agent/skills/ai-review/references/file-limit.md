# File limit

Read this file before the stated intent, the conventions, the diff, or any changed file. The count command's stdout is one integer. Do not print patches, file names, or a pull request body. Do not set `pipefail`. `git check-ignore` exits 1 when no path is ignored. That exit is a finished count. Read the integer. Exit 128, or a `gh` or `glab` error, means the count was not obtained.

## What counts

Count changed paths in the set the user asked to review. A rename is one path. Then drop a path only when `git check-ignore -v --no-index` matches it from a `.gitignore` inside the repository. `--no-index` is required so a tracked file that was force-added still matches. A match from `.git/info/exclude` or a global excludes file stays in the count. Those rules differ by machine. Untracked ignored files are already absent from `git diff`.

The filter uses the checkout's `.gitignore`. A pull request reviewed while another branch is checked out still gets a count. Compare `git rev-parse HEAD` with `gh pr view <number> --json headRefOid --jq .headRefOid`. When they differ, the reply says in one line: `The ignore filter used the checkout's .gitignore, not the pull request head.`

300 or fewer continues the review. More than 300 stops the whole review. No subset is reviewed. Lockfiles count unless a repository `.gitignore` matches them.

The keep rule below was checked against `git check-ignore -v --no-index --non-matching --stdin`. A non-match is a line `::` then a tab then the path. A match is `<source>:<line>:<pattern>` then a tab then the path. Keep the path when the source is `::`, starts with `/`, or does not end in the file name `.gitignore`.

```awk
function keep_line() {
  left = $1
  if (left == "::") return 1
  split(left, a, ":")
  source = a[1]
  base = source
  sub(/.*\//, "", base)
  if (source ~ /^\// || base != ".gitignore") return 1
  return 0
}
```

Count mode:

```awk
function keep_line() {
  left = $1
  if (left == "::") return 1
  split(left, a, ":")
  source = a[1]
  base = source
  sub(/.*\//, "", base)
  if (source ~ /^\// || base != ".gitignore") return 1
  return 0
}
keep_line() { keep++ }
END { print keep + 0 }
```

Path mode, for the diff only, uses the same `keep_line` and then `keep_line() { printf "%s\0", $2 }`.

## Names, then the filter

Build the name list, the ignore filter, and the count in one pipeline.

- GitHub. `gh api` accepts `--paginate` and `--jq`. The pulls files JSON includes `filename` and `patch`. Select only `filename`.

```sh
gh api --paginate --jq '.[].filename' "repos/{owner}/{repo}/pulls/<number>/files?per_page=100" \
  | git check-ignore -v --no-index --non-matching --stdin \
  | awk -F '\t' '<the count-mode program above>'
```

Do not pass `files` to `gh pr view --json`. That list is `files(first: 100)` with no next page. Do not use `gh pr diff` to count. `--name-only` still downloads the diff. Do not use `gh pr view --json changedFiles`. Ignored paths only raise that scalar.

- GitLab. `glab api` replaces `:fullpath` in the current repository. It has `--paginate` and `--output ndjson`. It has no `--jq`. The diffs endpoint is `GET /projects/:id/merge_requests/:merge_request_iid/diffs`, and each object has `new_path`, `old_path`, and `diff`. Print paths only. `changes_count` on the merge request is a string. Empty means the diff is not ready. `1000+` means the list may be capped.

```sh
glab api "projects/:fullpath/merge_requests/<iid>" | jq -r '.changes_count'
```

When that value is empty, `null`, or `1000+`, the count is unavailable. Otherwise:

```sh
glab api --paginate --output ndjson "projects/:fullpath/merge_requests/<iid>/diffs?per_page=100" \
  | jq -r '.new_path // .old_path' \
  | git check-ignore -v --no-index --non-matching --stdin \
  | awk -F '\t' '<the count-mode program above>'
```

Do not run `glab mr view` or `glab mr diff` for the count. `glab mr view` prints the description. If `jq` is missing, stop. Do not print the API body. If the number of diff entries is lower than the numeric `changes_count`, the count is unavailable.

- Local, with `--find-renames`, then the same filter. Branch: `git diff --name-only --find-renames <base>...HEAD` (three dots). One commit: `git show --name-only --pretty=format: --find-renames <sha>`. That list is empty for a merge commit. When `git rev-parse --verify --quiet <sha>^2` succeeds, use `git diff-tree --no-commit-id --name-only -r -m --first-parent --find-renames <sha>` instead of treating 0 as small. Working tree: `git diff --name-only --find-renames HEAD`, one unique list. Do not add staged and unstaged lists together. Untracked files count only when the user asked to include them: add `git ls-files --others --exclude-standard` to that same unique list before the filter.

## When the count is over 300

Do not gather intent, conventions, or the diff. Do not open a changed file. Do not re-check prior findings against the code. Check auth only for the host you will post to.

Write this note. `N` is the count. Do not list the files.

````markdown
## AI code review

> AI-generated note. The review stopped before reading the diff because this change is over the file limit. Nothing here is a finding.

Sorry — this change is too big to review. It touches N files after gitignore matches are removed, and ai-review stops automatically above 300 files. No files were reviewed.

Split the change into smaller pieces, or ask again on a smaller slice.
````

Say it in the chat reply. When the target is a pull request or merge request, post it with the posting modes in this skill, from a body file. Never approve or merge. A branch, commit, or working-tree review is not posted. Say there was nothing to post to.

Write or update `reports/ai-review-<id>.md`. Do not mark prior findings `resolved` or `still present`.

````markdown
### AI review report

**Report id:** `<id>`
**Target:** <pull request, merge request, commit, or branch reference>
**Platform:** GitHub, GitLab, or local
**Created:** <date of the first run>
**Last updated:** <date of this run>
**Outcome:** stopped — N files after the gitignore filter, limit 300. No review was run.

### Run history

| Run | Date | Reviewed commit | Posting mode | Files reviewed / skipped | Findings |
| --- | --- | --- | --- | --- | --- |
| <n> | <date> | `<sha>` or not read | a, b, or c | stopped (N files) | none |

### Notes for the next run

- This run stopped because the change had N files after the gitignore filter. The limit is 300.
- If the next run's count is 300 or fewer, review from scratch. Do not treat this report as findings.
````

## When the count cannot be obtained

Do not start the review, and do not call the change too big. Use the same disclosure shape, with this body:

````markdown
Sorry — the file count could not be read, so the review did not start. This does not mean the change is too big.
````

When `gh` or `glab` is missing or not authenticated, name that tool. Post and write the report the same way, with outcome `count unavailable`.

## When the review runs

A gitignored changed path is still a queue row: `skipped - matches gitignore`. It is not one of the 300. Do not open it to decide the skip. The other skip reasons stay generated output, vendored code, and lockfiles.

Read the diff of the counted paths only. When the filter excluded nothing, use `gh pr diff <number>`, `glab mr diff <id>`, or `git diff <base>...HEAD` as the skill already says. When it excluded any path, do not use those unfiltered commands. Feed the kept paths, NUL-separated, to `xargs -0 git diff --find-renames <base>...<head> --`. `xargs -0` was checked with a path that contains a space. If the kept-path list is empty, do not run `git diff` with no path arguments. That prints the whole diff. When the commits are not local, print `filename` and `patch` from the pulls files API, or `new_path` and `diff` from the merge request diffs endpoint, only for kept paths.

## Stop checklist

- [ ] The count command printed one integer, or the run stopped because the count was unavailable.
- [ ] No patch, file list, or pull request body was printed while counting.
- [ ] Gitignored paths were removed before the 300 comparison. A match from `.git/info/exclude` or a global excludes file was kept.
- [ ] Over 300: no intent, conventions, diff, or changed file was read, and prior findings were not re-checked.
- [ ] The note names the count and the 300 limit, says nothing was reviewed, and does not list the files.
- [ ] The disclosure does not say the diff was read.
- [ ] The note was said in chat, posted when the target is a pull request or merge request, and written to `reports/ai-review-<id>.md`.
- [ ] Nothing was approved or merged. No code was edited.
