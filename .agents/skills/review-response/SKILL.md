---
name: review-response
description: Works through the review comments on your own pull request or merge request, as the author. It fetches every comment surface — conversation comments, inline review comments, and review summary bodies — groups inline comments into threads, then classifies each comment as must-fix, valid-suggestion, opinion, or question and drafts a substantive reply for every one. An opinion gets a polite pushback that cites a real reason. A question gets a direct answer. The output is a response-plan table plus a resolution checklist that accounts for every comment. Use when you say help me respond to these review comments, triage this PR feedback, draft replies to my reviewers, I disagree with this review comment, or what do I do with all this PR feedback. It drafts and plans only. Nothing is posted until you approve the text, and it never resolves threads, edits code, approves, or merges.
license: CC-BY-ND-4.0
metadata:
  version: "0.1.0"
  category: review
---

# review-response

## Purpose

review-response serves the author of a change, not the reviewer. Its job is to get you through a pile of review comments quickly and honestly. There are two ways to fail at that, and they look nothing alike. The first is caving: agreeing with every comment because agreement ends the thread faster than thinking does, so the code drifts toward whatever the last reviewer preferred. The second is quiet attrition: a comment you find awkward gets no reply, the thread scrolls out of view, and the reviewer never learns whether you read it. Both leave the reviewer guessing. This skill prevents both by making every comment carry a classification, a planned action, and a drafted reply, then by counting the comments at the end so nothing can slip out of the list. It writes a plan and reply text. It does not edit code, resolve threads, approve, or merge.

## When to use / when NOT to use

Use review-response when you:

- Have review comments on an open pull request or merge request and need to work through them.
- Got a large review and want a plan before you start editing anything.
- Disagree with a comment and want to push back with a stated reason instead of arguing or caving.
- Need every thread accounted for before you ask for a re-review.
- Are answering for a change an agent wrote and need to check each comment against the code yourself.

Do NOT use review-response when you:

- Are the reviewer writing the findings. Use ai-review for that side.
- Want the change described rather than answered. Use pr-description.
- Want the fixes implemented. This skill plans the fix and drafts the reply; it does not change code.
- Have no review comments yet.
- Want threads resolved or closed in bulk. It never does that.

## Workflow

1. Identify the target: a pull request number on GitHub or a merge request id on GitLab. Note which forge you are on, because the fetch commands differ.
2. Check which tool is authenticated. Run `gh auth status` for GitHub or `glab auth status` for GitLab. Record the answer; step 13 depends on it.
3. Fetch every comment surface listed below. A pull request holds comments in more than one place, and a plan built from one surface silently drops the others.
4. Group the inline comments into threads. On GitHub a comment carries `in_reply_to_id` only when it is a reply, so a comment without that field is the root of a thread. On GitLab each discussion arrives with its notes already grouped.
5. Read each thread to its last reply before you classify it. A later reply often settles the question, and answering a thread that already closed wastes the reviewer's attention.
6. Read the current resolution state so you do not re-answer a settled thread. Skip the threads that are already resolved and say how many you skipped.
7. Write the comment inventory: every comment, with its id, its author, and its location. Nothing leaves this inventory because it looked minor, because you disagree with it, or because answering it is awkward.
8. Open the code at each cited location and read it before you classify the comment. Classify from the code, not from the comment.
9. Classify each comment into exactly one of the four categories below.
10. Write the response-plan table in the shape given in Output format.
11. Draft the reply text for every comment, following the drafting rules below.
12. Build the resolution checklist and the count line. The count must equal the number of comments you fetched.
13. Show the full plan and every drafted reply to the user. Stop here. Post nothing yet.
14. After the user approves, post through the matching mode in Posting modes. Say which mode you used.
15. Walk the QA checklist.

### Comment surfaces to fetch

| Forge | Surface | What lives there |
| --- | --- | --- |
| GitHub | Conversation comments | Top-level discussion on the pull request, not tied to a line. |
| GitHub | Inline review comments | Line-level and file-level comments on the diff. These form threads. |
| GitHub | Review summary bodies | The text a reviewer wrote when approving or requesting changes. |
| GitLab | Discussions | Both general notes and diff notes, already grouped into discussions. |

On GitHub, read the conversation comments and the inline comments:

```sh
gh pr view <number> --comments
```

```sh
gh api repos/{owner}/{repo}/pulls/<number>/comments --method GET \
  --jq '.[] | {id, in_reply_to_id, user: .user.login, path, line, side, url: .html_url, body}'
```

Then read the review summary bodies, because a "requesting changes" review often states the blocking requirement in its body and nowhere else:

```sh
gh api repos/{owner}/{repo}/pulls/<number>/reviews --method GET \
  --jq '.[] | {id, user: .user.login, state, body}'
```

`gh api` sends `GET` by default and switches to `POST` as soon as you add a parameter with `-f` or `-F`. Keep these three calls free of `-f` and `-F`, and pass `--method GET` when you want to be explicit. `{owner}` and `{repo}` are substituted from the current repository.

Read which threads are already resolved through the GraphQL API, since the REST comment payload does not carry a resolved flag. `databaseId` on the first comment of a thread is the same id the REST calls returned, which is how you match the two:

```sh
gh api graphql -f query='
  query {
    repository(owner: "<owner>", name: "<repo>") {
      pullRequest(number: <number>) {
        reviewThreads(first: 100) {
          nodes { isResolved isOutdated path comments(first: 1) { nodes { databaseId } } }
        }
      }
    }
  }'
```

On GitLab, `glab mr view <id> --comments` shows the comments and the activity, and takes `--resolved` or `--unresolved` to narrow the list:

```sh
glab mr view <id> --comments
```

`glab mr note list` gives the same discussions in a form you can filter and parse. It takes `--type all|general|diff|system`, `--state all|resolved|unresolved`, `--file <path>`, and `--output text|json`:

```sh
glab mr note list <id> --state unresolved --output json
```

Two notes before you rely on the GitLab side. First, `glab mr note list`, `glab mr note create`, and `glab mr note resolve` are all marked experimental upstream, so run `glab mr note list --help` on the installed version and fall back to `glab mr view --comments` for reading when a subcommand or flag is missing. Second, `-F` means `--output` on `glab` and `--field` on `gh`; write `--output` in full to avoid the collision.

Command sources: `cli.github.com/manual/gh_pr_view` and `gh pr view --help` for the conversation comments, `docs.github.com/en/rest/pulls/comments` for the review-comment endpoints and their fields, and the generated command documentation plus the command source in `gitlab.com/gitlab-org/cli` at tag `v1.119.0` for the `glab` commands.

### The four classifications

Give every comment exactly one of these. The classification decides the reply, so getting it wrong produces a polite answer to the wrong question.

| Classification | What the comment is | What you do |
| --- | --- | --- |
| `must-fix` | A real defect, or a blocking requirement: a correctness or security hole, a failing requirement, or a rule this repository actually enforces. | Fix it. The reply names what changed and where. |
| `valid-suggestion` | A genuine improvement that is not a defect. The code works; this would make it better. | Take it, or defer it with a reason and a place where it is tracked. |
| `opinion` | A preference about style, naming, or design where you may reasonably disagree. | Push back politely with a concrete reason, or take it anyway and say so. |
| `question` | The reviewer is asking something, not asserting something. | Answer it directly. Do not turn it into a code change unless the answer uncovers a defect. |

Classify from the code and from this repository's conventions, never from the reviewer's tone or seniority. A firmly worded preference is still an `opinion`. A hedged remark that happens to describe a real defect is still `must-fix`. And a `must-fix` does not become a `valid-suggestion` because the fix is inconvenient or the change is nearly merged.

Taking an `opinion` you do not share is a legitimate choice and often the cheapest one. What is not legitimate is pretending to agree. Say "your call, changed it" rather than inventing a reason you now believe it.

### Reply drafting rules

- Every reply says something a reader can act on. A bare "will fix" tells the reviewer nothing about what you understood, so they have to re-review from scratch to find out.
- A `must-fix` reply names the change and its location.
- A `valid-suggestion` reply that defers says why not now and where it is tracked.
- An `opinion` pushback carries its reason inside the reply: the repository convention and the file that establishes it, the stated requirement, or the specific technical evidence.
- A `question` reply answers the question in its first sentence. "I do not know yet" is a real answer; guessing is not.
- Keep it direct and respectful. No apology theatre, no inflated praise, no sarcasm.
- Write short sentences in your own voice. Thank the reviewer when the thanks is real, and once.
- Never describe a code change you have not made. If the fix is not written yet, say what you plan to do.

### Posting modes

Nothing is posted until the user has read the drafts and approved them. After that, use the matching mode and name it in your reply.

Mode a — GitHub. Reply into an inline thread with the id of the thread's root comment, which is the one that had no `in_reply_to_id`. GitHub does not support replying to a reply:

```sh
gh api repos/{owner}/{repo}/pulls/<number>/comments/<root-comment-id>/replies \
  --method POST \
  -f body='<reply text>'
```

Answer a conversation comment on the pull request itself:

```sh
gh pr comment <number> --body-file <path-to-reply-file>
```

Mode b — GitLab. Reply into an existing discussion by its id. `--reply` takes the full discussion id or a unique prefix of at least eight characters, and cannot be combined with `--file`, so reply by discussion id rather than by file and line:

```sh
glab mr note create <id> --reply <discussion-id> --message "<reply text>"
```

Add a general note when the comment was not part of a discussion:

```sh
glab mr note create <id> --message "<reply text>"
```

Mode c — neither tool is available or authenticated. Create `reports/` if it does not exist, write the whole plan to `reports/review-response-<PR-or-MR-number>-<YYYY-MM-DD>.md`, then say plainly that nothing was posted, which tool was missing, and where the file is.

## Output format

Produce one response plan in this shape.

````markdown
## Review response plan

**Target:** <pull request or merge request reference> — N comments across N threads.
**Surfaces fetched:** conversation N, inline N, review summaries N.
**Already resolved upstream:** N threads, skipped.

### Response plan

| # | Comment | Type | Planned action | Drafted reply |
| --- | --- | --- | --- | --- |
| 1 | "<the reviewer's own words>" — `path/to/file:42` (@reviewer) | must-fix | <the change you will make> | <reply, or its first sentence and "full text below"> |
| 2 | "<the reviewer's own words>" — conversation (@reviewer) | opinion | push back, keep the current form | <reply carrying the reason> |
| 3 | "<the reviewer's own words>" — `path/to/other:88` (@reviewer) | question | answer, no code change | <the direct answer> |

### Drafted replies

#### 1 — `path/to/file:42` — must-fix

> <the comment, quoted>

<the full reply text, ready to post as written.>

#### 2 — conversation — opinion

> <the comment, quoted>

<the full reply text. It names the convention, the requirement, or the evidence behind the pushback.>

### Resolution checklist

- [ ] 1 — `path/to/file:42` — must-fix — addressed in code
- [ ] 2 — conversation — opinion — replied only
- [ ] 3 — `path/to/other:88` — question — replied only
- [ ] 4 — `path/to/third:12` — valid-suggestion — needs author decision

### Counts

must-fix N · valid-suggestion N · opinion N · question N — total N, which equals the N comments fetched.
````

Rules for the plan:

- Every fetched comment appears exactly once in the table and exactly once in the checklist. The count line is the proof that none were dropped, so write it even when there is one comment.
- Order the table by classification, `must-fix` first, then by location. That order is also the order to do the work in.
- Quote the reviewer's own words. Never paraphrase a comment into a weaker or easier version of itself; summarise only when the comment is long, and say you summarised.
- Keep table cells short. When a reply runs past about two sentences, put the full text under Drafted replies and leave its first sentence in the cell.
- The three checklist statuses mean exactly this: `addressed in code` — a change exists that answers the comment; `replied only` — you answered or pushed back and no code changed; `needs author decision` — the call belongs to the user, because it is a product question, an unclear requirement, or a trade-off that is not yours to make.
- Describe fixes in words. Do not attach a patch and do not commit one.

## Guardrails

MUST:

- MUST fetch every comment surface for the forge before you classify anything.
- MUST group inline comments into threads with `in_reply_to_id` on GitHub, and read each thread to its last reply before classifying it.
- MUST open the code at the cited location and read it before you classify a comment.
- MUST give every comment exactly one of `must-fix`, `valid-suggestion`, `opinion`, `question`.
- MUST account for every fetched comment exactly once in the response-plan table and exactly once in the resolution checklist, and print the count line that proves it.
- MUST quote the reviewer's own words, and say so when you summarised a long comment.
- MUST draft substantive reply text for every comment, including the ones you agree with.
- MUST cite a concrete reason in every `opinion` pushback: a repository convention and the file that establishes it, a stated requirement, or specific technical evidence.
- MUST show the full plan and every drafted reply to the user and wait for approval before anything is posted.
- MUST mark a comment `needs author decision` when the call is not yours to make.
- MUST report which posting mode ran, and say plainly when nothing was posted.

NEVER:

- NEVER post a reply before the user has seen the drafted text and approved it.
- NEVER mark a thread resolved without either a code change that addresses it or an explicit agreed answer recorded in the reply. Closing a thread does not answer it.
- NEVER resolve, close, approve, or merge on your own initiative. Do not run `glab mr note resolve`, `gh pr merge`, `gh pr review --approve`, `glab mr approve`, or `glab mr merge`. Hand the user the command and let them run it.
- NEVER modify code, tests, or configuration. This skill produces a plan and reply text only.
- NEVER create a branch, a commit, or a tag, and never push.
- NEVER drop a comment because it looked minor, because you disagree with it, or because answering it is awkward.
- NEVER agree with a comment you did not check against the code. Silent agreement to end a thread is the failure this skill exists to prevent.
- NEVER classify by the reviewer's tone or seniority, and never downgrade a `must-fix` because the fix is inconvenient or the change is nearly merged.
- NEVER push back with "I disagree" and no reason.
- NEVER claim a code change you have not made.
- NEVER argue about the reviewer. Answer the comment.
- NEVER paste a secret value, a personal email address, or a customer identifier into a reply. Review threads are usually public.

## QA checklist

Run this list before you show the plan, and again before you post.

- [ ] Every comment surface for the forge was fetched, and the counts per surface are in the header.
- [ ] Inline comments are grouped into threads, and each thread was read to its last reply.
- [ ] Threads already resolved upstream were identified and the skipped count is stated.
- [ ] The code at every cited location was opened and read before classification.
- [ ] Every comment carries exactly one of `must-fix`, `valid-suggestion`, `opinion`, `question`.
- [ ] Every comment appears exactly once in the table and exactly once in the checklist.
- [ ] The count line totals to the number of comments fetched.
- [ ] Quotes use the reviewer's own words, and any summary is marked as a summary.
- [ ] Every comment has a drafted reply, and no reply is a bare "will fix".
- [ ] Every `opinion` pushback cites a convention, a requirement, or technical evidence.
- [ ] Every reply that claims a code change refers to a change that exists.
- [ ] Each checklist entry carries one of `addressed in code`, `replied only`, `needs author decision`.
- [ ] The full plan and every draft were shown to the user, and approval was given before posting.
- [ ] No thread was marked resolved without a code change or a recorded agreed answer.
- [ ] Nothing was resolved, closed, approved, or merged by this skill.
- [ ] No code, test, or configuration file changed during the run.
- [ ] The posting mode used is named, or the fallback report path is reported.
- [ ] No reply contains a secret value, personal data, or a customer identifier.

<!-- markdownlint-disable-next-line MD034 -->
© Sillybit — https://github.com/Sillybit-io/silly-skills — CC BY-ND 4.0. Attribution required; do not republish modified versions without written approval.
