# SEC-0101 — Secret Detection

## Status
Active

## Last Updated
2026-06

---

## 1. Threat

A developer may accidentally commit a secret — such as an API key,
database credential, or private key — to source code or git history,
exposing it to anyone with repository access and enabling an attacker
to gain unauthorized access to the systems or data protected by that
credential, with potential for lateral movement across connected systems.

**Likelihood without this control:** High
Secrets are frequently committed accidentally, under time pressure,
during debugging, or through misconfigured tooling. Git's distributed
nature makes every clone a permanent copy of the exposure.

**Impact:** High
A single leaked credential can provide direct access to production
databases, cloud infrastructure, CI/CD pipelines, or third-party
services. The blast radius almost always exceeds the apparent scope
of the secret itself.

---

## 2. Assets Protected

- Authentication credentials protecting application services
- Cloud provider access keys and service account credentials
- Database connection strings and credentials
- Private keys used for TLS, SSH, code signing, or JWT signing
- Symmetric encryption keys and HMAC secrets
- OAuth client secrets
- Webhook secrets
- Third-party API keys and access tokens

---

## 3. Security Principle

**Defense in Depth** — This control operates as one layer in a
broader secrets management program. It does not replace proper
secrets management practices (secrets managers, runtime injection,
least privilege). It acts as a safety net that catches secrets
before they enter shared infrastructure, compensating for the
inevitability of human error.

**Shift Left** — The control is applied as early as possible in
the SDLC, at the point where the cost of remediation is lowest
and the exposure is most limited.

---

## 4. Enforcement Point

**Primary:** Pre-merge (pull request CI pipeline)

The control runs as a blocking check on every pull request before
code is merged into a protected branch.

This enforcement point satisfies three requirements simultaneously:

- **Centralized:** runs in CI infrastructure controlled by the
  organization, cannot be bypassed by individual developers
- **Timely:** the secret has not yet entered the main branch,
  limiting the exposure perimeter
- **Actionable:** the developer has immediate context to remediate
  the finding within the same pull request

**Complementary (not in scope for this milestone):**
- Pre-commit hook on developer workstation (convenience layer,
  not an organizational control — can be bypassed with
  `git commit --no-verify`)
- Scheduled full history scan (detective control — identifies
  secrets committed before this control was adopted)

---

## 5. Failure Mode

**Default: Fail Closed**

If the secret detection scan finds a confirmed secret, the pipeline
fails and the merge is blocked. This is non-negotiable as a default.

If the secret detection tool itself is unavailable or misconfigured,
the pipeline fails. A scan that does not run provides no protection
and must not be treated as a passing scan.

**Exceptions must be:**
- Scoped to the specific finding, never to a file or directory
- Documented with a justification and an owner
- Time-limited with a defined review date
- Approved through a defined exception process

Fail-open behavior is never acceptable as a default. A period of
grace (notify without blocking) may be adopted during initial
rollout only, for a fixed and publicly communicated duration,
to allow ruleset calibration before enforcement begins.

---

## 6. Limitations

- **Pattern matching coverage:** the control detects secrets with
  known formats (cloud provider keys, SaaS tokens, private key
  headers). Generic secrets without recognizable patterns — such
  as internally generated tokens or simple passwords — may not
  be detected unless custom rules are defined.

- **No historical coverage:** this control operates on new code
  only. Secrets committed before adoption are not detected.
  A separate scheduled scan control is required for historical
  coverage.

- **No verification:** the control does not verify whether a
  detected secret is currently valid. A rotated secret may still
  trigger a finding. A valid secret with an unusual format may
  not trigger a finding.

- **False positives are expected:** high-entropy strings, hashes,
  test vectors, and encoded data may trigger findings. Alert
  fatigue from unmanaged false positives degrades the
  effectiveness of this control over time.

- **Remediation is not detection:** detecting a secret does not
  automatically remediate it. A confirmed finding requires
  immediate rotation of the credential, investigation of the
  exposure window, and review of access logs for the protected
  resource.

---

## 7. False Positives

Common sources of false positives:

- SHA-256 and other cryptographic hashes
- Base64-encoded non-sensitive data
- Example values in documentation or tests
- High-entropy strings in test vectors
- Placeholder values that match secret patterns

False positives must be managed through scoped allowlist entries,
not through broad suppression of files, directories, or rule
categories. Every allowlist entry requires a documented
justification, an owner, and a review date.

Systematic false positive rates must be monitored. A rising false
positive rate is a signal that the ruleset requires calibration,
not that suppression should be expanded.

---

## 8. Related Controls

| Control | Relationship |
|---|---|
| SEC-0201 — Dependency Scanning | Complementary — both operate pre-merge as blocking controls |
| SEC-0301 — Container Image Scanning | Complementary — extends secret detection to built artifacts |
| SEC-XXXX — Secrets Manager Integration | Upstream — reduces the probability that secrets exist in code in the first place |
| SEC-XXXX — Scheduled History Scan | Complementary detective control — covers historical exposure |

---

## 9. Compliance Mapping

| Standard | Reference | Notes |
|---|---|---|
| ISO 27001:2022 | A.5.17 — Authentication information | Secrets in source code represent improper storage of authentication information |
| ISO 27001:2022 | A.8.12 — Data leakage prevention | Committed secrets are an unauthorized disclosure of sensitive information |
| ISO 27001:2022 | A.8.8 — Management of technical vulnerabilities | An exposed credential is an active technical vulnerability |
| ISO 27001:2022 | A.8.9 — Configuration management | Credentials are part of system configuration and must be managed accordingly |
| OWASP CI/CD Top 10 | CICD-SEC-6 — Insufficient Credential Hygiene | Direct mapping — hardcoded credentials in source code |
| OWASP CI/CD Top 10 | CICD-SEC-1 — Insufficient Flow Control | Pre-merge blocking enforces flow control over sensitive material |
| NIS2 | Article 21(2)(e) | Applicable to organizations in sectors covered by NIS2 only |
| IEC 62443 | 4-1 SR 5.2 | Applicable to OT/ICS projects only |
| SLSA | Level 1–2 | Contributes to supply chain integrity by preventing credential-based pipeline compromise |

---

## 10. Evidence Generated

When this control executes, it produces:

- Scan result indicating pass or fail
- List of findings with file path, line number, rule matched,
  and secret type (not the secret value itself)
- Timestamp of scan execution
- Git commit range scanned

This evidence demonstrates that the control was applied to a
specific pull request at a specific point in time. It does not
constitute proof of organizational compliance with any standard.
Compliance requires consistent application over time, a documented
exception process, and integration with an incident response
procedure.

---

## 11. Operational Requirements

This control is technically effective only if the following
organizational processes exist:

1. **Triage process:** a defined owner who reviews findings,
   distinguishes confirmed secrets from false positives, and
   initiates the appropriate response within a defined SLA.

2. **Rotation runbook:** documented steps for rotating each
   category of secret, including which teams must be notified
   and how to verify that rotation was successful.

3. **Incident response integration:** confirmed secret leaks
   must enter the incident response process immediately.
   Rotation must precede investigation.

4. **Exception management:** a defined process for creating,
   approving, reviewing, and expiring allowlist entries.

5. **Metrics:** Mean Time to Detection (MTTD) and Mean Time
   to Rotation (MTTR) must be tracked. A rising MTTR indicates
   a process failure, not a tool failure.

Without these processes, this control provides detection
without response — which is operationally equivalent to
no control at all.
