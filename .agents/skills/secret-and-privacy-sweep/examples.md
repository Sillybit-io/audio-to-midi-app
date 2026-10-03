## Prompt

> Sweep this diff before I publish the repo. We open-source the billing service next week.

```diff
diff --git a/config/default.yaml b/config/default.yaml
index 8c1d4a2..f0b7e93 100644
--- a/config/default.yaml
+++ b/config/default.yaml
@@ -8,6 +8,8 @@ server:
   port: 8080
   requestTimeoutMs: 15000
 
 billing:
-  endpoint: ${BILLING_ENDPOINT}
+  # Falls back to the shared billing host when the variable is unset.
+  endpoint: ${BILLING_ENDPOINT:-https://internal-billing.corp.example/v2}
   retries: 3
+  webhookSecret: ${BILLING_WEBHOOK_SECRET}
diff --git a/test/fixtures/invoice.json b/test/fixtures/invoice.json
index 2b9f101..c47ae20 100644
--- a/test/fixtures/invoice.json
+++ b/test/fixtures/invoice.json
@@ -1,6 +1,9 @@
 {
   "invoiceId": "inv_0001",
-  "customer": { "id": "cus_0001" },
+  "customer": {
+    "id": "cus_0001",
+    "name": "Jane Example"
+  },
   "amountCents": 4200,
   "currency": "EUR"
 }
```

## Without skill

An agent with no skill loaded reads the diff and looks for the shapes it knows a secret takes: a long random string, a key block, a password field with something after the colon. None of those are here. The two observations it makes are both correct, and the conclusion it draws from them is wrong.

````markdown
I read both files in the diff. Nothing in it looks like a credential:

- `config/default.yaml` — both sensitive settings, `BILLING_ENDPOINT` and
  `BILLING_WEBHOOK_SECRET`, are read from environment variables. No values are
  committed, which is the right pattern.
- `test/fixtures/invoice.json` — the customer record is clearly fake.
  `cus_0001` is a sequential placeholder id and "Jane Example" is not a real
  person's name.

No API keys, no access tokens, no passwords, no private key files, no `.env`
file. The diff is safe to publish.
````

Both bullets hold up. The environment-variable indirection is genuinely correct, and the fixture is genuinely synthetic. The failure is in the question the pass never asks: *is anything here sensitive without being secret-shaped?*

The new fallback on the `endpoint` line is not a secret. Nothing in it grants access, no scanner rule matches it, and reading it aloud sounds like ordinary configuration. It is also the one line in this diff that tells a stranger something about the company's private network. An unguided pass slides past it because it was searching for values that unlock things, and this is a value that describes things. A regex scanner misses it for the same reason, which is why "gitleaks came back clean" is not an answer either.

## With skill

secret-and-privacy-sweep is fed the identical diff. The scope is fixed first, gitleaks runs first and comes back clean, and then all six categories are walked anyway — including the four that turn out clean, because a category reported without being listed is a category nobody can check.

````markdown
# Secret and privacy sweep — billing-service staged diff — 2026-09-24

> AI-generated sweep. An automated agent judged these findings. Each one is a claim to check, not a ruling.

**Scope:** staged diff
**History covered:** staged changes only — no line in this diff exists in a commit yet
**Regex scanner:** gitleaks, command `gitleaks dir --no-banner -v .`, 0 findings
**Files examined:** 2

## Findings

### 1. [medium] Internal billing host hardcoded as a configuration fallback — `config/default.yaml:13`

- **Category:** internal infrastructure references
- **What it is:** an internal service hostname, used as the default value of `BILLING_ENDPOINT`. Masked: `in***...***le`. The variable name beside it is not the finding; the literal fallback is.
- **Why it is risky:** the line names an internal billing service and shows the subdomain convention that service sits under. A reader of the published repository learns that the service exists, what it is called internally, and how internal names are formed. That is one fragment of a network map, and fragments accumulate: the next two configuration defaults someone adds will sit in the same file, in the same shape. The fallback also changes behaviour, not just documentation — an unset variable silently points production traffic at an internal name instead of failing. Severity is `medium` rather than `high` because this is a service name with no credential attached, and the host sits on a reserved documentation domain, so the specimen resolves nowhere: the disclosure is the naming, not a reachable endpoint.
- **In git history:** no — the line is staged and has never been committed.
- **Remediation:** delete the fallback and let startup fail when `BILLING_ENDPOINT` is unset, or keep the default in the deployment configuration that is not published. A missing endpoint should be a loud error, not a silent redirect.
- **History rewrite needed?** no — the value exists only in the staged change, so removing it before the commit is enough.
- **Executed by:** a human. This skill recommends only.

## What I checked

| Category | Looked at | Result |
| --- | --- | --- |
| Credentials, tokens, and keys | both files, plus the comment added above the `endpoint` line | clean — `BILLING_ENDPOINT` and `BILLING_WEBHOOK_SECRET` appear as variable names with nothing beside them |
| Personal data | `test/fixtures/invoice.json` | clean — the surname is a placeholder word and `cus_0001` is a sequential fixture id, not an account identifier |
| Internal infrastructure | `config/default.yaml` | 1 finding |
| Business-confidential terms | the added comment, both file paths | clean — no codename, no unreleased product name, no roadmap date, no customer or partner name |
| Environment-file values | `config/default.yaml` | clean — the diff adds a variable reference, not a value copied out of an environment file |
| High-risk file types | the diff's file list | clean — two text files, YAML and JSON; no certificate, keystore, dump, or data export |

## Not covered by this sweep

- Every file this diff does not touch. A staged-diff scope cannot see a secret that has sat in a tracked file since before this branch.
- Git history. Nothing committed was read.
- The deployment configuration that supplies `BILLING_ENDPOINT` in production. It is not in this repository.

SWEEP: PASS
````

Three things in that report are worth naming, because they are the parts a generic pass cannot reach.

The verdict is `PASS` and the diff is not cleared. No finding carries `block`, so the sweep passes by its own rule — and the `medium` finding stays above the verdict line, still owed a decision before the repository goes public. A passing sweep says "no blocker", never "ship it".

The clean rows earn their place. Four of the six categories found nothing, and each one says what it looked at and why the result is clean. The environment-file row is the clearest case: the diff adds `webhookSecret: ${BILLING_WEBHOOK_SECRET}`, which looks alarming and is not a finding, because a variable name belongs in the repository and only a value beside it would not. Writing that down is what stops the next reader from re-litigating it.

The scope is wrong for the stated goal, and the report says so. The request was "before I publish", and a staged diff answers a narrower question than publishing asks. The sweep does not quietly upgrade its own scope, and it does not let the mismatch pass unmentioned: it reports honestly on what it read, and names the full-tree sweep the publish still needs.
