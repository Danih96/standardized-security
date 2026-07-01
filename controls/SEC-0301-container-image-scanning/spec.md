# SEC-0301 — Container Image Scanning

## Status
Active

## Last Updated
2026-06

---

## 1. Threat

A container image built from a vulnerable base image or containing
OS-level packages with known CVEs can be exploited after deployment,
enabling an attacker to compromise the container, escape to the host,
or move laterally within the cluster.

**Likelihood without this control:** High
Base images are updated independently of application release cycles.
A base image pinned at build time accumulates CVEs continuously.
OS-level package vulnerabilities — in components like OpenSSL, curl,
or the C library — are routinely discovered and are not visible to
application-layer dependency scanners.

**Impact:** High
OS-level CVEs frequently enable privilege escalation within the
container or container escape to the host. CVEs in network-facing
packages (OpenSSL, libcurl) can be remotely exploitable. Impact
scope often exceeds that of application-level dependency CVEs
because OS packages run with broader privileges and access.

**Relationship to threat model:**
This control directly mitigates
[T-CICD-006](../../threat-models/infrastructure/ci-cd-pipeline.md).

---

## 2. Assets Protected

- Container images in the artifact registry
- The production runtime environment where containers are deployed
- Data processed by the deployed application
- Other workloads co-located on the same host or cluster node,
  in the event of a container escape

---

## 3. Security Principle

**Shift Left** — The scan runs against the built image before it is
pushed to the production registry or deployed. A vulnerable image is
rejected at the point of production, not discovered post-deployment.

**Defense in Depth** — This control complements SEC-0201
(Dependency Scanning) but is not a replacement for it. The two
controls operate on different artifacts at different stages:

| Control | Artifact scanned | Stage | What it covers |
|---|---|---|---|
| SEC-0201 | Source manifests and lock files | Pre-merge | Application dependencies |
| SEC-0301 | Built container image | Post-build, pre-deploy | OS packages, base image, all layers |

SEC-0301 is broader in scope — it sees everything in the image,
including packages installed by the Dockerfile, the base image's
OS packages, and any application dependencies installed into the
image. However, it runs later in the pipeline and cannot block
a merge the way SEC-0201 can.

Both controls are required. SEC-0201 provides early detection;
SEC-0301 provides complete coverage of the final artifact.

---

## 4. Enforcement Point

**Primary:** Post-build, pre-deploy

The control runs after the container image is built and before
it is pushed to the production registry or triggered for deployment.
A failing scan blocks the image from progressing further in the
pipeline.

This enforcement point ensures that:
- The artifact being scanned is the exact artifact that would be
  deployed — not an approximation from source files
- OS-level packages installed by the Dockerfile are included
- The base image version in use is verified, not assumed

**Why not pre-merge?**
Building a container image on every pull request is possible but
expensive. Pre-merge scans using SEC-0201 catch application
dependency CVEs earlier and at lower cost. Container image scanning
is deferred to post-build to scan the final artifact without
requiring a full image build on every PR.

**Complementary (not in scope for this milestone):**
- Continuous registry scanning — detects CVEs published after the
  image was pushed, without a new build
- Admission control — blocks deployment of non-compliant images
  at the Kubernetes scheduler level

---

## 5. Failure Mode

**Default: Fail Closed on High and Critical severity**

If the image scan finds a vulnerability at or above the configured
severity threshold, the pipeline fails and the image is not pushed
to the production registry. The default threshold is HIGH, meaning
both HIGH and CRITICAL severity CVEs are blocking.

If the scanning tool itself is unavailable or misconfigured,
the pipeline fails. A scan that does not run provides no protection
and must not be treated as a passing scan.

**Exceptions must be:**
- Scoped to a specific CVE identifier, never to a package, layer,
  or base image
- Documented with a justification and an owner
- Time-limited with a defined review date
- Approved through a defined exception process

Acceptable justifications for exceptions:
- The vulnerable package is present in the image but the vulnerable
  binary is not executed in the running container
- No fix is available in the base image and the risk is accepted
  pending a fixed base image release
- The CVE affects a development tool present in a builder stage
  that is excluded from the final image

---

## 6. Limitations

- **Known vulnerabilities only:** zero-day vulnerabilities and
  undisclosed CVEs are not detectable.

- **No runtime analysis:** the control scans the image filesystem.
  It cannot determine whether a vulnerable binary is actually
  executed at runtime or whether it is reachable from the
  application entry point.

- **Base image CVE lag:** CVE fixes for OS packages depend on the
  base image maintainer publishing an updated image. Between CVE
  publication and a fixed base image being available, the only
  options are exception approval or base image replacement.

- **Layer visibility:** scanners inspect all layers of the image.
  A package installed in an early layer and deleted in a later
  layer may or may not be detectable, depending on how the deletion
  was performed and which layer representation the scanner uses.

- **Multi-stage builds:** packages present only in builder stages
  and absent from the final image must not be reported as findings.
  Scanners that operate on the final image layer only handle this
  correctly; scanners that inspect all layers including intermediate
  ones may report false positives from builder stages.

- **Pre-merge coverage gap:** this control does not run on pull
  requests by default. A dependency CVE that was not caught by
  SEC-0201 — for example, a CVE in an OS package not covered by
  application-layer scanning — is not detected until the image is
  built.

---

## 7. False Positives

Common sources of false positives:

- CVEs in packages present in builder stages but absent from
  the final runtime image
- CVEs in packages that are installed but never executed
  (e.g., diagnostic tools added to the image for operational use)
- CVEs in packages where the vulnerability is specific to a
  configuration or usage pattern not present in this deployment
- CVEs with no available fix where the base image maintainer
  has assessed and accepted the risk

False positives must be managed through scoped suppression entries
tied to a specific CVE identifier. Layer-level, package-level, or
base image-level suppression is not permitted.

---

## 8. Related Controls

| Control | Relationship |
|---|---|
| SEC-0201 — Dependency Scanning | Complementary — SEC-0201 covers application dependencies pre-merge; SEC-0301 covers the full image post-build |
| SEC-0401 — Image Signing and Verification | Downstream — SEC-0301 produces a clean image; SEC-0401 signs it and verifies the signature at deploy time |
| SEC-0101 — Secret Detection | Complementary — secrets should not appear in image layers; SEC-0101 catches them pre-merge |

---

## 9. Compliance Mapping

| Standard | Reference | Notes |
|---|---|---|
| ISO 27001:2022 | A.8.8 — Management of technical vulnerabilities | OS-level CVEs in container images are technical vulnerabilities requiring management |
| ISO 27001:2022 | A.12.6 — Technical vulnerability management | Continuous vulnerability management for deployed software |
| OWASP Top 10 | A06:2021 — Vulnerable and Outdated Components | Extends coverage to OS-layer components not visible to application-level scanners |
| OWASP CI/CD Top 10 | CICD-SEC-3 — Dependency chain abuse | Base image is a form of dependency; its vulnerabilities enter the supply chain |
| SLSA | Level 1–2 | Contributes to artifact integrity by preventing known-vulnerable images from reaching the registry |
| CIS Docker Benchmark | 4.1 — Use trusted base images | Scanning verifies that the base image in use does not contain known critical vulnerabilities |

---

## 10. Evidence Generated

When this control executes, it produces:

- Scan result indicating pass or fail
- List of findings with CVE identifier, severity, affected package,
  affected version, fixed version (if available), and image layer
- Timestamp of scan execution
- Image reference (name, tag, digest) scanned

The image digest in the evidence links the scan result to the
exact image artifact. Tag-based references are insufficient for
evidence purposes because tags are mutable.

---

## 11. Operational Requirements

1. **Base image update process:** a defined process for updating
   the base image when a CVE fix is published, including testing
   and re-scanning before promotion to production.

2. **Triage process:** a defined owner who reviews findings,
   determines whether the vulnerable component is present in the
   final image and reachable at runtime, and initiates remediation
   or exception approval within a defined SLA.

3. **Exception management:** the same process defined for SEC-0201,
   applied to image-level CVEs.

4. **Continuous registry scanning:** a process for detecting CVEs
   published after an image is pushed. Without this, an image that
   passes the post-build scan may accumulate CVEs in the registry
   before it is deployed or replaced.

5. **Metrics:** Mean Time to Detection (MTTD) per severity tier,
   and Mean Time to Remediation (MTTR) distinguishing between
   application-layer CVEs (remediate by updating a dependency)
   and OS-layer CVEs (remediate by updating the base image).
