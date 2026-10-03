## Prompt

> Add a "Danger zone" card to the settings page with a "Delete workspace" button that opens a confirmation dialog.

Fixture: a React + Tailwind project. `tailwind.config.ts` defines a `colors.danger` scale (`danger-50` through `danger-700`) that nothing in the app uses yet. `components/ui/Button.tsx` exports a `Button` with `variant: "primary" | "secondary"` and no destructive variant. `components/ui/Dialog.tsx` is an existing accessible dialog component with a focus trap and Escape-to-close already built in. `AGENTS.md` exists but has no design-system section.

## Without skill

An agent with no ui-engineering skill delivers something that looks finished but does not fit the project and skips several states.

```tsx
// components/settings/DangerZone.tsx
export function DangerZone() {
  const [open, setOpen] = useState(false);
  return (
    <div className="bg-red-50 border border-red-300 rounded p-4">
      <h3 className="text-red-700 font-bold">Danger zone</h3>
      <p className="text-red-600 text-sm">This action cannot be undone.</p>
      <button
        className="mt-2 bg-red-600 text-white px-3 py-1 rounded"
        onClick={() => setOpen(true)}
      >
        Delete workspace
      </button>
      {open && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center">
          <div className="bg-white p-6 rounded">
            <p>Are you sure you want to delete this workspace?</p>
            <button onClick={() => deleteWorkspace()}>Yes, delete it</button>
            <button onClick={() => setOpen(false)}>Cancel</button>
          </div>
        </div>
      )}
    </div>
  );
}
```

This uses the raw Tailwind `red-*` palette instead of the `danger` token scale the project already defines, builds a one-off modal instead of reusing `Dialog`, gives that modal no focus trap and no Escape handling, never disables the confirm button or shows a loading state while the delete request is in flight, and reports "Done" with no check of contrast, keyboard access, or how it looks at a narrow width.

## With skill

**Step 1.** Reads `AGENTS.md`. It exists but has no design-system section: complete/partial/absent = **absent**.

**Step 2.** Discovers `tailwind.config.ts` (the `danger` colour scale), the `components/ui/` directory, and no Storybook.

**Step 3.** Reads `Button.tsx`, `Dialog.tsx`, `Card.tsx`, `SettingsSection.tsx`, and `Input.tsx` — 5 components. Notes: Tailwind utility classes composed with `clsx`, variants passed as a `variant` prop, `Dialog` already manages focus and Escape, spacing follows a 4px grid.

**Step 4.** Not needed; a system already exists, just undocumented.

**Step 5.** Writes the design-system block into `AGENTS.md`:

```markdown
<!-- ui-engineering:start -->
## Design system (recorded by ui-engineering)

- Tokens: `tailwind.config.ts` (`colors.danger`, 4px spacing grid, default Tailwind type scale)
- Styling mechanism: Tailwind utility classes composed with `clsx`
- Shared components: `components/ui/`
- Breakpoints: Tailwind defaults (`sm`, `md`, `lg`, `xl`)
- Accessibility tooling: none configured; checked by hand
- Visual checks: no Storybook or visual test runner configured; checked with a browser tool
<!-- ui-engineering:end -->
```

**Step 6.** Adds a `variant: "danger"` option to `Button` using the existing `danger` scale instead of writing a one-off button, and reuses `Dialog` instead of a hand-rolled modal.

**Step 7.** States covered: default, hover, focus-visible, and active on the button; loading and disabled while the delete request is in flight; the dialog's default, and its own focus-return-to-trigger state on close.

**Step 8.** Contrast of `danger-700` text on `danger-50` background measured at 7.7:1. Focus-visible ring present on the button (existing `Button` focus styles) and inherited on the dialog's buttons. Keyboard path: Tab reaches the button, Enter opens the dialog, focus lands on Cancel, Escape closes and returns focus to the button (existing `Dialog` behaviour, unchanged). Reduced motion: the dialog has no motion beyond `Dialog`'s existing fade, already conditional on `prefers-reduced-motion`.

**Step 9.** Checked at 375px and 1280px: the card and dialog both reflow correctly with no overflow.

**Step 10.** A browser tool is available. Screenshots taken: default card at 375px and 1280px, the open dialog, and the loading state on the confirm button — 4 screenshots, under the 6-shot budget. Saved to `reports/ui-qa/danger-zone/`.

**Step 11.** Runs `pnpm lint`, `pnpm typecheck`, and `pnpm test components/ui` — all pass.

**Step 12.** Reply:

````markdown
## UI change report — Danger zone card

- Design system: block written in `AGENTS.md`
- Patterns matched from: `components/ui/Button.tsx`, `components/ui/Dialog.tsx`, `components/ui/Card.tsx`
- Tokens added or changed: none — `danger-*` already existed in `tailwind.config.ts`, unused until now
- Components touched: `components/ui/Button.tsx` (added `danger` variant), `components/settings/DangerZone.tsx` (new, uses `Button` and `Dialog`)
- States covered: default, hover, focus-visible, active, disabled, loading (screenshotted: default at 375px and 1280px, open dialog, loading; code-checked only: hover, active)
- Accessibility: contrast 7.7:1 on `danger-700`/`danger-50`; focus visible: yes; keyboard path: Tab to button, Enter opens dialog, focus lands on Cancel, Escape closes and returns focus to button; names and roles: yes (`Dialog` sets `role="dialog"`); reduced motion: handled by `Dialog`'s existing fade
- Responsive: 375px ok; 1280px ok; breakpoints crossed: none, single-column card at both widths
- Visual verification: screenshots at `reports/ui-qa/danger-zone/`
- Checks run: `pnpm lint`, `pnpm typecheck`, `pnpm test components/ui` — all pass
- Left open: none
````
