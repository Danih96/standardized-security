# SEC-0201 — Dependency Scanning: Implementation

## Status
Active

## Last Updated
2026-06

---

This document describes the current implementation of
[SEC-0201 — Dependency Scanning](spec.md).

Trivy is the tool used to satisfy this control.
It is the current implementation, not the definition of the control.
If Trivy is replaced by another tool, this document changes.
The spec does not.

---

## 1. Tool Selection

**Selected tool:** [Trivy](https://github.com/aquasecurity/trivy)
(Aqua Security)

### Why Trivy over alternatives

| Criterion | Trivy | Grype | Snyk | OWASP Dep-Check |
|---|---|---|---|---|
| Ecosystem coverage | Very broad | Broad | Broad | Java-focused |
| SARIF output | Native | Native | Native | Via plugin |
| Official GitHub Action | Yes | Community | Yes | Community |
| Requires credentials | No | No | Yes (SaaS token) | No |
| Lock file support | Yes | Yes | Yes | Partial |
| Also covers containers | Yes | No | Yes | No |
| Active maintenance | Yes | Yes | Yes | Reduced |

The deciding factors were:

**No credentials required.** Trivy downloads its vulnerability
database directly from public sources at scan time. Snyk requires
a SaaS account and token, which introduces a credential dependency
into the reusable workflow and a third-party service dependency
into the CI pipeline.

**Same tool for Milestone 3.** Trivy scans both application
dependencies (filesystem mode) and container images (image mode).
Adopting Trivy here means Milestone 3 introduces no new tooling.
Reducing tool sprawl across the platform reduces maintenance burden
and makes the security pipeline easier to reason about.

**Broad ecosystem coverage.** Trivy supports npm, Yarn, pip,
Poetry, Go modules, Maven, Gradle, NuGet, Composer, Cargo, Bundler,
and others. A single workflow handles any language stack a consuming
repository uses.

Grype is a strong alternative and was seriously evaluated. Its
SBOM integration is excellent and will be relevant for Milestone 4.
It was not selected here solely because Trivy's container scanning
capability makes it the better choice as a platform-wide tool.

---

## 2. How Trivy Works

### Ecosystem detection

Trivy scans the repository filesystem for dependency manifest files
and lock files. It identifies the ecosystem from the filename:

| File | Ecosystem |
|---|---|
| `package-lock.json`, `yarn.lock` | npm / Node.js |
| `poetry.lock`, `requirements.txt`, `Pipfile.lock` | Python |
| `go.sum` | Go |
| `pom.xml`, `build.gradle` | Java (Maven / Gradle) |
| `Gemfile.lock` | Ruby |
| `Cargo.lock` | Rust |
| `composer.lock` | PHP |
| `packages.lock.json`, `*.csproj` | .NET |

**Lock files take precedence.** When a lock file is present, Trivy
parses the full transitive dependency graph from it. When only a
manifest file is present (e.g., `requirements.txt` without
`poetry.lock`), Trivy reports direct dependencies only and transitive
coverage is incomplete.

### Vulnerability database

Trivy checks each detected package version against multiple
vulnerability databases:

- **OSV** (Open Source Vulnerabilities) — the primary source,
  aggregates advisories from GitHub, PyPI, npm, and others
- **GitHub Advisory Database (GHSA)** — ecosystem-specific
  advisories from GitHub's security team
- **NVD** (National Vulnerability Database) — CVSS scores
  and CVE metadata

Trivy downloads and caches its database at scan time. The database
is refreshed on each run unless a local cache is present and within
the cache TTL. Stale cache is a source of missed CVEs — see §5.

### Severity scoring

Trivy reports severity using CVSS scores from the NVD, supplemented
by ecosystem-specific ratings where available. Severity levels are
CRITICAL, HIGH, MEDIUM, LOW, and UNKNOWN.

The severity of a CVE as reported by Trivy reflects the NVD
assessment. Ecosystem-specific advisories (e.g., GitHub Security
Advisories) may assign different severity ratings for the same CVE.
Where ratings differ, Trivy's output reflects the NVD rating unless
overridden by a more specific source.

### No reachability analysis

Trivy does not analyze whether the vulnerable code path in a
dependency is reachable from the application. A CVE in a dependency
is reported regardless of whether the vulnerable function is called.
Reachability analysis is an emerging capability in the SCA space
and is not currently available in Trivy. See §7.

---

## 3. Configuration Decisions

### Scan mode: filesystem

The workflow runs Trivy in filesystem mode (`trivy fs`), scanning
the repository for dependency manifests and lock files. This is
distinct from image mode (`trivy image`), which scans a built
container image. Image mode is used in Milestone 3 (SEC-0301).

### Severity threshold: HIGH and CRITICAL block by default

The workflow fails when Trivy reports findings at HIGH or CRITICAL
severity. MEDIUM and LOW findings are included in the SARIF output
but do not cause a failure by default.

This threshold is configurable via the `severity-threshold` input.
The default is always the most restrictive option available to
the workflow.

### Scanners: vulnerabilities only

Trivy can scan for vulnerabilities, misconfigurations, secrets,
and license issues. This workflow enables the vulnerability scanner
only (`--scanners vuln`). Other scanner types are out of scope for
this control.

### Output format: SARIF

Trivy produces output in SARIF format. The workflow uploads this
file as a workflow artifact named `dependency-scanning-results`.

### Exit code behavior

Trivy exits with code 1 when findings meet or exceed the configured
severity threshold. The workflow respects this exit code to implement
fail-closed behavior. See the `fail-on-findings` input in the
workflow for the mechanism available to consumers during rollout.

---

## 4. Exception Management

Exceptions are declared in a `.trivyignore` file at the root of
the repository being scanned.

### Required fields for every suppression entry

```
# CVE-2024-12345
# Justification: vulnerable function not reachable — application does not use X feature
# Owner: platform-team
# Review date: 2026-12
CVE-2024-12345
```

Trivy reads CVE IDs from `.trivyignore` and suppresses matching
findings. The fields above (`Justification`, `Owner`,
`Review date`) are TOML comments — Trivy does not enforce them,
so the process must.

### Scope restriction

Suppression entries must be scoped to a specific CVE ID.

**Not permitted:**
```
# Suppresses all findings in a package — never acceptable
# (achieved by removing the package from scanning scope)
```

**Permitted:**
```
# CVE-2024-12345
# Justification: affects only the XML parser path; this app does not parse XML
# Owner: backend-team
# Review date: 2026-09
CVE-2024-12345
```

Package-level or ecosystem-level suppression is not permitted.
It creates a permanent blind spot for all future CVEs in the
suppressed scope.

---

## 5. Known Limitations

The following limitations are specific to Trivy as the
implementation of SEC-0201. For limitations that apply to the
control itself regardless of tooling, see [spec.md §6](spec.md).

- **Stale database cache.** If a CI runner reuses a Trivy cache
  that exceeds the database TTL, CVEs published since the last
  cache refresh will not be detected. The workflow must not
  configure persistent Trivy cache across runs without also
  enforcing cache expiry.

- **Incomplete transitive coverage without lock files.** If a
  consuming repository does not commit lock files, Trivy reports
  direct dependencies only. Transitive CVEs — which represent the
  majority of real-world findings — will be missed silently.

- **CVSS score divergence.** The NVD CVSS score for a CVE may
  differ from the score assigned by the affected ecosystem's
  advisory database. A CVE rated HIGH by NVD may be rated MEDIUM
  by npm. Trivy uses NVD ratings by default, which can result
  in both over-reporting and under-reporting relative to
  ecosystem-specific guidance.

- **No scheduled scan.** This workflow runs pre-merge only. CVEs
  published after a dependency is merged are not detected until
  the next PR that touches the dependency file triggers a rescan.
  A scheduled scan workflow is required for continuous coverage
  and is not included in this milestone.

- **SARIF artifact may contain sensitive package metadata.**
  The SARIF output includes package names, versions, and CVE
  details. In repositories where the dependency graph is considered
  sensitive, artifact retention must be configured accordingly.

---

## 6. Validation

Two scenarios must pass to confirm this implementation is working.
Full procedures are in [tests/README.md](tests/README.md).

| Scenario | Expected result |
|---|---|
| Repository with no vulnerable dependencies | Workflow passes, SARIF artifact produced with zero findings at HIGH or CRITICAL |
| Repository with a pinned vulnerable dependency | Workflow fails, finding reported in SARIF artifact |

---

## 7. Future Improvements

**Scheduled scan**
A scheduled workflow running `trivy fs` on the default branch on a
daily cadence would detect CVEs published after the last pre-merge
scan. This is the most significant gap in the current implementation
and the first improvement to implement after Milestone 2 is
validated.

**SBOM generation**
Trivy can generate an SBOM in CycloneDX or SPDX format alongside
its vulnerability scan. Enabling SBOM output during the dependency
scan run adds no additional tool and is the foundation for
Milestone 4. The SBOM produced here can be signed in Milestone 5.

**Reachability analysis**
Emerging SCA tooling (including experimental Trivy features and
tools like Socket) can determine whether a vulnerable code path in
a dependency is actually called by the application. When this
capability matures in Trivy or an adjacent tool, it should be
evaluated as a way to reduce false positive rates for findings where
the vulnerable code is unreachable.

**Severity threshold calibration**
After initial rollout, the distribution of findings across severity
levels should be reviewed. If MEDIUM findings are consistently
actionable, the threshold should be lowered. If HIGH findings are
consistently false positives, the ruleset or suppression process
needs calibration — the threshold should not be raised.
