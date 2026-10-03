---
name: ui-engineering
description: Builds and changes UI code design-system first. Finds the design-system section in the project instructions file, reads existing components before writing one, extends tokens instead of hardcoding values, covers every interaction state, checks WCAG 2.2 contrast, focus, and keyboard access, and renders or screenshots the result before calling it done. Use when you build this component, implement this screen, style this page, make this responsive, or match the design system.
license: CC-BY-ND-4.0
metadata:
  version: "0.1.0"
  category: engineering
  suggested-model: anthropic/claude-opus-5-5
  suggested-effort: max
---

# ui-engineering

## Purpose

A change is done when it matches the design system the project already has, works in every state a user can reach, is usable without a mouse, and has actually been looked at. ui-engineering exists to stop the plausible-looking component: correct in a code review, wrong on screen, with its own colours and its own spacing that nothing else in the project uses. It reads the project's own instructions file for a design system before it looks at any code, keeps that file current when the information was missing, then builds inside the system it found — extending it rather than adding a one-off override — and ends with visual evidence, not a claim. The `suggested-model` hint above is advisory; this skill runs on any model.

## When to use / when NOT to use

Use ui-engineering when you:

- Add or change a component, screen, page, or layout in a web or mobile app.
- Make an existing screen responsive or fix a layout or interaction defect.
- Need a design system's tokens discovered, or a minimal one created, before real UI work can start.

Do NOT use ui-engineering when you:

- Are working on backend or API code with no visual surface.
- Want a design critique with no code change — say what you would change, but this skill writes code.
- Want a chart or data visualization. Those have their own conventions this skill does not cover.
- Have no way to render the code and only want a draft. Say so up front; the report will carry `NOT VERIFIED` for every state.

## Workflow

1. Read the project's instructions files for a design-system section: `AGENTS.md` and `CLAUDE.md` at the repository root and in the touched directories, plus `CONVENTIONS.md` and `.cursor/rules/*` when present. Look for: the tokens or theme path, the styling mechanism, the shared components directory, the breakpoints, the type and spacing scale, the accessibility tooling, and how to run a visual check. Verify every path it names still exists. Record the result as complete, partial, or absent.
2. Discover only what step 1 did not already settle, inside a budget of 15 files: a tokens or theme file, a Tailwind or equivalent config, `:root` custom properties, the shared components directory, a Storybook or component catalogue, and any lint rule that encodes a convention.
3. Read the 5 to 10 components nearest to the one you are about to touch — never more than 10. Note the styling mechanism, the variant conventions, how state is expressed, and the breakpoints in use. These are the conventions to match; a popular style guide from outside the project is not.
4. When no design system exists at all, create the minimum before writing the component: a colour set (background, surface, text, muted text, primary, danger, border, focus ring), a spacing scale, a type scale, corner radii, and motion durations, in the project's own styling mechanism, in one file. Say in the report that you created it.
5. When step 1 found the design-system section partial or absent, write what you found into the project's own instructions file — `AGENTS.md` if it exists, else `CLAUDE.md` if that exists, else create `AGENTS.md` — inside a marked block, `<!-- ui-engineering:start -->` through `<!-- ui-engineering:end -->`. A re-run replaces only the text between those markers and never touches anything outside them. The block holds the seven items from step 1, one line each with its path. Skip this step entirely when step 1 was already complete.
6. Build with tokens only. When a value you need has no token, add the token to the system first, then use it. Extend a shared component with a new variant before you write a new component that duplicates it. Never override a shared component's styling from the call site.
7. Cover every state the change can reach: default, hover, focus-visible, active, disabled, loading, empty, error, overflow or long content, and right-to-left layout when the project supports it.
8. Check accessibility against WCAG 2.2: text contrast of at least 4.5:1 (success criterion 1.4.3), a visible focus indicator on every operable element (2.4.7), full keyboard reachability and operation (2.1.1), a name and role on every control, and `prefers-reduced-motion` respected for any animation you add.
9. Check the responsive layout at roughly 375px and roughly 1280px, plus any project breakpoint the component crosses, watching for horizontal overflow, clipped text, and touch targets that are too small.
10. Verify visually, inside a budget. With a browser automation tool available: screenshot the default state at both widths, plus every state the change introduced or touched, up to 6 screenshots in this pass, and one more pass after any fix. Save them to `reports/ui-qa/<component>/`; do not stage or commit them, and note in the report if the project's `reports/` is not already gitignored. States beyond the 6-screenshot budget are checked by reading the code instead and listed as "not screenshotted." Without a browser tool, run the project's own component or visual tests instead and write `NOT VERIFIED: <reason>` for whatever those tests do not cover.
11. Run the project's existing lint, type check, and test commands against the files you touched.
12. Reply with the change report in Output format, and nothing else.
13. Walk the QA checklist.

### Handling feedback

A hedged remark about a design choice — "I'm not sure this red is right" — never changes the code by itself. Name the token in question, say what the system already uses for the same purpose elsewhere (for example, "destructive actions use the `danger` token"), give a recommendation, and ask. A plain instruction — "use the primary colour instead" — is applied directly, with a one-line note if it departs from how the rest of the project uses that colour.

## Output format

````markdown
## UI change report — <component or screen>

- Design system: instructions file complete | block written or updated in `<file>` | created minimal system at `<path>`
- Patterns matched from: `<path>`, `<path>`, `<path>`
- Tokens added or changed: `<name>: <value>` | none
- Components touched: `<path>`, `<path>`
- States covered: default, hover, focus-visible, active, disabled, loading, empty, error, overflow (screenshotted: <list>; code-checked only: <list>)
- Accessibility: contrast `<ratio>` on `<foreground>`/`<background>`; focus visible: yes; keyboard path: `<tab order or shortcut>`; names and roles: yes; reduced motion: handled | not applicable
- Responsive: 375px ok | <issue and fix>; 1280px ok; breakpoints crossed: `<list>`
- Visual verification: screenshots at `<path>` | NOT VERIFIED: <reason>
- Checks run: `<lint>`, `<typecheck>`, `<tests>` — all pass | <failure and cause>
- Left open: none | <what could not be done, and why>
````

## Guardrails

MUST:

- MUST read the project's instructions files for a design-system section before discovering anything else.
- MUST write the marked block into the instructions file when that information was missing or incomplete.
- MUST use a token wherever one already exists for the value you need.
- MUST add a missing value to the design system before using it, never inline it once.
- MUST extend a shared component with a variant before writing a new one that duplicates it.
- MUST cover every state listed in step 7 that the change can reach.
- MUST meet the WCAG 2.2 criteria named in step 8.
- MUST check both the narrow and the desktop width.
- MUST render or screenshot the change when a browser tool is available, and write `NOT VERIFIED` with a reason when one is not.
- MUST run the project's own lint, type check, and test commands on the touched files.
- MUST answer a hedged remark with the token, the system's existing use, and a question before changing the code.

NEVER:

- NEVER hardcode a colour, spacing value, radius, font size, or duration that a token already provides.
- NEVER edit the project's instructions file outside the marked `ui-engineering` block.
- NEVER override a shared component's styling from the call site instead of extending it.
- NEVER add a new dependency — an icon set, a UI library, an animation library — without naming it in the report, and asking first in an interactive session.
- NEVER add a gradient, animation, or visual effect the design system does not already use.
- NEVER remove a focus outline.
- NEVER change an existing token's value without saying so; every consumer of that token changes with it.
- NEVER call a change done without either visual evidence or a `NOT VERIFIED` line naming the reason.
- NEVER exceed the screenshot budget in one pass.
- NEVER stage or commit the screenshots in `reports/ui-qa/`. They are local working files, like this repository's own `reports/` convention.

## QA checklist

- [ ] The instructions file was read for a design-system section before any file discovery happened.
- [ ] The marked block was written or updated when that information was missing, and nothing outside the block changed.
- [ ] 5 to 10 nearest components were read, and at least one is named in the report.
- [ ] No hardcoded colour, spacing, radius, font size, or duration exists where a token was available.
- [ ] Every state from step 7 that the change can reach is covered, and the report says which were screenshotted versus code-checked.
- [ ] The contrast ratio is measured and stated; a visible focus indicator exists on every operable element; the keyboard path is stated; reduced motion is handled or marked not applicable.
- [ ] Both the narrow and desktop widths were checked.
- [ ] Screenshots exist under `reports/ui-qa/<component>/` and were not staged or committed, or `NOT VERIFIED` names the reason.
- [ ] The project's lint, type check, and test commands were run on the touched files.
- [ ] Any new dependency is named in "Left open" and, in an interactive session, was asked about first.
- [ ] The reply is the change report only.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
