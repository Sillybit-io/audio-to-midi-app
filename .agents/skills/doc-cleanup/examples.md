## Prompt

> Clean up this doc — it's gotten messy.

The request arrived with the document and with the repository it describes. Both branches below receive this
same input, and neither is given anything the other lacks. `ferrule` is a hypothetical CLI used here so the
evidence can be shown in full; nothing in this scenario refers to a real package.

The document, `docs/getting-started.md`:

````markdown
## Getting started

Ferrule is a powerful command-line tool that converts your Markdown changelogs into clean, production-ready HTML. Getting up and running is seamless — you will be generating your first page in under a minute.

To get started, clone the repository and install the dependencies. Then run `npm run setup` to create the local cache directory and fetch the default stylesheet. Once setup has completed, you can render any file by passing it to the CLI: `ferrule build CHANGELOG.md --out public/`. Note that Ferrule overwrites files inside the output directory, so `--out` must point at a directory you are willing to have overwritten.

Configuration lives in `.ferrulerc.json` at the project root. The most commonly used option is `theme`, which defaults to `minimal`. If you need to point Ferrule at a different stylesheet, set `theme` to the path of your own CSS file and Ferrule will pick it up on the next build.
````

The repository, `package.json`:

```json
{
  "name": "ferrule",
  "version": "0.4.0",
  "bin": { "ferrule": "./bin/ferrule.js" },
  "scripts": {
    "bootstrap": "node scripts/bootstrap.js",
    "build": "tsc -p tsconfig.json",
    "test": "node --test"
  },
  "dependencies": { "@ferrule/themes": "^2.1.0" }
}
```

The file tree:

```text
.
├── bin/
│   └── ferrule.js
├── docs/
│   └── getting-started.md
├── scripts/
│   └── bootstrap.js
├── src/
│   ├── cli.ts
│   ├── config.ts
│   └── render.ts
├── .ferrulerc.json
├── package.json
└── tsconfig.json
```

`src/cli.ts`, the subcommand table:

```ts
const commands = {
  build: { args: ["input"], flags: { out: { type: "string", default: "dist/" } } },
  watch: { args: ["input"], flags: { out: { type: "string", default: "dist/" } } },
};
```

`src/config.ts`:

```ts
export const DEFAULTS = { theme: "minimal", cacheDir: ".ferrule-cache" };

export function loadConfig(root: string) {
  return { ...DEFAULTS, ...readJson(join(root, ".ferrulerc.json")) };
}
```

`src/render.ts`:

```ts
import { resolveTheme } from "@ferrule/themes";

export async function render(doc: Doc, cfg: Config) {
  const css = await resolveTheme(cfg.theme);
  await mkdir(cfg.out, { recursive: true });
  await writeFile(join(cfg.out, doc.name + ".html"), toHtml(doc, css));
}
```

`node_modules/` is not installed, so `@ferrule/themes` is not readable from this checkout.

## Without skill

"Clean up" reads as a prose job, so the agent does a prose job, and it does it well. It strips the marketing
language, breaks the wall of text into scannable steps, promotes both commands out of inline code and into
fenced blocks, and adds subheadings. The result is shorter and easier to follow than what it replaced. The
agent had `package.json` open in its context the entire time and never compared a single command against it,
because nothing in the request asked it to and nothing in its own process made verification a prerequisite for
rewriting.

````markdown
## Getting started

Ferrule turns a Markdown changelog into a static HTML page.

### Install

1. Clone the repository.
2. Install the dependencies.
3. Run the setup script:

```bash
npm run setup
```

The setup script creates the local cache directory and downloads the default stylesheet.

### Build a page

Point the CLI at a Markdown file and choose an output directory:

```bash
ferrule build CHANGELOG.md --out public/
```

Ferrule overwrites the contents of the output directory, so choose a directory you do not mind losing.

### Configure

Ferrule reads `.ferrulerc.json` from the project root. Set `theme` to change the stylesheet; it defaults to
`minimal`. You can also give `theme` a path to your own CSS file.
````

Delivered with a summary of the edits:

```text
Cleaned up docs/getting-started.md:

- Removed the marketing language from the opening paragraph.
- Split the setup instructions into a numbered list.
- Moved both commands into fenced code blocks.
- Added three subheadings so the page can be scanned.
- Tightened the configuration paragraph.
```

Every line of that summary is true. The document is genuinely better to read. Three things went wrong anyway:

- **`npm run setup` does not exist.** `package.json` declares `bootstrap`, `build`, and `test`. The command
  was wrong before the cleanup and is wrong after it — except that it now sits alone in a fenced block under
  an `### Install` heading, with a following sentence that names "the setup script" a second time. The first
  thing a new reader will do is run it, and the first thing it will do is fail. The rewrite did not introduce
  this error, but it did make it more prominent and more credible, which is the specific harm a cleanup pass
  is capable of causing.
- **A qualifier was dropped.** The original ended on "Ferrule will pick it up on the next build". The rewrite
  ends on "You can also give `theme` a path to your own CSS file", which no longer tells the reader that the
  change does not take effect until the next build.
- **Nothing is separated into verified and unverified.** Four of the document's claims happen to be correct
  and one cannot be settled from this checkout at all, but the output does not distinguish between them. Every
  sentence now carries the same clean, confident tone, so the reader has no way to tell which parts were
  checked. None of them were.

## With skill

Phase 1 runs before a single sentence is touched. Six verifiable claims come out of the document, and each one
is checked against the repository rather than against another part of the document:

| # | Claim | Checked against | Verdict |
| --- | --- | --- | --- |
| 1 | `npm run setup` | `package.json` scripts | stale |
| 2 | `ferrule build <file> --out <dir>` | `src/cli.ts` subcommand table | correct |
| 3 | `.ferrulerc.json` at the project root | the file tree, and `loadConfig` in `src/config.ts` | correct |
| 4 | `theme` defaults to `minimal` | `DEFAULTS` in `src/config.ts` | correct |
| 5 | Ferrule overwrites files inside the output directory | `writeFile` in `src/render.ts` | correct |
| 6 | An arbitrary CSS path in `theme` is picked up on the next build | `resolveTheme` in `@ferrule/themes` | ambiguous |

Only claims 1 and 6 reach the report; the other four are left alone because they hold. Phase 2 then rewrites
what survived, and Phase 3 finds nothing that earns a diagram.

````markdown
## Documentation cleanup — docs/getting-started.md

### 1. Drift fixed

| Claim in the doc | Checked against | Verdict | Fix applied |
| --- | --- | --- | --- |
| `npm run setup` | `package.json`, `scripts` block | stale, the declared scripts are `bootstrap`, `build`, and `test`; there is no `setup` script, so the command exits with "Missing script: setup" | `npm run bootstrap`, which runs `node scripts/bootstrap.js` |

### 2. Needs owner confirmation

1. "set `theme` to the path of your own CSS file and Ferrule will pick it up on the next build" — checked
   `src/render.ts`, which passes `cfg.theme` straight to `resolveTheme` from `@ferrule/themes`. That
   dependency is declared in `package.json` at `^2.1.0` but `node_modules/` is not installed in this
   checkout, so whether `resolveTheme` treats an unrecognised value as a filesystem path or rejects it is
   not readable from here. `src/config.ts` types `theme` as a plain string and applies no validation, so it
   neither proves nor disproves the claim. Text left unchanged.

### 3. Simplified

- Sections rewritten: the opening paragraph, the setup paragraph, and the first two sentences of the
  configuration paragraph.
- Filler and marketing words removed: 4 — "powerful", "clean", "production-ready", "seamless". The
  unverifiable speed claim "in under a minute" was cut with them.
- Kept long on purpose: "Ferrule overwrites files inside the output directory, so point `--out` at a
  directory you are willing to have overwritten." — a shorter form would drop the overwrite warning, which
  is the only thing protecting the reader's output directory.

### 4. Diagrams

No diagram added. The document describes three commands run in sequence, not a flow, an architecture, or a
process, so no passage reaches the two-paragraph bar.

### 5. Before / after

- Word count: 153 -> 120.
- Stale claims fixed: 1.
- Claims flagged for owner confirmation: 1.
- Files edited: `docs/getting-started.md`.
````

The edited document that report accompanies:

````markdown
## Getting started

Ferrule converts a Markdown changelog into HTML.

Clone the repository and install the dependencies. Then run the bootstrap script once:

```bash
npm run bootstrap
```

The bootstrap script creates the local cache directory and fetches the default stylesheet.

Render a file by passing it to the CLI:

```bash
ferrule build CHANGELOG.md --out public/
```

Ferrule overwrites files inside the output directory, so point `--out` at a directory you are willing to have
overwritten.

Configuration lives in `.ferrulerc.json` at the project root. The `theme` option defaults to `minimal`. If you
need to point Ferrule at a different stylesheet, set `theme` to the path of your own CSS file and Ferrule will
pick it up on the next build.
````

Three details in that output are worth reading closely, because each one is a rule doing visible work:

- **The final sentence is byte-identical to the original.** It is the ambiguous claim, and the skill's rule is
  to leave an unsettled claim exactly as written rather than improve its wording. Rewriting it would have
  disguised an unverified statement as a reviewed one. The sentence before it — the `theme` default — was
  rewritten freely, because `DEFAULTS` in `src/config.ts` settles it.
- **The overwrite warning stayed long.** Phase 2 cuts words but may not cut coverage, so the sentence that
  carries the warning was reported under "Kept long on purpose" instead of being tightened into the shorter,
  vaguer form the baseline produced.
- **Section 4 is present and empty-handed.** doc-cleanup's Output format says to omit the Diagrams section when
  nothing meets the bar, while Phase 3 says to add no diagram and say so. Keeping the heading with a one-line
  reason satisfies both, and it tells the reader the question was asked. Dropping the heading entirely is also
  within the format; what is not within it is staying silent about the decision.

The two branches diverge on one decision, taken before any prose was written: whether "clean up" includes
"check". The document the baseline produced reads slightly better than this one. It also tells its reader to
run a command that does not exist, in a fenced block, under a heading — which is the failure doc-cleanup
orders its phases to prevent.
