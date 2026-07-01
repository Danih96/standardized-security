# SEC-0201 — Dependency Scanning

## Status
Active

## Last Updated
2026-06

---

## 1. Threat

A third-party dependency — direct or transitive — may contain a
known vulnerability (CVE) that can be exploited once the application
is deployed, enabling an attacker to compromise the application,
the data it processes, or the infrastructure it runs on.

**Likelihood without this control:** High
Transitive dependencies are pulled in automatically by package
managers without developer awareness. A single top-level dependency
may introduce dozens of transitive packages. CVEs are continuously
discovered and published; a dependency that was safe at the time it
was added may become vulnerable before the next review cycle.

**Impact:** High
The impact depends on the CVE. Remote code execution, authentication
bypass, privilege escalation, and data exfiltration are all
represented in the historical CVE record for common ecosystems.
Log4Shell (CVE-2021-44228) — a critical RCE in a widely used Java
logging library, typically present as a transitive dependency — is
the canonical example of this threat class.

**Relationship to threat model:**
This control directly mitigates
[T-CICD-002](../../threat-models/infrastructure/ci-cd-pipeline.md).

---

## 2. Assets Protected

- Application runtime and the data it processes
- Production infrastructure accessible from the application
- CI/CD pipeline, if a vulnerable dependency is present in
  build tooling
- Users of the application, if the vulnerability enables
  data exfiltration or integrity compromise

---

## 3. Security Principle

**Shift Left** — Known vulnerabilities are detected at the earliest
point where the dependency graph is available: the pull request that
introduces or updates a dependency. The cost of remediation at this
point is a version change in a manifest file, not an emergency patch
in production.

**Defense in Depth** — This control does not replace runtime
protection, WAF rules, or network segmentation. It reduces the
probability that a known-vulnerable component reaches production,
complementing controls that limit the impact if it does.

---

## 4. Enforcement Point

**Primary:** Pre-merge (pull request CI pipeline)

The control runs as a blocking check on every pull request. This
enforcement point catches new vulnerabilities introduced by
dependency changes before they enter the main branch.

**Limitation of this enforcement point:**
A CVE published after a dependency was merged is not caught by the
pre-merge check alone. A scheduled scan control (not in scope for
this milestone) is required to detect vulnerabilities in
already-merged dependencies as new CVEs are published.

**Complementary (not in scope for this milestone):**
- Scheduled full dependency scan (detective control — identifies
  CVEs published after the dependency was merged)
- Dependency update automation (e.g., Dependabot or Renovate —
  reduces time from CVE publication to fix, but is not a blocking
  control)

---

## 5. Failure Mode

**Default: Fail Closed on High and Critical severity**

If the dependency scan finds a vulnerability at or above the
configured severity threshold, the pipeline fails and the merge
is blocked. The default threshold is HIGH, meaning both HIGH and
CRITICAL severity CVEs are blocking.

MEDIUM and LOW severity findings are reported but do not block
the pipeline by default. This threshold is configurable per
consuming repository.

If the scanning tool itself is unavailable or misconfigured, the
pipeline fails. A scan that does not run provides no protection
and must not be treated as a passing scan.

**Exceptions must be:**
- Scoped to a specific CVE identifier, never to a package or
  ecosystem category
- Documented with a justification and an owner
- Time-limited with a defined review date
- Approved through a defined exception process

Acceptable justifications for exceptions:
- The vulnerable code path is not reachable in this application
- No fix is available and the risk is accepted pending a fix
- The dependency is present in test or build tooling only and
  does not reach the production artifact

Exceptions based on "we'll fix it later" without a review date
are not acceptable.

---

## 6. Limitations

- **Known vulnerabilities only:** this control detects CVEs that
  have been published in the advisory databases consulted by the
  scanning tool. Zero-day vulnerabilities and undisclosed
  vulnerabilities are not detectable.

- **Database freshness:** the scanner is only as current as the
  vulnerability database it uses. A CVE published between the last
  database update and the scan may not be detected.

- **No code path analysis:** the scanner cannot determine whether
  the vulnerable code in a dependency is actually reachable from
  the application. A CVE in a dependency may be reported even if
  the vulnerable function is never called.

- **Transitive dependency visibility depends on lock files:**
  accurate transitive dependency detection requires a lock file
  (`package-lock.json`, `poetry.lock`, `go.sum`, etc.). Without
  a lock file, the scanner may report incomplete results.

- **No fix validation:** detecting a CVE does not guarantee that
  a fixed version exists or is compatible with the rest of the
  dependency graph. Remediation may require significant dependency
  restructuring.

- **No runtime tracking:** this control operates on the dependency
  manifest at build time. It does not track which dependencies are
  loaded at runtime or detect vulnerabilities introduced by dynamic
  dependency loading.

- **Pre-merge scope only:** CVEs published after a dependency is
  merged into the main branch are not detected by this control.
  A scheduled scan control is required for continuous coverage.

---

## 7. False Positives

Common sources of false positives:

- CVEs in test or development dependencies that do not reach the
  production artifact (e.g., a test framework with a known CVE)
- CVEs where the vulnerable code path is not reachable in the
  application
- CVEs in packages where the severity rating overestimates the
  actual risk in the specific deployment context
- Withdrawn or disputed CVEs that remain in the database

False positives must be managed through scoped suppression entries
tied to a specific CVE identifier, not through suppression of an
entire package or ecosystem.

Every suppression entry requires a documented justification, an
owner, and a review date. A rising suppression count is a signal
that the severity threshold or scope needs recalibration, not that
suppression should expand.

---

## 8. Related Controls

| Control | Relationship |
|---|---|
| SEC-0101 — Secret Detection | Complementary — both operate pre-merge as blocking controls |
| SEC-0301 — Container Image Scanning | Extends dependency scanning to OS-level packages in the container base image |
| SEC-0401 — Image Signing and Verification | Downstream — ensures the artifact produced after a clean scan is the artifact deployed |

---

## 9. Compliance Mapping

| Standard | Reference | Notes |
|---|---|---|
| ISO 27001:2022 | A.8.8 — Management of technical vulnerabilities | Direct mapping — known CVEs in dependencies are technical vulnerabilities |
| ISO 27001:2022 | A.8.9 — Configuration management | Dependencies are part of application configuration and must be managed |
| OWASP Top 10 | A06:2021 — Vulnerable and Outdated Components | This control is the primary technical countermeasure for this category |
| OWASP CI/CD Top 10 | CICD-SEC-3 — Dependency chain abuse | Detects known-vulnerable packages introduced via the dependency chain |
| SLSA | Level 1–2 | Contributes to supply chain integrity by preventing known-vulnerable components from entering the build |
| NIS2 | Article 21(2)(e) | Applicable to organizations in sectors covered by NIS2 only |

---

## 10. Evidence Generated

When this control executes, it produces:

- Scan result indicating pass or fail
- List of findings with CVE identifier, severity, affected package,
  affected version, and fixed version (if available)
- Timestamp of scan execution
- Dependency manifest or lock file path scanned

This evidence demonstrates that the control was applied to a
specific pull request at a specific point in time against the
vulnerability database version available at that time. It does not
constitute proof of organizational compliance with any standard.

---

## 11. Operational Requirements

This control is technically effective only if the following
organizational processes exist:

1. **Triage process:** a defined owner who reviews findings,
   determines exploitability in the specific application context,
   and initiates remediation or exception approval within a
   defined SLA.

2. **Dependency update runbook:** documented steps for updating
   a dependency to a non-vulnerable version, testing compatibility,
   and verifying that the CVE no longer appears in scan output.

3. **Exception management:** a defined process for creating,
   approving, reviewing, and expiring suppression entries, including
   the acceptable justification categories defined in §5.

4. **Scheduled scan complement:** a process for detecting CVEs
   published after the last merge. Without this, the control only
   catches new vulnerabilities at the time a PR is opened.

5. **Metrics:** Mean Time to Detection (MTTD) and Mean Time to
   Update (MTTU) must be tracked per severity tier. A rising MTTU
   for HIGH and CRITICAL findings indicates a process failure.

Without these processes, this control provides detection without
response — operationally equivalent to no control at all.
