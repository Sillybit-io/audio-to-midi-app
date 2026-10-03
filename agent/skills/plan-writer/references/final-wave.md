# Final verification wave

Read this file when you add the final verification wave. It comes after every implementation todo. plan-writer writes these todos. It does not run them.

## The four gates

Title them `F1`, `F2`, `F3`, and `F4`, in that order. They are one parallel wave: none depends on another. The execution-strategy line names them as `F1, F2, F3, F4`, plus any extra. Each gate starts with `- [ ] Open`. The builder changes that line to `- [x] Done` in the project copy when the gate is finished. The test-before-next rule on todos under `## Todos` does not apply to these gates. F2 and F3 still do their own work.

- **F1 Plan compliance.** Every Must Have is present. Every Must NOT Have is absent. Cite the evidence.
- **F2 Code quality.** Run the test, lint, and build commands the project actually defines. Name any of the three the project does not have. Compare the results with the baseline checks recorded in the Evidence index, so a failure that predates the change is named instead of hidden or blamed on the build. Then a language-appropriate slop pass: empty catches, debug logs, commented-out code, unused imports, and the local equivalent of a type escape.
- **F3 Scenario QA.** Execute every todo's QA scenario, including the edge cases. Do not name a browser tool or a screenshot path. Those belong only to the UI QA todo.
- **F4 Scope fidelity.** An independent result review in a fresh session compares every changed artifact with the plan, and every requirement with the change, from the build baseline: `plan-result-review` when it is installed. No extra files. No todo edits a file another todo owns. Each difference is explained with its location and reason.

Extra feature-specific checks are allowed. Title them `F5` onward and place them after `F4` and before the UI QA todo. Four gates is the minimum, not the maximum.

## UI QA

Set `ui: yes` when the project has a web framework in its manifest, an `index.html`, a templates or views directory, or a mobile app target, and also when this plan itself adds a web or mobile surface. Otherwise `ui: no`.

When `ui: yes`, the last todo in the plan is the automated UI QA task. It names the tool, the route or screen, the viewport widths, the steps, the expected result at each step, and the screenshot path `reports/ui-qa/<slug>/`. It is not one of F1–F4, and it is not folded into F3. The test-before-next rule does not apply to it.

When `ui: no`, do not add that todo. Say why in one line under the wave.
