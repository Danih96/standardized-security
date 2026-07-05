# Threat Model — CI/CD Pipeline Infrastructure

## Status
Active

## Last Updated
2026-06

## Scope

This document models threats to the CI/CD pipeline infrastructure
itself — the systems that build, test, and deliver software.

It is not a threat model for any application that runs on top of
this infrastructure. Application-specific threat models belong in
each application repository. See
[../methodology/template.md](../methodology/template.md).

---

## 1. Assets

| Asset | Description |
|---|---|
| Source code | Application code stored in GitHub repositories, including all branches and git history |
| CI/CD secrets | GitHub Actions secrets, cloud provider access keys, registry credentials, signing keys, and any token passed to the runner environment |
| Build artifacts | Binaries, container images, and other outputs produced by the CI pipeline |
| Reusable workflows | Workflow definitions in `standardized-security` that execute in every consumer CI environment |
| Pipeline runner environment | The GitHub Actions runner process, its filesystem, its environment variables, and its network access during a workflow run |

---

## 2. Trust Boundaries

### Boundary 1 — Developer workstation → GitHub repository

A developer pushes commits or opens a pull request. GitHub has no
way to verify that the local environment was uncompromised or that
the developer's identity was not stolen. Any code that reaches
GitHub is treated as potentially hostile until it passes CI controls.

### Boundary 2 — GitHub repository → CI runner

GitHub Actions provisions a runner and passes secrets from the
repository's encrypted secret store. The runner receives the
`GITHUB_TOKEN` and any explicitly declared secrets. Code in the
workflow definition — which may include code from a pull request —
runs with these credentials.

This boundary is the highest-risk point in the pipeline.
A workflow that executes untrusted code with access to CI/CD secrets
is the primary attack surface for credential exfiltration.

### Boundary 3 — CI runner → external services

The runner makes outbound connections to package registries (npm,
PyPI, Docker Hub, Maven Central), artifact stores, and any external
API called by the build or test process. The runner trusts that
packages and images retrieved from these services are what they
claim to be.

### Boundary 4 — CI runner → deployment environment

The runner pushes build artifacts to a registry or triggers a
deployment. The deployment environment trusts that the artifact
received is the artifact the CI pipeline produced.

---

## 3. Threat Actors

**External attacker**
No initial access to the organization's systems. Capable of
publishing malicious packages, exploiting public-facing services,
or compromising external dependencies.

**Compromised developer account**
Holds valid GitHub credentials with access to one or more
repositories. The account may have been stolen via phishing,
credential stuffing, or malware. The attacker operates within
the access level of the compromised account.

**Malicious dependency**
A third-party package that contains intentionally harmful code,
either introduced by the original maintainer (insider threat) or
by a supply chain compromise of the package maintainer's account.
Executes during `npm install`, `pip install`, or equivalent.

**Malicious PR contributor**
A contributor who opens a pull request to an organization's
repository with the intent of achieving code execution in the CI
environment. Relevant primarily to open-source or open-contribution
repositories where pull requests from unknown parties are accepted.

---

## 4. Threats

---

### T-CICD-001 — Secret committed to source code

**Actor:** Developer (accidental); Compromised developer account (intentional)

**Attack vector:**
A developer commits a secret — API key, database credential, private
key — directly to source code or git history. The secret is
distributed to every clone of the repository and is accessible to
anyone with read access.

**Impact:**
Unauthorized access to the system or service protected by the
credential. Lateral movement to connected systems. The exposure
window begins at the time of the commit and ends only after the
secret is rotated — which may be days or never.

**Affected assets:**
Source code, CI/CD secrets (if the committed secret is a CI token
or cloud key)

**Mitigating control:**
SEC-0101 — Secret Detection (Milestone 1, active)

---

### T-CICD-002 — Dependency with known CVE introduced pre-merge

**Actor:** Developer (accidental); Compromised developer account

**Attack vector:**
A pull request adds or upgrades a dependency that contains a known
vulnerability. The vulnerability enters the main branch and is
built into production artifacts. Transitive dependencies — packages
pulled in by direct dependencies without developer awareness — are
the most common source of this threat.

**Impact:**
Runtime exploitation of the application or CI runner. Depending
on the CVE, impact ranges from denial of service to remote code
execution or data exfiltration.

**Affected assets:**
Build artifacts, pipeline runner environment

**Mitigating control:**
SEC-0201 — Dependency Scanning (Milestone 2, planned)

---

### T-CICD-003 — Malicious package introduced via dependency confusion

**Actor:** External attacker

**Attack vector:**
The attacker identifies an internal package name used by the
organization and publishes a public package with the same name at
a higher version number on a public registry (npm, PyPI, etc.).
Package managers that check public registries before private ones
resolve the malicious version automatically, executing its install
scripts during `npm install` or equivalent.

**Impact:**
Arbitrary code execution on the CI runner during dependency
installation. The runner's environment, secrets, and network access
are available to the malicious install script. Produced artifacts
may be backdoored.

**Affected assets:**
Pipeline runner environment, CI/CD secrets, build artifacts

**Mitigating control:**
TBD — requires private registry configuration with registry
precedence enforcement and package allowlisting. No current control
planned for this milestone range.

---

### T-CICD-004 — Compromised CI runner exfiltrates secrets

**Actor:** External attacker; Malicious dependency; Malicious PR contributor

**Attack vector:**
An attacker achieves code execution on the CI runner through one
of several vectors: workflow injection (T-CICD-007), a malicious
dependency install script (T-CICD-003), or a compromised action.
The runner's environment variables, secret files, and network
access are then available for exfiltration.

**Impact:**
Complete exposure of all secrets passed to the runner, including
the `GITHUB_TOKEN`, cloud provider credentials, registry tokens,
and signing keys. These secrets can be used immediately or stored
for later use. The exposure may not be detectable.

**Affected assets:**
CI/CD secrets, pipeline runner environment

**Mitigating control:**
TBD — partial mitigation through least-privilege `GITHUB_TOKEN`
permissions (T-CICD-008) and workflow hardening (T-CICD-007).
Full mitigation requires runner isolation and secret scoping beyond
the current milestone range.

---

### T-CICD-005 — Unsigned or tampered container image deployed

**Actor:** External attacker

**Attack vector:**
A container image is pushed to a registry without a cryptographic
signature. An attacker who gains write access to the registry, or
who can intercept the image in transit, can replace the image with
a malicious version. The deployment system has no way to verify
that the deployed image is the image the CI pipeline produced.

**Impact:**
Deployment of malicious code to production. The attack is invisible
to the application team unless runtime behavior reveals the
tampering. Discovery may occur only after significant damage.

**Affected assets:**
Build artifacts

**Mitigating control:**
SEC-0401 — Image Signing and Verification (Milestone 5, planned)

---

### T-CICD-006 — Vulnerable base image used in container build

**Actor:** External attacker

**Attack vector:**
The application container is built using a base image (e.g.,
`ubuntu:22.04`, `node:20-alpine`) that contains packages with
known CVEs. The vulnerability is incorporated into every image
built on that base and is present in the production runtime
environment.

**Impact:**
Runtime exploitation of the deployed container. Depending on the
CVE, impact ranges from privilege escalation within the container
to container escape and host compromise.

**Affected assets:**
Build artifacts

**Mitigating control:**
SEC-0301 — Container Image Scanning (Milestone 3, planned)

---

### T-CICD-007 — Workflow injection via untrusted input

**Actor:** Malicious PR contributor; External attacker

**Attack vector:**
A GitHub Actions workflow interpolates untrusted input — a pull
request title, branch name, commit message, or issue body — directly
into a `run:` step using expression syntax
(`${{ github.event.pull_request.title }}`). An attacker crafts a
PR with a title containing shell metacharacters or commands, which
are executed by the runner when the workflow processes the
expression.

**Impact:**
Arbitrary shell command execution on the CI runner with access to
all secrets available in the workflow context. Equivalent in impact
to T-CICD-004.

**Affected assets:**
CI/CD secrets, pipeline runner environment

**Mitigating control:**
TBD — requires workflow hardening: binding untrusted input to
environment variables before use in shell steps, avoiding direct
expression interpolation in `run:` contexts, and using
`pull_request_target` cautiously. No dedicated control planned
for this milestone range.

---

### T-CICD-008 — Excessive CI token permissions enabling lateral movement

**Actor:** Any actor with code execution on the runner (see T-CICD-004)

**Attack vector:**
The `GITHUB_TOKEN` issued to a workflow run is granted broad
permissions — `contents: write`, `packages: write`, or equivalent.
An attacker who achieves runner access (via any vector) uses the
token to push code to protected branches, create releases containing
malicious artifacts, or access other repositories within the
organization.

**Impact:**
Lateral movement within the GitHub organization. Code injection
into protected branches. Malicious release artifacts distributed
to users. Token abuse may be logged but is unlikely to be detected
in real time.

**Affected assets:**
Source code, CI/CD secrets, reusable workflows, build artifacts

**Mitigating control:**
TBD — requires explicit `permissions:` declarations in all workflow
files, restricting each job to the minimum token scope required.
No dedicated control planned for this milestone range.

---

### T-CICD-009 — Artifact tampering between build and deployment

**Actor:** External attacker

**Attack vector:**
A build artifact — binary or container image — is produced
correctly by the CI pipeline and pushed to a registry or artifact
store. Between the push and the deployment, an attacker with write
access to the registry replaces the artifact with a malicious
version. The deployment system retrieves the artifact by tag or
name rather than by digest, and the substitution is not detected.

**Impact:**
Deployment of a malicious artifact to production with no visible
indication of tampering. Distinguished from T-CICD-005 in that
the image may have been signed at build time but the deployment
system does not verify the signature.

**Affected assets:**
Build artifacts

**Mitigating control:**
SEC-0401 — Image Signing and Verification (Milestone 5, planned).
Full mitigation requires both signing at build time and digest-based
verification at deploy time.

---

### T-CICD-010 — Reusable workflow pinned to mutable reference

**Actor:** External attacker

**Attack vector:**
A consumer workflow references a reusable workflow using a mutable
reference — a branch name (`@main`) or a version tag (`@v1`).
If the referenced branch or tag is updated with malicious content
— through a compromised maintainer account, a repository takeover,
or a deliberate supply chain attack — all consumer workflows
execute the malicious code on their next run without any change
to the consumer's repository.

**Impact:**
Code execution across every CI environment that consumes the
affected workflow. Mass exfiltration of secrets from all consumer
repositories simultaneously. Impact scales with the number of
consumers.

**Affected assets:**
CI/CD secrets, pipeline runner environment, build artifacts,
reusable workflows

**Mitigating control:**
TBD — full mitigation requires pinning to immutable commit SHAs
(`@abc1234...`) rather than mutable tags or branches. Automated
enforcement (e.g., a workflow linting control) is not currently
planned. The versioning guidance in
[docs/architecture.md](../../docs/architecture.md) documents the
risk but does not enforce mitigation.

---

## 5. Residual Risk Summary

| Threat ID | Name | Mitigated by |
|---|---|---|
| T-CICD-001 | Secret committed to source code | Milestone 1 — SEC-0101 (active) |
| T-CICD-002 | Dependency with known CVE | Milestone 2 — SEC-0201 (planned) |
| T-CICD-006 | Vulnerable base image | Milestone 3 — SEC-0301 (planned) |
| T-CICD-005 | Unsigned container image deployed | Milestone 5 — SEC-0401 (planned) |
| T-CICD-009 | Artifact tampering between build and deploy | Milestone 5 — SEC-0401 (planned) |
| T-CICD-003 | Dependency confusion | No planned control |
| T-CICD-004 | CI runner secret exfiltration | No planned control |
| T-CICD-007 | Workflow injection | No planned control |
| T-CICD-008 | Excessive CI token permissions | No planned control |
| T-CICD-010 | Mutable workflow reference | No planned control |

Threats with no planned control represent accepted residual risk
for the current milestone range. They must be reviewed when
the roadmap is updated. Acceptance is not permanent.

---

## 6. DREAD Risk Scoring

STRIDE and the threat catalog above answer "what could go wrong."
DREAD answers "which of these matters most" — a 1-10 score across
five axes (Damage, Reproducibility, Exploitability, Affected users,
Discoverability), averaged into a single number per threat.

### Methodology

Each score below is the **inherent severity of the threat**, assuming
no mitigating control exists — not the residual risk today. This
keeps mitigated and unmitigated threats on the same scale, so a threat
that is already well-controlled (e.g. T-CICD-001) can still be
compared honestly against one with no control at all (e.g. T-CICD-010).
Whether the risk is actually reduced today is a separate question,
answered by the "Status" column and Section 5 above.

| Threat ID | Name | D | R | E | A | Di | Score | Status today |
|---|---|---|---|---|---|---|---|---|
| T-CICD-001 | Secret committed to source code | 8 | 9 | 8 | 6 | 9 | **8.0** | Mitigated (M1) |
| T-CICD-006 | Vulnerable base image in container build | 7 | 9 | 6 | 7 | 8 | **7.4** | Mitigated (M3) |
| T-CICD-002 | Dependency with known CVE introduced pre-merge | 7 | 8 | 6 | 7 | 7 | **7.0** | Mitigated (M2) |
| T-CICD-008 | Excessive CI token permissions | 8 | 9 | 5 | 7 | 6 | **7.0** | No planned control |
| T-CICD-010 | Reusable workflow pinned to mutable reference | 10 | 10 | 3 | 10 | 2 | **7.0** | No planned control |
| T-CICD-004 | Compromised CI runner exfiltrates secrets | 9 | 6 | 5 | 10 | 3 | **6.6** | Partial |
| T-CICD-007 | Workflow injection via untrusted input | 8 | 7 | 6 | 8 | 4 | **6.6** | No planned control |
| T-CICD-003 | Malicious package via dependency confusion | 9 | 5 | 5 | 8 | 4 | **6.2** | No planned control |
| T-CICD-005 | Unsigned or tampered container image deployed | 9 | 6 | 4 | 9 | 3 | **6.2** | Mitigated (M5) |
| T-CICD-009 | Artifact tampering between build and deployment | 9 | 6 | 4 | 9 | 3 | **6.2** | Partial (M5) |

### Next priority, by score, among threats with no planned control

1. **T-CICD-010** (7.0) — reusable workflow pinned to `@main`. Highest
   reproducibility and blast radius of any unmitigated threat: a single
   compromised commit on the platform propagates to every consumer
   repository on their next run, with no action required by the attacker
   beyond the initial compromise.
2. **T-CICD-008** (7.0) — excessive `GITHUB_TOKEN` permissions. Close
   second; unlike T-CICD-010 it requires an attacker to already have
   some code execution on the runner, but it is trivial to fix
   (explicit `permissions:` blocks) relative to its severity.
3. **T-CICD-007 / T-CICD-003** (6.6 / 6.2) — workflow injection and
   dependency confusion, both requiring more attacker setup than the
   two above.

### Limitations of DREAD

- **Subjective inputs.** Two reviewers can reasonably assign different
  scores to the same threat; there is no ground truth like a CVSS
  vector string. Scores here should be read as this platform's
  judgment call, not an objective measurement.
- **Averaging hides outliers.** A threat with catastrophic Damage (10)
  but low scores elsewhere can end up ranked below a threat that is
  moderately bad across all five axes. T-CICD-004 and T-CICD-005 both
  illustrate this: very high Damage and Affected-users scores are
  pulled down by low Discoverability.
- **No shared calibration across organizations.** Unlike CVSS, there is
  no public reference corpus of "what a 7 looks like," which is why
  Microsoft — DREAD's original author — deprecated it internally in
  favor of a simpler bucketed severity scale.
- **Practical use here:** DREAD is used as a lightweight prioritization
  aid on top of the STRIDE-style threat catalog above, not as a
  standalone methodology. It answers "what do we fix next," not "have
  we found everything."
