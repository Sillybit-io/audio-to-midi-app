# Writer contract

Read this file when running checks F through J. It restates what `plan-writer` is required to leave in the plan file. A miss is a blocker, same rank as checks A through E.

Describe every execution blocker in detail; there is no reporting cap, and a display limit never makes a failed requirement pass. For equally consequential writer-contract misses, prioritize T0, test-before-next, continuation, final gates, unresolved decisions, research, and diagrams.

## Check F — Research

`## Research` is present and either:

- names sources, how others did it, what matters, pros and cons, and what the plan will follow, or
- contains the line `No useful public source found.`

Each source is an `http` or `https` URL. Verify the claim against the fetched content and the target version when the plan relies on a version-specific contract. An inaccessible source is not proof of a defect: record the access failure and any substitute evidence. If a necessary contract remains unverified, the approval gate produces INCOMPLETE unless a demonstrated blocker already requires REJECT. Optional unreadable sources belong in Notes. A fetched contradiction is evidence for a blocker. A "no useful public source" line satisfies the research-section format but does not waive a necessary external-contract check.

## Check G — Questions

`## Questions` has `### Product` before `### Technical`, and neither group is empty. Every item has an answer or a recorded default.

Product is who it is for, what job they are doing, what success looks like, what is out of scope, or which user-facing tradeoff they want. Technical is an approach, a library, data, compatibility, failure behavior, or where the change lives. A question that names a library is technical.

Technical-before-product, a missing group, or an item with neither an answer nor a default is a blocker. Do not judge whether a question was wise.

## Check H — Diagram

`## Design` is present.

A diagram is required when the user asked for a diagram, a flow, or a design, or when the request is about how a process, a user journey, or a system interaction works. A list of file edits is not a flow. The order of the implementation todos does not force a diagram.

When a diagram is required, the section contains a fenced `mermaid` block whose first code line starts with `flowchart`, `sequenceDiagram`, or `stateDiagram`. `flowchart TD` counts. When it is not required, the section contains `Diagram: omitted — <reason>`.

A missing section, a required diagram that is absent, or a required diagram that is not one of those three types is a blocker. An extra diagram on a file-edit plan is not. Do not reject a diagram for node-id style.

## Check I — Final wave

The wave contains todos titled `F1`, `F2`, `F3`, and `F4`, in that order:

- F1 plan compliance: every Must Have is present, every Must NOT Have is absent.
- F2 code quality: the test, lint, and build commands the project defines, plus a slop pass.
- F3 scenario QA: every todo's QA scenario. F3 does not name a browser tool or a screenshot path.
- F4 scope fidelity: the diff matches the spec.

Extra todos titled `F5` onward may sit after `F4`. Fewer than four gates, a missing gate, or a gate out of order is a blocker.

When `ui: yes` — including a plan that adds a web or mobile surface — the automated UI QA todo is present and last. It names the tool, the route or screen, the viewport widths, the steps, the expected result, and a screenshot path under `reports/ui-qa/`. When `ui: no`, that todo is absent and the wave says why in one line.

## Check J — Todo boxes and T0

Four misses, each a blocker:

- Every todo under `## Todos` and every gate under `## Final verification wave` starts with `- [ ] Open` on a freshly planned file. The `## Todos` section tells the builder to change that line to `- [x] Done` in the project copy before the next todo starts. A missing box, or a missing instruction, is a blocker. Do not reject a box that is already `- [x]` on a re-review after the build has started. One intro paragraph that says to pass the checks, mark Done, and only then start the next todo satisfies this miss and the test miss together.
- `## Todos` tells the builder to run that todo's Acceptance and QA scenario, pass them, commit when the todo says `Commit: yes`, mark `- [x] Done`, and only then start the next todo. A missing instruction is a blocker. Look for it in the section intro, not on each todo body. A failure path marked n/a is not run; the intro does not have to say that for this check to pass. The final wave must not inherit that rule. A blocker is an intro that says the test-before-next rule applies to F1–F4 or the UI QA todo, including "the same rule applies here" once that rule includes testing. F2 running the project's test, lint, and build commands, and F3 executing QA scenarios, are the gates themselves. Do not flag those.
- `## Execution strategy` tells the builder to finish T0, then each wave in list order, then the final wave, without stopping to ask for a continue. Todos inside one wave stay as independent as that line says. F1–F4 stay one parallel wave. If a todo's checks fail, the builder fixes that todo and runs the checks again until they pass, then continues. A missing sentence is a blocker. So is an instruction to stop after a wave and wait, or to stop and wait when a check fails. A failed check that is fixed and then continued is not this miss. Gates that stay parallel are not this miss.
- `T0` is the first todo. Its job is to copy this plan into the project's `docs/plans/` when the file is not already there, and then to do the rest of the build in that copy. If the file is already there, it stays. Checking its own box is the one edit T0 may make besides that copy. A missing T0, a T0 that is not first, a T0 that copies unconditionally, a T0 that leaves the build in the outside file, or a T0 that forbids the checkbox edit, is a blocker. T0 does not need to close a gap. Its reference may be `this file`.
