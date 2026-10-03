---
name: tech-writing
description: Writes a new technical document from repository facts. Covers a README, a how-to, a reference page, an explanation, or a decision record. Names the reader and their next action first, picks the type, outlines before prose, writes in simple English, strips filler, and verifies every command and link before handing it back. Use when you write a README for this, write an ADR for this decision, document this decision, write a how-to, or draft a design note. Creates new documents only.
license: CC-BY-ND-4.0
metadata:
  version: "0.1.0"
  category: docs
  suggested-model: anthropic/claude-fable-5-1
  suggested-effort: medium
---

# tech-writing

## Purpose

A document exists for a reader to act on, and for nothing longer than that. tech-writing answers two questions before it writes a single heading — who reads this, and what do they do next — then builds an outline from those answers, gathers facts from the repository rather than memory, and writes in plain, verified sentences. It exists to stop the document that talks about the software instead of to the reader: a features list, a wall of badges, a decision record that states the decision without the reasons anyone would need to revisit it. It creates new documents and decision records only. `doc-cleanup` repairs an existing document that has gone stale; `issue-refiner` writes a brief into a ticket. The `suggested-model` hint above is advisory; this skill runs on any model.

## When to use / when NOT to use

Use tech-writing when you:

- A module, service, or repository has no README yet.
- A decision was made and needs a written record for the next person who wonders why.
- A how-to or runbook is missing for a task people keep re-figuring out.
- An explanation of a design is needed for someone who was not there when it was made.

Do NOT use tech-writing when you:

- The document exists already and is wrong or stale. Use `doc-cleanup`; it verifies before it simplifies.
- The text is a ticket. Use `issue-refiner`.
- The text is an implementation plan. Use `plan-writer`.
- The text is a pull request description. Use `pr-description`.
- The target is `CHANGELOG.md`, a release note, or any file carrying a legal or attribution notice.
- The request is marketing copy or a launch post. Those need a voice this skill removes.
- No reader can be named, and the person asking cannot say who it is.

## Workflow

1. Name the reader and their next action in one line: "`<who>` reads this to `<do what>`." If neither is stated and the repository does not make it obvious, ask that one question in an interactive session, or state the assumption at the top of the reply in a non-interactive one.
2. Pick the document type by what the reader needs: learning something for the first time is a tutorial, doing a task is a how-to or a runbook, looking something up is a reference, understanding why is an explanation or a decision record. Pick the path to match: `README.md` at the module's root; `docs/decisions/NNNN-<slug>.md` for a decision record, numbered one past the highest existing number; `docs/<slug>.md` for everything else; or the project's own existing docs layout when one is already established. When the target path already exists: in an interactive session, say so, recommend `doc-cleanup` for a stale document or a rewrite here for a stub, and ask which; in a non-interactive run, write to `<path>.new.md` instead and say so in the reply.
3. Gather facts from the repository itself, never from memory: verify a command against the project's manifest scripts, a path against the real file tree, a behaviour claim against the code that implements it — the same check-it-against approach `doc-cleanup` uses for its drift phase. Run every command you intend to print. Budget: 15 files read; when you hit it, note under "Not verified" in the handback block whatever you could not check rather than guessing.
4. Outline before you write a word of prose: list the headings, and under each write one line stating the question it answers for the reader. Delete any heading whose line does not serve the stated next action.
5. Write in simple English: one idea per sentence, active voice, the actor named and acting, one term per concept held for the whole document, the circumstance stated before the instruction that depends on it. Teach the reason once, then give the steps, rather than repeating the reason at every step. This follows the same ASD-STE100 Simplified Technical English principles `doc-cleanup` uses; see that skill for the full rule set (asd-ste100.org).
6. Strip every phrase in the table below, then cut any sentence that only announces what a section is about to do, and any sentence that only summarizes what a section just did.

   | Cut | Write instead |
   | --- | --- |
   | delve | look into, or the specific action |
   | leverage | use |
   | utilize | use |
   | in order to | to |
   | robust, seamless, powerful, cutting-edge | the number or the behaviour |
   | it's important to note that / it's worth noting | delete; say the thing directly |
   | simply, just, easily | delete |
   | in today's fast-paced world (or any opener about the world) | delete |
   | comprehensive, holistic | delete |
   | we are excited to | delete |
   | this document will | delete; start with the content |
   | please note | delete |
   | a wide range of | the actual list |
   | at the end of the day | delete |

7. For a decision record, use the five-part shape in Output format: Context, Decision, Consequences (including the costs, not only the benefits), Alternatives considered (each with the reason it lost), and a status history. Keep it to about two pages; a longer record usually means the decision was really several decisions.
8. For a README, use the section order in Output format: exactly one quick-start path from install to a first visible result, no features list, and badges limited to build status and license.
9. Verify a second time: run every command again from a clean shell, open every link, and re-check every path against the current tree.
10. Self-review each paragraph by asking "what does the reader do with this?" — delete the paragraph when the answer is nothing.
11. Write the file at the path from step 2. Reply with the handback block only.
12. Walk the QA checklist.

### Handling feedback

A hedged remark about the document — "I think the Consequences section is too negative" — never changes the text by itself. Say why each listed cost is there, give a recommendation, and ask. A plain instruction — "cut the second alternative" — is applied directly, with a one-line note if the record now reads differently as a result, for example that it lists only one alternative.

## Output format

README skeleton:

````markdown
# <name>

<One sentence: what it is and who it is for.>

## Install

```sh
<one verified command>
```

## Quick start

<The shortest path from install to one visible result. One path only.>

## Usage

<The two or three things the reader does most, each with a verified command and its output.>

## Configuration

| Variable or option | Meaning | Default |
| --- | --- | --- |

## Where to go next

- <link to a reference, a how-to, or a decision record>

## License

<one line>
````

Decision-record skeleton, Nygard's five sections plus alternatives, with MADR-style status values:

````markdown
# <NNNN>. <Decision as a short noun phrase>

- Status: proposed | accepted | deprecated | superseded by <NNNN>
- Date: <YYYY-MM-DD>

## Context

<The forces at play: the problem, the constraints, what happens if nothing is decided. Two to five sentences.>

## Decision

<What was decided, stated in the active voice: "We will ...". One paragraph.>

## Consequences

<What becomes easier, what becomes harder, and what now has to be done. Include the costs, not only the wins.>

## Alternatives considered

- <Option> — <why it lost, one or two sentences>.

## Status history

- <date>: proposed by <handle>
- <date>: accepted
````

How-to / runbook skeleton:

````markdown
# How to <task>

## Before you start

- <precondition, one line>

## Steps

1. <one action> — expect: <result>

## If it fails

| Symptom | Cause | Fix |
| --- | --- | --- |

## Related

- <link>
````

Handback block, sent as the reply and nothing else:

```markdown
Written: `<path>` — <type>, for <reader> to <next action>.
- Facts verified: <n> commands run, <n> paths checked, <n> links opened.
- Not verified: none | <claim and why>
- Words: <n>. Sections: <n>.
```

## Guardrails

MUST:

- MUST name the reader and their next action before writing anything else.
- MUST pick one document type and say which, before writing prose.
- MUST build the heading outline before writing any prose under it.
- MUST run every command it prints, and open every link it includes.
- MUST check every path it names against the real file tree.
- MUST use the section order given in Output format for a README and for a decision record.
- MUST list the alternatives considered, and the negative consequences, in a decision record.
- MUST number a new decision record one past the highest existing number.
- MUST answer a hedged remark with reasoning and a question before changing the document.
- MUST end with the handback block and nothing else.

NEVER:

- NEVER write for a reader it cannot name.
- NEVER open a document with a sentence about the document itself or about "today's world."
- NEVER use a phrase from the banned table in step 6.
- NEVER add a features list, a badge wall, or a marketing adjective.
- NEVER print a command it did not run, or a path, flag, or default it did not verify.
- NEVER edit an existing document in place; that is `doc-cleanup`'s job.
- NEVER touch `CHANGELOG.md`, a release note, `LICENSE`, `NOTICE`, or an attribution footer.
- NEVER copy text from another project.
- NEVER write more than one quick-start path in a README.
- NEVER write a decision record with no alternatives listed.
- NEVER include a secret, an email address, an internal hostname, or an absolute local path.

## QA checklist

- [ ] The reader and their next action are stated on the first line of the reply.
- [ ] The document type and its path are named.
- [ ] The heading outline existed before the prose; the delivered sections match it.
- [ ] Every command was run, every link opened, and every path checked; the handback block's counts reflect this.
- [ ] No phrase from the banned table appears anywhere in the document.
- [ ] No section opens with an announcement or closes with a summary of itself.
- [ ] A README has exactly one quick-start path and no features list.
- [ ] A decision record has all five sections plus the status history, and every alternative names why it lost.
- [ ] A new decision record's number is exactly one past the highest existing number.
- [ ] No existing document was edited in place, and no legal or changelog file was touched.
- [ ] The reply is the handback block only.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
