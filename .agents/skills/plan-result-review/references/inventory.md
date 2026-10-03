# Change inventory

Read this file when you build the change inventory. The inventory lists every artifact the build could have touched, before you map any of them to the plan. A file-name list is not an inventory: each entry needs its before and after contents.

## Choose the baseline

Use the first that applies:

1. The plan's `## Build` record names a baseline snapshot. This is the only baseline that separates the owner's pre-build work from the build's changes.
2. The caller names a snapshot directory, or a base revision or range.
3. Nothing is named: stop and ask for an explicit base. Never guess `HEAD~1` or compare only the last commit.

A revision-only comparison covers committed changes but cannot certify that the owner's staged, unstaged, or untracked work survived. When the plan or the caller needs that claim and no snapshot exists, the verdict is INCOMPLETE.

## Run the helper

The helper ships with this skill. It needs Bun and the `plan-review` skill installed beside this one:

```text
bun <plan-result-review-base>/scripts/inventory-changes.ts <plan> --root <project> [--baseline <snapshot>] [--base <revision>] [--json]
```

It verifies the baseline snapshot, reads the current HEAD, index, and working tree for every path the baseline, the receipts, or git knows about, and prints each path whose layers changed. For each path, it prints:

- the changed layers: `head` (committed), `index` (staged), `worktree`;
- the baseline and current state of each layer: absent, file, or symlink, with mode, length, and digest;
- `owner work` flags when the baseline's index or working tree already differed from HEAD, and whether that work is preserved, restored to HEAD, or removed;
- a line diff for text, `binary` for binary files, the old and new target for a symlink, and a mode-only change;
- the commits since the base with their files, git's own staged, unstaged, and untracked lists, and the receipts.

Exit 0 means the inventory is complete. Exit 1 means the baseline is corrupt or the state is unsupported. Exit 2 means an argument, the plan, the baseline, or the `plan-review` dependency is missing. A missing or corrupt baseline object makes owner-work preservation uncertifiable: record INCOMPLETE with the snapshot path and the object named in the error.

## Without the helper

When Bun or `plan-review` is unavailable, build the same inventory by hand, and say so in the record:

- Committed: `git diff --name-status -z -M <base> HEAD` and `git log --format='%H %s' <base>..HEAD`.
- Staged: `git diff --cached --name-status -z -M`.
- Unstaged: `git diff --name-status -z`.
- Untracked: `git ls-files --others --exclude-standard -z`.
- Add every path in the baseline manifest and in each receipt snapshot, even when git lists it nowhere: a file restored to HEAD, a deleted untracked file, or a newly ignored file disappears from all four git lists.
- For each path, compare the manifest's `head`, `index`, and `worktree` entries with `git ls-files --stage`, `git ls-tree HEAD`, and the working-tree bytes (`shasum -a 256`). Read old contents from `objects/<sha256>` in the snapshot directory.

Use NUL-separated output so paths with spaces and newlines survive. Read contents, not only names: a rename, a mode change, or a symlink retarget can keep the name and change the behavior.

## Read what you inventoried

For every changed path, read the diff and enough of the file to judge its behavior. For every requirement, read the code that should satisfy it, including callers and consumers the plan's Evidence index names. Checks that execute code run in a disposable copy of the project, never in the project itself.
