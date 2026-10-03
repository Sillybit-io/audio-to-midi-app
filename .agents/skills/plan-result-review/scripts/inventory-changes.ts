#!/usr/bin/env bun
/**
 * inventory-changes — lists every path whose HEAD, index, or working-tree
 * layer differs from a plan-builder baseline snapshot, with content diffs.
 *
 *   bun inventory-changes.ts <plan> [--root <project>] [--baseline <snapshot>] [--base <revision>] [--json]
 *
 * Read-only. It uses the validator bundled with the plan-review skill, found
 * beside this skill (`../../plan-review/scripts/validate-plan.ts`), for
 * snapshot verification and the state inventory. With --base and no
 * snapshot, it lists committed and current changes but cannot tell the
 * owner's pre-build work from the build's: `ownerWorkCertifiable` is false.
 *
 * Exit codes: 0 — inventory complete; 1 — the baseline snapshot is corrupt or
 * the project state is unsupported; 2 — invalid arguments, a missing plan,
 * baseline, or plan-review dependency.
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

type Layer = { state: string; mode?: string; length?: number; sha256?: string };
type Row = { path: string; head: Layer; index: Layer; worktree: Layer };

const VALIDATOR = resolve(dirname(import.meta.path), "../../plan-review/scripts/validate-plan.ts");

export const USAGE = `Usage: inventory-changes <plan> [--root <project>] [--baseline <snapshot>] [--base <revision>] [--json]

Lists every path whose HEAD, index, or working-tree layer changed since the
build baseline recorded in the plan's Build record, or since --baseline.
With only --base, lists committed and current changes without owner-work
attribution. Read-only; needs the plan-review skill installed beside this one.`;

function git(root: string, args: string[]): { code: number; out: string } {
  const p = spawnSync("git", args, { cwd: root, env: { ...process.env, GIT_OPTIONAL_LOCKS: "0" }, encoding: "utf8", maxBuffer: 1 << 30 });
  return { code: p.status ?? 1, out: p.stdout ?? "" };
}

function same(a: Layer | undefined, b: Layer | undefined): boolean {
  const x = a ?? { state: "absent" };
  const y = b ?? { state: "absent" };
  return x.state === y.state && x.mode === y.mode && x.sha256 === y.sha256;
}

function describe(l: Layer): string {
  if (l.state === "file" || l.state === "symlink") return `${l.state} ${l.mode} ${l.length}B ${String(l.sha256).slice(0, 12)}`;
  return l.state;
}

function isText(buf: Buffer): boolean {
  return !buf.subarray(0, 8192).includes(0);
}

function unifiedDiff(before: string, after: string, path: string): string {
  const a = before.split("\n");
  const b = after.split("\n");
  // Longest-common-subsequence diff; fixture-sized files only need a simple one.
  const n = a.length;
  const m = b.length;
  if (n * m > 4_000_000) return `(diff omitted: ${n} and ${m} lines)`;
  const dp: number[][] = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
  const out = [`--- baseline/${path}`, `+++ current/${path}`];
  let i = 0;
  let j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && a[i] === b[j]) {
      i++;
      j++;
    } else if (j < m && (i === n || dp[i][j + 1] >= dp[i + 1][j])) out.push(`+${j + 1}: ${b[j++]}`);
    else out.push(`-${i + 1}: ${a[i++]}`);
  }
  return out.join("\n");
}

export function main(argv: string[], write: (s: string) => void = (s) => console.log(s)): number {
  let plan: string | null = null;
  let root = process.cwd();
  let baselineArg: string | null = null;
  let base: string | null = null;
  let json = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--help" || a === "-h") {
      write(USAGE);
      return 0;
    }
    if (a === "--root") root = argv[++i];
    else if (a === "--baseline") baselineArg = argv[++i];
    else if (a === "--base") base = argv[++i];
    else if (a === "--json") json = true;
    else if (a.startsWith("-") || plan) {
      write(`error: unexpected argument '${a}'\n${USAGE}`);
      return 2;
    } else plan = a;
  }
  if (!plan || !root) {
    write(`error: a plan path is required\n${USAGE}`);
    return 2;
  }
  root = resolve(root);
  if (!existsSync(VALIDATOR)) {
    write(`error: the plan-review skill is not installed beside this skill (expected ${VALIDATOR})`);
    return 2;
  }
  const planAbs = resolve(root, plan);
  if (!existsSync(planAbs)) {
    write(`error: cannot read plan ${plan}`);
    return 2;
  }
  const v = require(VALIDATOR);
  const planRel = planAbs.slice(root.length + 1);
  const parsed = v.parsePlan(readFileSync(planAbs, "utf8"));
  const record = v.buildRecord(parsed);
  const recordValue = record && !("error" in record) ? (record.value as Record<string, unknown>) : null;
  const inGit = v.isGitRoot(root);

  const report: Record<string, unknown> = { schemaVersion: 1, plan: planRel, root: ".", baseline: null, ownerWorkCertifiable: false };
  let baselineManifest: { paths: Row[]; baseRevision: string | null; headRevision: string | null; includes?: string[] } | null = null;
  let baselineDir = "";
  const snapshotRef = baselineArg ?? ((recordValue?.baseline as Record<string, string> | undefined)?.snapshot ?? null);
  if (snapshotRef) {
    baselineDir = v.resolveSnapshot(root, snapshotRef, inGit);
    try {
      const verified = v.verifySnapshot(baselineDir);
      const expected = (recordValue?.baseline as Record<string, string> | undefined)?.manifestSha256;
      if (!baselineArg && expected && verified.manifestSha256 !== expected) {
        write(`error: baseline manifest ${snapshotRef} does not match the Build record's digest`);
        return 1;
      }
      baselineManifest = verified.manifest;
      report.baseline = { snapshot: snapshotRef, manifestSha256: verified.manifestSha256, baseRevision: verified.manifest.baseRevision };
      report.ownerWorkCertifiable = true;
    } catch (error) {
      const message = (error as Error).message;
      const missing = /missing/.test(message) && !/object/.test(message);
      write(`${missing ? "error" : "error: corrupt baseline"}: ${message}. Owner-work preservation cannot be certified; the result review is INCOMPLETE until the snapshot is restored.`);
      return missing ? 2 : 1;
    }
  } else if (!base) {
    write("error: no Build record baseline and no --base; pass an explicit comparison base rather than guessing");
    return 2;
  }
  const baseRevision = base ?? baselineManifest?.baseRevision ?? null;
  report.baseRevision = baseRevision;

  // Receipt snapshots add paths that later appeared and disappeared.
  const carry = new Set<string>(baselineManifest?.paths.map((r) => r.path) ?? []);
  const includes = new Set<string>(baselineManifest?.includes ?? []);
  for (const r of (recordValue?.receipts as Record<string, unknown>[] | undefined) ?? []) {
    for (const side of ["before", "after"]) {
      const ref = r[side] as Record<string, string> | null;
      if (!ref?.snapshot) continue;
      try {
        const m = v.verifySnapshot(v.resolveSnapshot(root, ref.snapshot, inGit)).manifest;
        for (const row of m.paths as Row[]) carry.add(row.path);
      } catch {
        // A receipt snapshot that cannot be read only narrows the carried path set.
      }
    }
  }
  let current: { body: { headRevision: string | null; paths: Row[] }; blobs: Map<string, Buffer> };
  try {
    current = v.inventoryState(root, { carry: [...carry], include: [...includes] });
  } catch (error) {
    write(`error: ${(error as Error).message}`);
    return 1;
  }
  report.headRevision = current.body.headRevision;

  const baseRows = new Map((baselineManifest?.paths ?? []).map((r) => [r.path, r]));
  const readBase = (sha: string | undefined): Buffer | null => (sha && baselineDir ? v.readSnapshotBlob(baselineDir, sha) : null);
  const changes: Record<string, unknown>[] = [];
  for (const row of current.body.paths as Row[]) {
    if (row.path === planRel) continue;
    const b = baseRows.get(row.path);
    // With a baseline, a layer changed when it differs from the baseline's layer.
    // In revision-only mode, only uncommitted index and working-tree changes
    // relative to HEAD can be seen here; committed ones are in `commits`.
    const layers = baselineManifest
      ? (["head", "index", "worktree"] as const).filter((l) => !same(b?.[l], row[l]))
      : (["index", "worktree"] as const).filter((l) => !same(row.head, row[l]));
    if (layers.length === 0) continue;
    const ownerAtBaseline = b ? !same(b.head, b.index) || !same(b.index, b.worktree) : false;
    const entry: Record<string, unknown> = {
      path: row.path,
      changedLayers: layers,
      baseline: b ? { head: describe(b.head), index: describe(b.index), worktree: describe(b.worktree) } : null,
      current: { head: describe(row.head), index: describe(row.index), worktree: describe(row.worktree) },
      ownerWorkAtBaseline: ownerAtBaseline,
      ownerWorkPreserved: ownerAtBaseline ? same(b?.index, row.index) && same(b?.worktree, row.worktree) : null,
      restoredToHead: b ? ownerAtBaseline && row.head.state !== "absent" && same(row.index, row.head) && same(row.worktree, row.head) : false,
      removed: b ? b.worktree.state !== "absent" && row.worktree.state === "absent" : false,
    };
    const before = b?.worktree.state === "file" ? readBase(b.worktree.sha256) : null;
    const after = row.worktree.state === "file" ? current.blobs.get(row.worktree.sha256 as string) ?? null : null;
    if (b?.worktree.state === "symlink" || row.worktree.state === "symlink") {
      entry.symlink = {
        before: b?.worktree.state === "symlink" ? readBase(b.worktree.sha256)?.toString() : null,
        after: row.worktree.state === "symlink" ? current.blobs.get(row.worktree.sha256 as string)?.toString() : null,
      };
    } else if (b && b.worktree.mode && row.worktree.mode && b.worktree.mode !== row.worktree.mode && b.worktree.sha256 === row.worktree.sha256) {
      entry.modeOnly = `${b.worktree.mode} → ${row.worktree.mode}`;
    } else if ((before && !isText(before)) || (after && !isText(after))) {
      entry.binary = true;
    } else if (layers.includes("worktree") || !b) {
      entry.diff = unifiedDiff(before?.toString("utf8") ?? "", after?.toString("utf8") ?? "", row.path);
    }
    changes.push(entry);
  }
  report.changes = changes;

  if (inGit && baseRevision) {
    const log = git(root, ["log", "--format=%H %s", `${baseRevision}..HEAD`]);
    report.commits = log.out
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        const [sha, ...subject] = line.split(" ");
        const files = git(root, ["diff-tree", "--no-commit-id", "--name-status", "-r", "-M", sha]).out.trim().split("\n").filter(Boolean);
        return { sha, subject: subject.join(" "), files };
      });
    const z = (args: string[]) => git(root, args).out.split("\0").filter(Boolean);
    report.gitInventory = {
      committed: z(["diff", "--name-status", "-z", "-M", baseRevision, "HEAD"]),
      staged: z(["diff", "--cached", "--name-status", "-z", "-M"]),
      unstaged: z(["diff", "--name-status", "-z"]),
      untracked: z(["ls-files", "--others", "--exclude-standard", "-z"]),
    };
  }
  report.receipts = ((recordValue?.receipts as Record<string, unknown>[] | undefined) ?? []).map((r) => ({
    seq: r.seq,
    todo: r.todo,
    event: r.event,
    state: r.state,
    commit: r.commit,
  }));

  if (json) write(JSON.stringify(report, null, 2));
  else {
    write(`plan ${planRel}; baseline ${report.baseline ? (report.baseline as Record<string, string>).snapshot : "none (revision-only)"}; base ${baseRevision ?? "none"}; HEAD ${report.headRevision ?? "none"}`);
    write(`owner work certifiable: ${report.ownerWorkCertifiable}`);
    write(`${changes.length} changed paths:`);
    for (const c of changes) {
      const flags = [
        (c.changedLayers as string[]).join("+") || "new",
        c.ownerWorkAtBaseline ? (c.ownerWorkPreserved ? "owner work preserved" : "OWNER WORK CHANGED") : "",
        c.restoredToHead ? "restored to HEAD" : "",
        c.removed ? "removed from the working tree" : "",
        c.binary ? "binary" : "",
        c.modeOnly ? `mode ${c.modeOnly}` : "",
        c.symlink ? `symlink ${(c.symlink as Record<string, string>).before} → ${(c.symlink as Record<string, string>).after}` : "",
      ].filter(Boolean);
      write(`- ${c.path}: ${flags.join("; ")}`);
      write(`    baseline: ${c.baseline ? JSON.stringify(c.baseline) : "not in baseline"}`);
      write(`    current:  ${JSON.stringify(c.current)}`);
      if (c.diff) write(String(c.diff).split("\n").map((l) => `    ${l}`).join("\n"));
    }
    for (const c of (report.commits as Record<string, unknown>[] | undefined) ?? []) write(`commit ${String(c.sha).slice(0, 12)} ${c.subject}: ${(c.files as string[]).join(", ")}`);
  }
  return 0;
}

if (import.meta.main) {
  process.exit(main(process.argv.slice(2)));
}
