# SEC-0501 — Policy as Code

## Status
Active

## Last Updated
2026-07

---

## 1. Threat

A workflow definition or infrastructure-as-code file may contain
an insecure configuration that is not a known vulnerability — it is
a design choice. A reusable workflow pinned to a mutable branch, a
job that runs with default (broad) token permissions, or a cloud
resource created without required tags or with an insecure default
all pass through every prior control unchanged, because none of
them evaluate the *structure* or *intent* of configuration files.

Secret detection looks for credentials. Dependency and container
scanning look for known CVEs. Image signing proves artifact
integrity. None of them can say "this workflow grants more
permission than it needs" or "this action reference can be moved
under our feet" — those are policy decisions, not vulnerabilities,
and they require a control that encodes and enforces the
organization's own rules.

**Likelihood without this control:** High
This threat requires no attacker. An insecure configuration enters
the pipeline through an ordinary pull request — a developer copying
an example, a default left unchanged, a tag used instead of a
digest. Every workflow and IaC change is an opportunity to
introduce one, and without an automated gate the only defense is
manual review, which does not scale and is inconsistently applied.

**Impact:** High
The specific impact depends on the misconfiguration. A mutable
action reference exposes every consumer to a single upstream
compromise. Excessive token permissions widen the blast radius of
any runner compromise. An insecure IaC default may expose data or
grant standing access. In each case the misconfiguration is
invisible to the other controls and persists until someone notices
it by hand.

**Relationship to threat model:**
This control mitigates
[T-CICD-010](../../threat-models/infrastructure/ci-cd-pipeline.md)
(reusable workflow pinned to a mutable reference) and
[T-CICD-008](../../threat-models/infrastructure/ci-cd-pipeline.md)
(excessive CI token permissions) — the two highest-scored threats
in the DREAD assessment that previously had no planned control.
Mitigation is partial, not complete: see Section 6.

---

## 2. Assets Protected

- Reusable workflows — the workflow definitions in
  `standardized-security` and in every consumer repository are held
  to a consistent, enforced standard rather than convention
- CI/CD secrets — by requiring least-privilege token permissions,
  the credentials available to any given job are constrained before
  a compromise can exploit them
- Pipeline runner environment — reducing the permissions and
  mutable dependencies a workflow carries reduces the value of
  compromising the runner
- Infrastructure resources — cloud resources defined as code are
  held to tagging, ownership, and secure-default requirements
  before they are ever provisioned

---

## 3. Security Principle

**Secure by Default, Enforced** — Security-relevant configuration
rules are written down as executable policy, versioned alongside
the code, and evaluated automatically on every change. A rule that
is only documented is advisory; a rule that is enforced as code is
a gate.

**Least Privilege, Codified** — The requirement that every job
declare explicit, minimal token permissions is not left to
reviewer memory. It is a policy that fails the build when violated.

**Shift Left** — Configuration governance moves from post-incident
discovery, or manual review, to an automated check that runs before
merge. The insecure configuration is caught at authoring time, when
it is cheapest to fix.

---

## 4. Enforcement Point

This control runs pre-merge, on pull requests, as a blocking check
once registered as a required status check.

The reusable workflow evaluates:
- `.github/workflows/*.yml` — GitHub Actions workflow definitions
- `*.tf` — Terraform infrastructure-as-code files

against Rego policies using Conftest (a wrapper over Open Policy
Agent that tests structured configuration files). A policy
violation fails the job.

**Architectural note — the policies live in the platform.**

Unlike SEC-0101 through SEC-0402, whose tools (Gitleaks, Trivy,
Cosign) ship with their own detection rules, this control's rules
*are* the control. The Rego policies are maintained in
`standardized-security` under
`controls/SEC-0501-policy-as-code/policies/`. The reusable workflow
therefore checks out its own repository — not only the consumer's —
to retrieve the policies before evaluating the consumer's files.

This is a deliberate design choice: it means every consumer is
evaluated against the same, centrally-maintained policy set, and a
policy improvement propagates to all consumers without any change
on their side — the same central-trust property that makes the
reusable-workflow model valuable in the first place.

---

## 5. Failure Mode

**Policy violation → job fails → merge blocked**

If any evaluated file violates a policy, the Conftest step exits
non-zero and the job fails. Once registered as a required status
check, a failing policy evaluation blocks the pull request from
merging.

**Fail closed, not open**

A policy evaluation that cannot run — because the policies could
not be retrieved, or Conftest could not parse a file it was asked
to evaluate — must fail the job, not skip it. A control that
silently passes when it cannot evaluate provides false assurance.

**Policy errors are the platform's responsibility**

A false positive — a policy that fails a configuration that is
actually acceptable — is a defect in the platform's policy set, not
a reason for the consumer to disable the check. Policy changes are
made in `standardized-security` and reviewed like any other control
change.

---

## 6. Limitations

- **The control only checks what the policies encode.** Conftest
  finds violations of the rules we have written. It says nothing
  about configuration risks we have not thought to codify. This is
  a completeness limitation shared by all rule-based controls, and
  it makes the policy set a living artifact that must grow as new
  risks are identified.

- **The policies are this platform's judgment, not a standard.**
  Unlike a CVE database, there is no external authority for "what
  a secure workflow looks like." The rules reflect decisions made
  by this platform and should be read as such.

- **Tag pinning is accepted, so T-CICD-010 is only partially
  mitigated.** The action-reference policy rejects mutable *branch*
  references (`@main`, `@master`) but accepts semantic-version tags
  (`@v1`, `@v1.2.3`). A tag is still mutable — a maintainer with
  write access can move it — so this control reduces, but does not
  eliminate, the mutable-reference threat. Full mitigation would
  require pinning to immutable commit SHAs, which conflicts with the
  current versioning guidance in
  [docs/architecture.md](../../docs/architecture.md) and is deferred
  as a conscious, documented tradeoff.

- **Static, pre-merge only.** This control evaluates files at
  authoring time. It does not observe runtime behavior, and it does
  not detect drift between the committed configuration and what is
  actually deployed. IaC that is applied out of band, or a workflow
  altered after merge, is out of scope.

- **IaC coverage is scoped to what the policies target.** The
  Terraform policies check the specific properties they encode
  (required tags, insecure defaults). They are not a general-purpose
  IaC scanner and do not replace a dedicated tool such as tfsec or
  Checkov for broad Terraform misconfiguration coverage — that is a
  separate control in the SEC-0500 range.

---

## 7. Related Controls

| Control | Relationship |
|---|---|
| All reusable workflows (SEC-0101–SEC-0402) | This control evaluates the workflow files that invoke every other control, holding them to the pinning and permissions policy |
| SADR-002 — Control-Centric Design | Architectural decision that explains why controls are defined independently of tools; this control makes the platform's own rules an enforceable artifact |

---

## 8. Compliance Mapping

| Standard | Reference | Notes |
|---|---|---|
| CIS Software Supply Chain Security Guide | Build Pipelines — pipeline instructions and access | Enforcing least-privilege token permissions and pinned dependencies maps to CIS supply-chain build-pipeline recommendations |
| NIST SSDF (SP 800-218) | PO.3 — Implement supporting toolchains | Policy-as-code is a toolchain control that enforces secure configuration automatically |
| NIST SSDF (SP 800-218) | PW.9 — Configure software with secure settings by default | Enforcing secure defaults on workflow and IaC configuration |
| SLSA | Build L2+ — build platform hardening | Constraining workflow permissions and dependency references contributes to build platform integrity |
| ISO 27001:2022 | A.8.9 — Configuration management | Automated enforcement of secure configuration baselines |

---

## 9. Evidence Generated

When this control executes, it produces:

- A pass or fail result per evaluated file
- For failures, the specific policy that was violated and the file
  and location that violated it, in the Conftest output
- A workflow run record showing which policy version
  (the platform commit) was used to evaluate the change

The Conftest output is the authoritative record of which rules were
evaluated and which were violated for a given pull request.

---

## 10. Operational Requirements

1. **Policy ownership:** the Rego policy set is maintained in
   `standardized-security` and is owned by the platform, not by
   consumers. Policy changes follow the same review process as any
   other control change.

2. **Policy versioning:** because the policies are retrieved from
   the platform at evaluation time, the reference a consumer pins
   (`@v1`, `@main`) determines which policy version evaluates their
   files. Tightening a policy is a change that can newly fail
   configurations that previously passed; it must be versioned and
   communicated like any other breaking change.

3. **Exception handling:** a configuration that must legitimately
   violate a policy requires either a scoped, reviewed exception in
   the policy set, or a documented change to the policy itself.
   Consumers do not silently disable the check.

4. **Policy set growth:** the policy set is expected to grow as new
   configuration risks are identified. New policies should be
   introduced in a non-blocking (warn) mode first where practical,
   then promoted to blocking after consumers have had time to
   remediate.
