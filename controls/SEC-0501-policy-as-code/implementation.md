# SEC-0501 — Policy as Code: Implementation

## Status
Active

## Last Updated
2026-07

---

This document describes the current implementation of
[SEC-0501 — Policy as Code](spec.md).

Conftest (Open Policy Agent) is the tool used to satisfy this
control. It is the current implementation, not the definition of
the control. If Conftest is replaced by another policy engine,
this document changes. The spec does not.

Unlike other controls, the rules this tool enforces are authored
and maintained by this platform, in
[policies/](policies/). Those Rego policies are as much a part of
the control as the tool that runs them.

---

## 1. Tool Selection

**Selected tool:** [Conftest](https://www.conftest.dev/)
(Open Policy Agent / CNCF)

### Why Conftest

| Criterion | Conftest (OPA) | tfsec / Checkov | actionlint |
|---|---|---|---|
| Custom, org-defined rules | Yes (Rego) | Limited / built-in focus | No |
| Evaluates GitHub Actions YAML | Yes | No | Yes (Actions only) |
| Evaluates Terraform | Yes | Yes | No |
| Evaluates arbitrary structured config (YAML/JSON/HCL) | Yes | No | No |
| Rules versioned with the platform | Yes | Partial | No |
| Single engine across file types | Yes | No | No |

Conftest is selected because this control is about enforcing
*our own* configuration rules across multiple file types, not
detecting a fixed catalogue of known misconfigurations. tfsec and
Checkov are strong dedicated Terraform scanners with large built-in
rule sets, but they are Terraform-specific and not designed to
carry custom rules over GitHub Actions workflows. actionlint checks
workflow syntax and common mistakes but does not let us encode
policy such as "reject mutable action references."

A dedicated IaC scanner (tfsec/Checkov) remains a candidate for a
separate control in the SEC-0500 range for broad Terraform coverage.
This control is deliberately scoped to platform-authored policy.

---

## 2. How Conftest / OPA Works

### The evaluation flow

```
On a pull request:

1. The reusable workflow checks out TWO repositories:
   - the consumer repo (the files to be evaluated)
   - standardized-security (the Rego policies)

2. Conftest parses each target file into structured data
   (.yml -> YAML object, .tf -> HCL object)

3. Conftest evaluates the parsed data against the Rego policies
   Each policy is a set of `deny` (or `warn`) rules

4. Any `deny` rule that matches produces a failure with a message
   Conftest exits non-zero if any deny rule matched

5. A non-zero exit fails the job, which (as a required check)
   blocks the pull request
```

### Why two checkouts

This is the structural difference from every prior control. The
policies are not built into the tool — they are files in
`standardized-security/controls/SEC-0501-policy-as-code/policies/`.
The reusable workflow must therefore retrieve the platform
repository (its own repository) in addition to the consumer's, so
Conftest has the policies to evaluate against. Every consumer is
evaluated against the same centrally-maintained policy set.

### Rego in one paragraph

A Rego policy is a set of rules in a named package. Rules named
`deny` (by convention) evaluate to a set of violation messages: if
the set is non-empty, Conftest reports failures. A rule "fires"
when its body conditions all hold for some input. Policies are pure
functions of the input document — no side effects, no state.

---

## 3. Configuration Decisions

### Policy 1 — action references must not be mutable branches

**File:** [policies/workflows.rego](policies/workflows.rego)
**Applies to:** `.github/workflows/*.yml`

Every `uses:` reference is split on `@`. The ref (the part after
`@`) is accepted only if it is:
- a semantic-version tag (`v1`, `v1.2.3`), or
- a full 40-character commit SHA

Any other ref — a branch name such as `@main`, `@master`, `@develop`
— is denied. Local actions (`./...`) and Docker references
(`docker://...`) are out of scope for this rule.

This is the direct enforcement of
[T-CICD-010](../../threat-models/infrastructure/ci-cd-pipeline.md).
As documented in the spec (Section 6), accepting tags leaves the
threat *partially* mitigated: a tag is still mutable. The rule
rejects the worst and most common case (branch references) while
remaining consistent with the current `@v1` versioning guidance in
[docs/architecture.md](../../docs/architecture.md).

### Policy 2 — top-level workflows must declare explicit permissions

**File:** [policies/workflows.rego](policies/workflows.rego)
**Applies to:** `.github/workflows/*.yml`

A workflow that is triggered by an event (`on: push`,
`on: pull_request`, etc.) must declare a `permissions:` block. When
it does not, `GITHUB_TOKEN` is granted GitHub's broad default
permissions — the condition described by
[T-CICD-008](../../threat-models/infrastructure/ci-cd-pipeline.md).

**Reusable workflows (`on: workflow_call`) are exempt.** They
inherit permissions from the calling workflow, so an absent
`permissions:` block is correct, not a defect. Flagging them would
produce debatable findings on legitimately-configured files and
erode trust in the control. Requiring explicit permissions on
reusable workflows as a non-blocking `warn` is noted as a future
tightening (Section 8).

### Policy 3 — Terraform resources must carry required tags

**File:** [policies/terraform.rego](policies/terraform.rego)
**Applies to:** `*.tf`

Taggable resources must define `tags` including at minimum
`Environment` and `Owner`. Untagged infrastructure cannot be
attributed to a team or lifecycle, which blocks both incident
response and cost/ownership governance.

### Policy 4 — Terraform must not use known-insecure defaults

**File:** [policies/terraform.rego](policies/terraform.rego)
**Applies to:** `*.tf`

A small set of unambiguous insecure defaults is denied — for
example an S3 bucket with a public-read ACL, or a security group
rule open to `0.0.0.0/0` on an administrative port. This is not a
substitute for a dedicated IaC scanner; it encodes a few high-value
rules the platform chooses to enforce directly.

### Policy retrieval and pinning

Because the policies are retrieved from the platform at evaluation
time, the reference a consumer pins for the reusable workflow
(`@v1`, `@main`) also determines which policy version evaluates
their files. Tightening a policy is therefore a change that can
newly fail previously-passing configurations, and is versioned like
any other breaking interface change.

---

## 4. Exception Management

A configuration that must legitimately violate a policy is handled
in one of two ways, both reviewed in `standardized-security`:

1. **A scoped exception in the policy set.** The Rego rule is
   amended to exclude the specific, justified case — for example a
   named resource or a specific action reference — with a comment
   recording why. The exception is visible, versioned, and reviewed.

2. **A change to the policy itself.** If the rule is wrong or too
   broad, the policy is corrected.

Consumers do not silently disable the check. There is no
consumer-side ignore file, by design: an exception that is invisible
to the platform is indistinguishable from an unnoticed violation.

---

## 5. Running Conftest

The reusable workflow evaluates the two file sets against their
respective policy packages:

```bash
# Workflow files against the workflow policy package
conftest test \
  --policy "$POLICY_DIR" \
  --namespace workflows \
  .github/workflows/*.yml

# Terraform files against the terraform policy package
conftest test \
  --policy "$POLICY_DIR" \
  --namespace terraform \
  --parser hcl2 \
  *.tf
```

`--namespace` selects which Rego package's `deny` rules apply to
which files, so a workflow rule is never accidentally evaluated
against a Terraform file. `$POLICY_DIR` points at the policies
retrieved from the platform checkout. Terraform evaluation only
runs when `*.tf` files are present.

---

## 6. Known Limitations

- **Only encoded rules are enforced.** Conftest reports violations
  of the rules we wrote and nothing else. The policy set is a living
  artifact that must grow as new risks are identified.

- **Tag references pass.** Policy 1 rejects branch references but
  accepts semver tags, which are still mutable. T-CICD-010 is
  reduced, not eliminated. Full mitigation (SHA pinning) is a
  documented, deferred tradeoff.

- **Static, pre-merge only.** Files are evaluated at authoring time.
  The control does not observe runtime, and does not detect drift
  between committed configuration and what is actually deployed.

- **Terraform coverage is intentionally narrow.** Policies 3 and 4
  encode a few high-value rules, not comprehensive IaC scanning.
  Broad Terraform misconfiguration coverage requires a dedicated
  scanner as a separate SEC-0500 control.

- **Policy parsing depends on the file being parseable.** A workflow
  or Terraform file Conftest cannot parse fails evaluation (fail
  closed). This is correct behavior but means malformed files
  surface as policy failures rather than parse errors.

---

## 7. Validation

Scenarios that must pass to confirm this implementation is working.
Full procedures are in [tests/README.md](tests/README.md).

| Scenario | Expected result |
|---|---|
| Workflow with a `uses: ...@main` branch reference | Policy 1 fails the job, violation names the file |
| Top-level workflow with no `permissions:` block | Policy 2 fails the job |
| Workflow using only `@vN` tags and explicit permissions | Job passes |
| Terraform resource missing `Environment`/`Owner` tags | Policy 3 fails the job |
| Clean Terraform with required tags and secure defaults | Job passes |

---

## 8. Future Improvements

**Warn mode for reusable-workflow permissions**
Add a non-blocking `warn` rule encouraging explicit `permissions:`
on reusable workflows, without failing the build — consistent with
the spec's guidance to introduce new policies in warn mode before
promoting them to blocking.

**SHA-pinning policy, promoted from tag-pinning**
Once the platform tags a stable `v1` and consumers migrate off
`@main`, a stricter policy variant can require full SHA pinning,
fully mitigating T-CICD-010. This is gated on the versioning
change in `docs/architecture.md`.

**Delegate broad Terraform coverage to a dedicated scanner**
Introduce tfsec or Checkov as a separate SEC-0500 control for
comprehensive Terraform misconfiguration detection, leaving this
control focused on platform-authored policy across file types.

**Policy unit tests**
OPA supports unit testing Rego with `opa test`. Adding test cases
for each policy — a passing input and a failing input — would let
the policy set itself be validated in CI before it is used to gate
consumers.
