# Design diagram

Read this file after the second research pass, when the plan is being filled in. Put the result in `## Design`, after Scope and before Verification strategy.

## When a diagram is required

Add a fenced `mermaid` block when either of these is true:

- The user asked for a diagram, a flow, or a design.
- The request is about how a process, a user journey, or a system interaction works.

A list of file edits is not a flow. The order of the implementation todos does not force a diagram.

Use one of these, and no other type:

- `flowchart` for control flow. `flowchart TD` is fine.
- `sequenceDiagram` for who talks to whom.
- `stateDiagram` for state. `stateDiagram-v2` is fine.

## When a diagram is omitted

`## Design` is one line:

```text
Diagram: omitted — <reason>
```

The reason names why the request is not a flow or a design. An extra diagram on a file-edit plan is allowed. A missing `## Design` section is not.

## Diagrams and flow traces

A diagram shows the design at a glance. It does not replace the traces under `### Critical flows` and in the Evidence index, which name each entry point, ordered effect, recovery path, and counterexample. A file-edit plan can omit the diagram and still have a critical flow; a cross-component process needs both.

## Syntax

These rules are for the writer so the diagram renders. Review does not grade them.

- No spaces in node ids. Use camelCase or underscores.
- Put quotes around an edge label that contains parentheses, brackets, or other special characters.
- Put double quotes around a node label that contains parentheses, commas, or colons.
- Do not set colors, styles, or `classDef`.
- Do not use `click`.
