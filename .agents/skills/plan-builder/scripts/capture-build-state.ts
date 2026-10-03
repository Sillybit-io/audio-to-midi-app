#!/usr/bin/env bun
/**
 * capture-build-state — the durable snapshot writer for plan-builder's D4
 * contract. It only reads the project and writes its own snapshot output: it
 * never stages, commits, restores, edits the project, or executes a
 * plan-supplied command. Every digest and inventory rule comes from the
 * plan-review validator bundled beside this skill
 * (`../../plan-review/scripts/validate-plan.ts`), so a captured snapshot and
 * the validator's resume check always agree.
 *
 *   bun capture-build-state.ts <plan> --root <project> --output <destination>
 *     [--carry <snapshot>]... [--include <path>]... [--report <path>]...
 *     [--run-id <id>] [--base-revision <revision>] [--approved-spec <digest>]
 *
 * <destination> is a name relative to the Git directory in a git project —
 * this script resolves it with `git rev-parse --git-path`, so give it
 * `silly-skills/plan-builds/<run-id>/<label>`, never a path that already
 * starts with `.git/` — or an absolute path outside the project in a
 * non-git one; D4 requires a durable location in both cases, never
 * temporary storage. Each `--carry <snapshot>` names an earlier snapshot
 * (same location form) whose paths and `includes` are inherited into this
 * capture's inventory, and whose matching blobs are hard-linked instead of
 * copied. `--report <path>` repeats to name a declared report/progress output
 * excluded from `stateDigest`, matching the Build record's
 * `administrative.reports`. `--run-id`, `--base-revision`, and
 * `--approved-spec` are recorded as given; the builder is responsible for
 * their correctness.
 *
 * Exit codes: 0 — captured and verified; the manifest location and digests
 * are on stdout as JSON. 1 — the project state is unsupported (an unmerged
 * index entry, a submodule, an unrepresentable file) or changed while this
 * ran. 2 — invalid arguments or an unreadable input, including a missing
 * plan, a missing plan-review dependency, or an existing destination.
 */

import { existsSync, mkdirSync, linkSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, isAbsolute, join, resolve } from "node:path";

const VALIDATOR = resolve(dirname(import.meta.path), "../../plan-review/scripts/validate-plan.ts");

export const USAGE = `Usage: capture-build-state <plan> --root <project> --output <destination>
  [--carry <snapshot>]... [--include <path>]... [--report <path>]...
  [--run-id <id>] [--base-revision <revision>] [--approved-spec <digest>]`;

type Manifest = {
  schemaVersion: 1;
  kind: "silly-skills.build-state";
  runId: string;
  createdAt: string;
  producer: { name: string; sha256: string };
  repository: { kind: "git"; rootCommits: string[]; branch: string | null } | { kind: "none" };
  baseRevision: string | null;
  headRevision: string | null;
  approvedSpecDigest: string;
  plan: { path: string; sha256: string; specDigest: string };
  administrative: { plan: string; reports: string[] };
  includes: string[];
  stateDigest: string;
  paths: unknown[];
};

function gitOut(root: string, args: string[]): string | null {
  const p = spawnSync("git", args, { cwd: root, env: { ...process.env, GIT_OPTIONAL_LOCKS: "0", GIT_CONFIG_NOSYSTEM: "1" } });
  return p.status === 0 ? p.stdout.toString().trim() : null;
}

function parseArgs(argv: string[]): Record<string, unknown> | null {
  const out: Record<string, unknown> = { carry: [] as string[], include: [] as string[], report: [] as string[] };
  const rest: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === "--root") out.root = next();
    else if (a === "--output") out.output = next();
    else if (a === "--carry") (out.carry as string[]).push(next());
    else if (a === "--include") (out.include as string[]).push(next());
    else if (a === "--report") (out.report as string[]).push(next());
    else if (a === "--run-id") out.runId = next();
    else if (a === "--base-revision") out.baseRevision = next();
    else if (a === "--approved-spec") out.approvedSpec = next();
    else if (a === "--help" || a === "-h") return null;
    else if (a.startsWith("--")) return null;
    else rest.push(a);
  }
  if (rest.length !== 1) return null;
  out.plan = rest[0];
  return out;
}

export function run(argv: string[], write: (text: string) => void = (t) => console.log(t)): number {
  const args = parseArgs(argv);
  if (!args) {
    write(USAGE);
    return argv.includes("--help") || argv.includes("-h") ? 0 : 2;
  }
  if (!args.output) {
    write(`error: --output is required\n${USAGE}`);
    return 2;
  }
  const root = resolve(String(args.root ?? "."));
  if (!existsSync(VALIDATOR)) {
    write(`error: the plan-review skill is not installed beside this skill (expected ${VALIDATOR})`);
    return 2;
  }
  const planAbs = resolve(root, String(args.plan));
  if (!existsSync(planAbs)) {
    write(`error: cannot read plan ${String(args.plan)}`);
    return 2;
  }
  const planRel = planAbs.slice(root.length + 1);
  // biome-ignore lint: dynamic require resolves the bundled validator at its installed path
  const v = require(VALIDATOR);
  const inGit: boolean = v.isGitRoot(root);
  const outputArg = String(args.output);
  let destAbs: string;
  if (isAbsolute(outputArg)) destAbs = outputArg;
  else if (inGit) {
    const gitDir = gitOut(root, ["rev-parse", "--git-dir"]);
    const gitDirName = gitDir ? gitDir.split("/").pop() : null;
    if (gitDirName && (outputArg === gitDirName || outputArg.startsWith(`${gitDirName}/`))) {
      write(`error: --output ${outputArg} already includes the Git directory; give a name relative to it instead (git rev-parse --git-path resolves that for you), e.g. silly-skills/plan-builds/<run-id>/<label>, not ${gitDirName}/silly-skills/plan-builds/<run-id>/<label>`);
      return 2;
    }
    const gp = gitOut(root, ["rev-parse", "--git-path", outputArg]);
    if (!gp) {
      write(`error: cannot resolve --output ${outputArg} as a git path`);
      return 2;
    }
    destAbs = resolve(root, gp);
  } else {
    write(`error: --output must be an absolute path in a non-git project (D4 requires a durable location outside the project)`);
    return 2;
  }
  if (existsSync(destAbs)) {
    write(`error: destination exists: ${outputArg}`);
    return 2;
  }

  const carryLocations = args.carry as string[];
  const carryPaths = new Set<string>();
  const includes = new Set<string>(args.include as string[]);
  const carriedManifests: { dir: string; manifest: Manifest }[] = [];
  for (const loc of carryLocations) {
    const dir = v.resolveSnapshot(root, loc, inGit);
    let verified: { manifest: Manifest };
    try {
      verified = v.verifySnapshot(dir);
    } catch (error) {
      write(`error: cannot read --carry snapshot ${loc}: ${(error as Error).message}`);
      return 2;
    }
    carriedManifests.push({ dir, manifest: verified.manifest });
    for (const row of verified.manifest.paths as { path: string }[]) carryPaths.add(row.path);
    for (const inc of verified.manifest.includes ?? []) includes.add(inc);
  }

  let inv: { body: { headRevision: string | null; paths: unknown[] }; blobs: Map<string, Buffer> };
  try {
    inv = v.inventoryState(root, { carry: [...carryPaths], include: [...includes] });
  } catch (error) {
    if (error instanceof v.UnsupportedState) {
      write(`unsupported state: ${(error as Error).message}`);
      return 1;
    }
    write(`error: ${(error as Error).message}`);
    return 1;
  }

  const reports = args.report as string[];
  const planBytes = readFileSync(planAbs);
  const repository: Manifest["repository"] = inGit
    ? { kind: "git", rootCommits: v.gitRepositoryIdentity(root).rootCommits, branch: gitOut(root, ["symbolic-ref", "-q", "--short", "HEAD"]) }
    : { kind: "none" };
  const manifest: Manifest = {
    schemaVersion: 1,
    kind: "silly-skills.build-state",
    runId: String(args.runId ?? ""),
    createdAt: new Date().toISOString(),
    producer: { name: "capture-build-state.ts", sha256: v.sha256(readFileSync(import.meta.path)) },
    repository,
    baseRevision: (args.baseRevision as string | undefined) ?? null,
    headRevision: inv.body.headRevision,
    approvedSpecDigest: String(args.approvedSpec ?? ""),
    plan: { path: planRel, sha256: v.sha256(planBytes), specDigest: v.canonicalSpecDigest(planBytes.toString("utf8")) },
    administrative: { plan: planRel, reports },
    includes: [...includes].sort(),
    stateDigest: "",
    paths: inv.body.paths,
  };
  manifest.stateDigest = v.stateDigest(inv.body, planRel, (d: string) => inv.blobs.get(d) as Buffer, reports);

  const partial = `${destAbs}.partial-${process.pid}`;
  try {
    mkdirSync(join(partial, "objects"), { recursive: true });
    for (const [digest, data] of inv.blobs) {
      const target = join(partial, "objects", digest);
      let linked = false;
      for (const c of carriedManifests) {
        const src = join(c.dir, "objects", digest);
        if (existsSync(src)) {
          try {
            linkSync(src, target);
            linked = true;
            break;
          } catch {
            // Fall through to a plain write, e.g. across filesystems.
          }
        }
      }
      if (!linked) writeFileSync(target, data);
    }
    const raw = `${JSON.stringify(manifest, null, 2)}\n`;
    writeFileSync(join(partial, "manifest.json"), raw);

    // Verify every written object before anything reads this snapshot as real.
    for (const row of manifest.paths as { path: string; head: unknown; index: unknown; worktree: unknown }[]) {
      for (const layer of [row.head, row.index, row.worktree] as { state: string; length?: number; sha256?: string }[]) {
        if (layer.state === "file" || layer.state === "symlink") {
          const data = readFileSync(join(partial, "objects", layer.sha256 as string));
          if (data.length !== layer.length || v.sha256(data) !== layer.sha256) {
            throw new Error(`written object for ${row.path} does not verify`);
          }
        }
      }
    }

    // Re-inventory and recompute: the project must not have changed underneath this capture.
    const again = v.inventoryState(root, { carry: [...carryPaths], include: [...includes] });
    const againDigest = v.stateDigest(again.body, planRel, (d: string) => again.blobs.get(d) as Buffer, reports);
    if (againDigest !== manifest.stateDigest) {
      rmSync(partial, { recursive: true, force: true });
      write("error: project state changed during capture");
      return 1;
    }

    renameSync(partial, destAbs);
  } catch (error) {
    rmSync(partial, { recursive: true, force: true });
    write(`error: ${(error as Error).message}`);
    return 1;
  }

  write(
    JSON.stringify(
      { snapshot: outputArg, manifestSha256: v.sha256(readFileSync(join(destAbs, "manifest.json"))), stateDigest: manifest.stateDigest, paths: manifest.paths.length, objects: inv.blobs.size },
      null,
      2,
    ),
  );
  return 0;
}

if (import.meta.main) process.exit(run(process.argv.slice(2)));
