# Roadmap

## Vision

`standardized-security` will provide a complete set of reusable,
control-driven security checks that any application repository can
adopt in a single workflow call. Each control starts from a threat,
is defined independently of its tooling, and fails closed by default.
The platform grows one validated control at a time.

---

## Completed: Milestone 1 — Secret Detection

| Artifact | Status |
|---|---|
| `controls/SEC-0101-secret-detection/spec.md` | Done |
| `controls/SEC-0101-secret-detection/implementation.md` | Done |
| `controls/SEC-0101-secret-detection/tests/README.md` | Done |
| `workflows/secret-detection.yml` | Done |

---

## Completed: Milestone 2 — Dependency Scanning

| Artifact | Status |
|---|---|
| `controls/SEC-0201-dependency-scanning/spec.md` | Done |
| `controls/SEC-0201-dependency-scanning/implementation.md` | Done |
| `controls/SEC-0201-dependency-scanning/tests/README.md` | Done |
| `workflows/dependency-scanning.yml` | Done |

---

## Completed: Milestone 3 — Container Image Scanning

| Artifact | Status |
|---|---|
| `controls/SEC-0301-container-image-scanning/spec.md` | Done |
| `controls/SEC-0301-container-image-scanning/implementation.md` | Done |
| `controls/SEC-0301-container-image-scanning/tests/README.md` | Done |
| `workflows/container-scanning.yml` | Done |

---

## Completed: Milestone 4 — SBOM Generation

| Artifact | Status |
|---|---|
| `controls/SEC-0401-sbom-generation/spec.md` | Done |
| `controls/SEC-0401-sbom-generation/implementation.md` | Done |
| `controls/SEC-0401-sbom-generation/tests/README.md` | Done |
| `workflows/sbom-generation.yml` | Done |

---

## Current Milestone: Milestone 5 — Image Signing and Verification

| Artifact | Status |
|---|---|
| `controls/SEC-0402-image-signing/spec.md` | Done |
| `controls/SEC-0402-image-signing/implementation.md` | Done |
| `controls/SEC-0402-image-signing/tests/README.md` | Done |
| `workflows/image-signing.yml` | Done |

**Done means:** the workflow signs a real image, the signature is
verifiable with `cosign verify` using the correct identity regexp,
and the verification step is wired into `standardized-deployment`
as a blocking gate before any deployment.

**Milestone 3 — Container Image Scanning (SEC-0301)**
Detect known vulnerabilities in built container images before deployment.

**Milestone 4 — SBOM Generation**
Produce a Software Bill of Materials for every build, covering both
application dependencies and the base container image.

**Milestone 5 — Image Signing and Verification**
Sign container images at build time and verify signatures at deploy
time, using `standardized-deployment` as the verification point.

**Beyond**
Policy as Code, IaC Scanning, Compliance Automation.

---

No milestone begins until the previous one is validated in a real
application repository.
