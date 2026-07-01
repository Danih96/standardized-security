# SEC-0301 — Container Image Scanning: Implementation

## Status
Active

## Last Updated
2026-06

---

This document describes the current implementation of
[SEC-0301 — Container Image Scanning](spec.md).

Trivy is the tool used to satisfy this control.
It is the current implementation, not the definition of the control.
If Trivy is replaced by another tool, this document changes.
The spec does not.

---

## 1. Tool Selection

**Selected tool:** [Trivy](https://github.com/aquasecurity/trivy)
(Aqua Security) — image mode (`trivy image`)

Trivy was already selected as the platform tool in SEC-0201.
The decision to use it here is a direct consequence of that choice:
the same tool, a different scan mode. No new tooling is introduced.

### Why the same tool rather than a dedicated image scanner

| Criterion | Trivy (image mode) | Grype | Snyk Container | Clair |
|---|---|---|---|---|
| OS package databases | USN, Alpine SecDB, Debian, RHEL OVAL | Same | Same | Same |
| SARIF output | Native | Native | Native | No |
| Official GitHub Action | Yes (same action) | Community | Yes | No |
| Requires credentials | No | No | Yes | Self-hosted |
| Already on platform | Yes (SEC-0201) | No | No | No |

No tool switch means no new action to pin, no new database to cache,
no new failure mode to document, and no new learning curve for
platform consumers. Trivy's image mode uses the same
`aquasecurity/trivy-action` as SEC-0201, with `scan-type` changed
from `fs` to `image`.

---

## 2. How Trivy Works in Image Mode

### Layer inspection

A container image is a stack of compressed tar archives, one per
Dockerfile instruction. Trivy decompresses and merges these layers
into a unified filesystem view, then inspects it for:

- OS package manager databases (`/var/lib/dpkg/status` for Debian/Ubuntu,
  `/lib/apk/db/installed` for Alpine, `/var/lib/rpm/Packages` for RHEL)
- Application dependency manifests and lock files embedded in the image

### Vulnerability databases — OS vs. application

This is the critical difference between `trivy fs` and `trivy image`.

Application dependencies are checked against OSV, GHSA, and NVD —
the same databases used in SEC-0201. OS packages require additional
distribution-specific databases:

| Distribution | Database | Why a separate database is needed |
|---|---|---|
| Ubuntu / Debian | Ubuntu Security Notices (USN) | Ubuntu backports security fixes to older versions; NVD scores reference upstream versions only |
| Alpine | Alpine SecDB | Alpine version strings differ from upstream; SecDB maps Alpine package versions to CVEs |
| RHEL / CentOS | Red Hat OVAL | Red Hat backports extensively; OVAL maps RHEL package versions to CVE status |
| Debian | Debian Security Tracker | Same backport rationale as Ubuntu |

A CVE in `libssl` fixed upstream in OpenSSL 3.0.8 may be fixed in
Ubuntu via a backport to `libssl3 3.0.2-0ubuntu1.10`. NVD reports
`OpenSSL < 3.0.8` as vulnerable. Ubuntu SecDB reports
`libssl3 3.0.2-0ubuntu1.10` as fixed. Without consulting USN,
Trivy would report a false positive. With USN, it correctly marks
the backported version as not affected.

### Multi-stage build handling

Trivy inspects the final image only — the layers that result from
the last `FROM` instruction. Packages present exclusively in builder
stages do not appear in the final image filesystem and are not
reported. This is the correct behavior for production security
assessment.

### Image access

Trivy accesses the image in one of three ways:

1. **Registry pull** — Trivy pulls the image from a container
   registry using the provided reference. This is the primary
   mode used by the reusable workflow.
2. **Local Docker daemon** — Trivy reads the image from the Docker
   daemon on the runner if the image was built in the same job.
3. **Tarball** — Trivy reads an image exported via `docker save`.

The reusable workflow uses registry pull. The consuming pipeline
must push the image to a registry before calling this workflow.

---

## 3. Configuration Decisions

### Scan mode: image

The workflow runs Trivy with `scan-type: image`, providing the
image reference via the `image-ref` input. This is distinct from
`scan-type: fs` used in SEC-0201.

### Image reference: consumer-provided

The image reference (`image-ref`) is a required workflow input.
The consuming pipeline is responsible for providing a reference
that is accessible from the runner — typically a registry image
pushed immediately before the scan job runs.

Consumers should pass the image reference with a digest rather
than a tag alone when possible:

```
ghcr.io/org/myapp:sha-a1b2c3d              ← tag only (acceptable)
ghcr.io/org/myapp@sha256:abc123...         ← digest (preferred)
ghcr.io/org/myapp:sha-a1b2c3d@sha256:...  ← tag + digest (best)
```

The SARIF artifact records the reference as provided. Consumers
using tag-only references accept that the evidence does not
cryptographically bind the scan result to the deployed artifact.

### Severity threshold: HIGH and CRITICAL block by default

Identical policy to SEC-0201. The default threshold is HIGH.
MEDIUM and LOW findings appear in the SARIF output but do not
cause a failure. The threshold is configurable via
`severity-threshold` input.

### Scanners: vulnerabilities only

Same as SEC-0201 — `--scanners vuln`. Secret scanning in images
is not in scope for this control. Misconfiguration scanning is
not in scope for this control.

### Exit code behavior

Same pattern as SEC-0201: `exit-code` is set to `1` when
`fail-on-findings` is true, and `0` when false. Tool errors
always fail the job regardless of `fail-on-findings`.

---

## 4. Exception Management

Exceptions follow the same pattern as SEC-0201, using a
`.trivyignore` file at the root of the consuming repository.

```
# CVE-2023-0286
# Justification: libssl3 present in image but TLS termination
#                handled by sidecar proxy — app does not use OpenSSL directly
# Owner: platform-team
# Review date: 2026-12
CVE-2023-0286
```

The scope restriction from SEC-0201 applies here as well:
suppression must be scoped to a specific CVE ID. Suppressing
all CVEs in a base image, a package, or a layer is not permitted.

**Note on base image CVEs with no available fix:**
When a CVE affects a base image package and no fixed version has
been published by the distribution, the acceptable exception
justification is: *"No fix available in [distro] as of [date].
Accepted pending availability of a fixed base image."* The review
date must be set short — 30 to 60 days — to force re-evaluation
when a fix is published.

---

## 5. Known Limitations

The following limitations are specific to Trivy in image mode.
For control-level limitations, see [spec.md §6](spec.md).

- **Registry authentication required for private images.**
  The workflow passes `GITHUB_TOKEN` for GitHub Container Registry
  (`ghcr.io`). Images in other registries require additional
  credential configuration by the consuming pipeline.

- **No runtime reachability.** Trivy reports packages present
  in the image filesystem. It cannot determine whether a vulnerable
  binary is executed at runtime or whether the vulnerable code
  path is reachable from the application entry point.

- **Deleted files in later layers.** A package installed in layer N
  and deleted in layer N+1 may still appear in the merged filesystem
  depending on how the deletion was performed. Files deleted via
  `RUN rm` may leave traces; files deleted via `.dockerignore` or
  `--mount=type=cache` do not appear at all.

- **No scheduled scan.** This workflow runs post-build on demand.
  CVEs published after the image is pushed to the registry are
  not detected until the next build triggers a rescan. Continuous
  registry scanning is required for ongoing coverage and is not
  included in this milestone.

- **Tag mutability risk.** If the consumer provides a tag-only
  reference and the tag is updated between the scan and the deploy,
  the deployed image may differ from the scanned image. Using
  digest-pinned references eliminates this risk.

- **SARIF artifact contains package metadata.** As with SEC-0201,
  the SARIF output may be treated as sensitive in contexts where
  the dependency graph is confidential. Retention is set to 7 days.

---

## 6. Validation

Two scenarios must pass to confirm this implementation is working.
Full procedures are in [tests/README.md](tests/README.md).

| Scenario | Expected result |
|---|---|
| Image built from a current, non-vulnerable base with no vulnerable packages | Workflow passes, SARIF artifact produced with zero HIGH or CRITICAL findings |
| Image built with a base image known to contain a HIGH or CRITICAL CVE | Workflow fails, finding reported in SARIF artifact |

---

## 7. Future Improvements

**SBOM generation alongside image scan**
Trivy can produce a CycloneDX or SPDX SBOM from the same image
scan run. Enabling this adds no additional tooling and produces
the artifact required by Milestone 4 (SBOM Generation). The SBOM
produced here covers both application dependencies and OS packages —
a more complete picture than the filesystem-only SBOM from SEC-0201.

**Continuous registry scanning**
A scheduled workflow running `trivy image` against tagged images
in the registry on a daily cadence would detect CVEs published
after the last build. This is the most significant operational
gap in the current implementation.

**Digest-pinned base images**
A Dockerfile linting step (e.g., using `hadolint`) can enforce
that `FROM` instructions use digest-pinned references rather than
mutable tags. This eliminates the tag mutability risk and ensures
that the base image used in a build is identical to the one that
was scanned and approved. This is a workflow hardening control,
not a scanning control, and is not in scope for SEC-0301.

**Admission control integration**
Kubernetes admission controllers (e.g., Kyverno, OPA/Gatekeeper)
can block deployment of images that do not have a valid, recent
scan result. This provides a runtime enforcement layer that
complements the build-time control defined here.
