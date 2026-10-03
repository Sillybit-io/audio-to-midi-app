# Evidence gate

Read this file when building the coverage ledger and before deciding a verdict. The gate checks whether the plan is executable on current evidence. It does not require implementing the plan first. [references/validator-contract.md](validator-contract.md)'s Plan grammar and Gate record sections define the plan's grammar, the required-target list, and the evidence-kind/id scheme; this file explains how to use them, not a substitute for them.

## Build the ledger

Give each obligation a stable `O<n>` id. Cover every required target validator-contract.md names: each `MH<n>` and `MN<n>`; every todo's `.start`, `.acceptance`, and `.qa`; every `dep:T<a>:T<b>`; every `F<n>.acceptance`; every Evidence index flow's `flow:<id>`; every external citation's `contract:<id>`; and `check:A` through `check:J`. Group targets into one obligation only when the same evidence supports all of them. Map each row to its owning todos and planned QA. Also account for Checks A–J.

Record three things separately:

- **Source trace:** file and lines, the behavior inspected, and the conclusion that behavior supports. For proposed behavior, connect the existing entry points to the plan's ordered changes and expected outcome. A citation alone is not a trace.
- **Executed probe:** command or tool, fixture inputs, actual result, and what was stubbed or omitted. Keep the output in the review or name an accessible artifact. A copied reimplementation demonstrates only the model it encodes; prefer invoking the real function in an isolated fixture.
- **Planned QA:** the test the builder will run later. Check that it is feasible and can detect the claimed failure. Do not mark it executed or require future implementation tests to pass during plan review.

Versioned documentation can verify an external contract. Plan inspection can verify a decision, dependency, or writer-contract requirement. Neither proves runtime behavior by itself. General guidance, analogies, and unversioned examples cannot establish an exact callback signature or lifecycle guarantee.

For each behavioral guarantee, identify the existing behavior and the specific planned change that makes the guarantee true. A future assertion such as "existing backups stay unchanged" is not that change. If the source violates the guarantee and the plan leaves the controlling behavior unchanged, mark the obligation contradicted. A generic "fix checks until they pass" instruction cannot supply a missing implementation decision.

Assign each required row one status:

| Status | Meaning |
| --- | --- |
| verified | The cited evidence supports this review obligation. For proposed work, the existing contracts and explicit planned changes support executability; the implementation is still future work. |
| contradicted | Evidence demonstrates an execution failure or a conflict with a required outcome. Record a blocker and a fix. |
| unverified | Required evidence has not been obtained. Record why and the smallest next check. |

Mark optional observations `Required? no` and keep them out of approval totals. A required obligation cannot become optional merely because checking it is difficult. Report verified/required counts derived from ledger IDs, with separate critical-flow counts derived from unique flow IDs and their statuses. Do not substitute todo counts for coverage counts or count a subcase twice.

## Select critical flows

A flow is critical when its failure prevents a Must Have, loses or misattributes data, strands a user after a state change, or breaks a necessary integration. Trace every such flow across todo boundaries. Small file-only changes can have zero critical runtime flows; record why. Do not manufacture migration, network, or UI checks for a plan that has none.

For each applicable flow, record the entry point, starting state, preconditions, ordered reads and writes, external effects, result, and recovery. Try a concrete counterexample before calling the flow verified. Record the counterexample and the evidence that confirms or refutes it. A source trace is sufficient when it resolves the question. If ordering or state remains uncertain, use a disposable probe; if that cannot resolve it, keep the flow unverified.

| Flow | Questions the trace must answer |
| --- | --- |
| Startup/install/upgrade | Which installation is detected before paths change? Do version detection, locking, backup, and migration use the same selected source? Does creating a lock directory invalidate a later destination-absence guard? |
| Migration | Cover legacy-only, new-only, both-present, and interrupted states when supported. Which state is authoritative? At what point does the active path change? Is existing destination data preserved or handled explicitly? |
| Rollback/recovery | What is the transaction boundary? Which data, executables, generated files, hooks, environment settings, shell helpers, and external configuration fragments changed? After restoring or removing owned changes, can the original entry points actually run, and are unrelated settings preserved? |
| Events/background work | How are session and workspace attributed? Who owns queued work, persistence, refresh, and termination? Do concurrent sessions, duplicate delivery, compaction, or interrupted workers change the promised outcome? |
| Retrieval/aggregation | Does the advertised scope reach every intended store through the real API? Do limits bound results or silently skip input stores? Does an oldest or least-prioritized unique match survive? |
| Tool/protocol integration | Are registration, handshake, payload, version, working directory, event scope, lifecycle, and teardown consistent with the exact target contract? A plausible event name is not evidence. |
| Dependency/verification order | Can each todo's own Acceptance and QA pass immediately after that todo, before downstream todos exist? Do final gates invoke the real user-facing path? |

The table is a starting point, not a requirement to invent absent features. Trace any other critical flow the actual plan needs. Choose counterexamples based on its guarantees rather than copying this table into every review.

## Check failure paths operationally

Migration and rollback checks must go beyond directory existence or bank-data preservation when the plan promises a working installation. Follow each changed pointer to its consumer. A hook that returns a harmless-looking empty response after its engine disappeared is still broken.

For stateful changes, trace failure before and after each distinct irreversible or externally visible boundary. Where configuration is rewritten, include a failure after that rewrite. Record the planned restore/remove behavior for installer-owned entries and how unrelated user settings survive. If a relevant recovery decision is absent, report the missing decision as a blocker; if a decision exists but its premise cannot be checked, record the evidence gap.

## Re-review without anchoring

Fix verification and approval verification answer different questions. First establish that each listed defect is resolved. Then revisit all critical flows and requirement mappings before approval, including unchanged sections.

Reuse an observation only if its source content and the plan obligations it supports still match. A repository revision plus the word `dirty` is insufficient: dirty file contents can change without either value changing. Compare evidence-file digests, inspect changed callers or dependencies, and record the scope of reuse. Re-read or probe when dependencies changed or the earlier review has no supporting evidence.

Newly demonstrated failures remain reportable even when an earlier round passed that area. Preserve the old verdict and explicitly state why the new one supersedes it. Do not invent findings to justify a confidence challenge, and do not treat a user's confidence as evidence.

## Evidence limits and verdicts

- A timeout, unavailable repository, or unreadable contract does not prove a defect. Finish every available independent check first; only a genuine access failure, not a self-imposed limit, produces INCOMPLETE if required evidence remains unavailable and no demonstrated blocker exists.
- An inaccessible optional reference is a note. An inaccessible necessary contract is unverified unless another inspected source establishes it.
- A missing required decision, broken dependency, or demonstrated contradiction produces REJECT. If gaps also remain, include them with the rejection.
- Zero blockers with required unverified rows is INCOMPLETE. Only zero blockers plus complete required coverage can produce OKAY.
- Owner waivers and acceptance of risk remain separate from technical verification. If the owner actually changes the requirement, review the revised scope and record that change; do not relabel the original failure as a pass.
- Structural validation can check report shape and arithmetic. It cannot prove that the reviewer read the cited code or that a flow works. Never use a passing validator as the sole approval evidence.

Before saving OKAY, reconcile the ledger, critical-flow records, Checks A–J, blocker count, and frontmatter. After saving, re-read the review and confirm that its verdict and identity still match the evidence. If writing is unavailable, return the review with the limitation and do not claim that the plan file was updated.

## Checkpoint format for a retryable INCOMPLETE

An INCOMPLETE round that leaves the door open to another round records, per unresolved obligation: which checks this round actually completed (with their evidence ids), which searches or sources remain unopened and why, and what new evidence or newly runnable check would resolve it. A round that repeats this list unchanged from the previous round, with no new evidence and no newly runnable check, is not progress and does not justify spending another round; say so and stop instead of retrying identically.
