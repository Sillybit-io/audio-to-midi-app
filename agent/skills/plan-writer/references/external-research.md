# External research

Read this file after the codebase investigation and, when the request came from a ticket, after the vagueness test. Skip it only when the run already stopped as `trivial` or as a blocked ticket.

## What to research

Search the public web for this feature, not for generic best practice. The queries come from what the user asked: the official docs, how other people implemented it, what they treat as important, and the pros and cons.

Research ends when every external contract a todo relies on is verified, not when a count runs out. A contract is an API signature, a configuration field, a CLI flag, a file format, a lifecycle or ordering guarantee, or a version constraint. For each one:

1. Find the version the project uses, from its lockfile, manifest, installed binary, or pinned image.
2. Open documentation for that version, or a rolling page whose date you record.
3. Record the source as an `external` citation in the Evidence index, with the quoted text the plan relies on.

General guidance, analogies, and examples for a different version do not verify a contract. When the documentation cannot be reached, record the access failure and any substitute evidence, such as the installed package's source. Keep the contract on the frontier until something establishes it.

## Write `## Research`

- Sources. Each is an `http` or `https` URL you opened, with its version.
- How others did it.
- What matters.
- Pros and cons.
- What this plan will follow.
- Queries not run, with the reason, or `none`.

When the public web has nothing useful, write the line `No useful public source found.` and name the queries you ran. That line satisfies the format. It does not waive a contract a todo needs.

A research finding does not replace a code citation. Every IS cell still cites `path:line`. Put a research finding in the GAP cell or in this section.

## After the owner's answers

Research again when an answer introduces a product choice, a technology, a constraint, or a non-goal that `## Research` does not already cover. Confirming a recorded default is not a new point. Append the result under `### After answers` and update the IS/GAP ledger, the risks, and the Evidence index.

Research repeats whenever new evidence demands it. The one stop: the new point creates an irreversible, destructive, costly, or cross-cutting fork that nobody has answered. Write that one question, with its reason and its default, into `## Questions`, and stop at the draft gate.

## Fix-only

When `plan-review` names a missing section or an unverified contract, research that contract as above. Research the codebase only along the blocker's affected paths.
