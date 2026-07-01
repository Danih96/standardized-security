# SEC-0401 — SBOM Generation: Implementation

## Status
Active

## Last Updated
2026-06

---

This document describes the current implementation of
[SEC-0401 — SBOM Generation](spec.md).

Trivy is the tool used to satisfy this control.
It is the current implementation, not the definition of the control.
If Trivy is replaced by another tool, this document changes.
The spec does not.

---

## 1. Tool Selection

**Selected tool:** [Trivy](https://github.com/aquasecurity/trivy)
(Aqua Security) — CycloneDX output mode

Trivy was already selected as the platform tool in SEC-0201 and
SEC-0301. SBOM generation requires no new tooling — the same Trivy
image inspection that produces SARIF for SEC-0301 can produce a
CycloneDX SBOM by changing the output format flag.

### Why CycloneDX over SPDX

| Criterion | CycloneDX | SPDX |
|---|---|---|
| Primary focus | Security and supply chain | License compliance |
| VEX support | Native (CycloneDX VEX) | Via external document |
| Tooling ecosystem | Dependency-Track, Grype, OSV | FOSSA, FOSSology, compliance tools |
| NTIA minimum elements | All seven satisfied | All seven satisfied |
| GitHub native support | Yes | Yes |
| Trivy support | Native, v1.6 | Native |

CycloneDX is selected because the platform's focus is security,
not license compliance. VEX support is the deciding factor —
CycloneDX VEX allows publishing exploitability statements alongside
the SBOM, which is the foundation for the exception management
evolution planned beyond Milestone 5.

SPDX output can be added as an additional step if compliance
tooling requires it. Trivy supports both formats from the same
scan run.

---

## 2. How Trivy Generates the SBOM

### Same inspection, different output

Trivy inspects the container image identically for both SEC-0301
and SEC-0401. It decompresses image layers, reads OS package
databases and application manifests, and builds an internal
component model. The difference is the output format:

```
SEC-0301:  trivy image myapp:latest --format sarif      → findings only
SEC-0401:  trivy image myapp:latest --format cyclonedx  → full inventory
```

SARIF contains only what Trivy considers a violation (CVEs at or
above the threshold). CycloneDX contains every component Trivy
detected, regardless of vulnerability status.

### What appears in the SBOM

Every component Trivy can identify is included:

- OS packages from `/var/lib/dpkg/status` (Debian/Ubuntu),
  `/lib/apk/db/installed` (Alpine), or `/var/lib/rpm/Packages`
  (RHEL)
- Application dependencies from manifests and lock files embedded
  in the image (`package-lock.json`, `poetry.lock`, `go.sum`, etc.)
- The image itself as the top-level component, identified by digest

Each component entry contains:
- `name` and `version`
- `purl` (Package URL) — a standardized cross-ecosystem identifier
- `type` — `library`, `operating-system`, or `container`
- License information where available from the package metadata

### What does not appear in the SBOM

- Components that Trivy cannot detect: dynamically loaded plugins,
  packages installed at runtime outside the image build, obfuscated
  or vendored dependencies without a recognizable manifest
- Builder-stage packages absent from the final image (same
  multi-stage build behavior as SEC-0301)

---

## 3. Configuration Decisions

### Output format: CycloneDX JSON

The workflow produces a CycloneDX v1.6 JSON file. This format
satisfies all seven NTIA minimum elements and is accepted by the
widest range of security tooling.

The output file is named `sbom.cdx.json` by convention.
The `.cdx.json` extension is the standard suffix for CycloneDX
JSON files and is recognized by most SBOM tooling without
additional configuration.

### Image reference: consumer-provided

The `image-ref` input follows the same design as SEC-0301.
The consuming pipeline pushes the image to a registry before
calling this workflow. The SBOM is generated from the same
image reference.

Consumers should pass the same `image-ref` to both SEC-0301 and
SEC-0401. Using different references for scan and SBOM generation
risks producing a SBOM that does not match the scanned image.

### No exit-code on findings

Unlike SEC-0201 and SEC-0301, the workflow does not set an
exit code based on component content. There are no findings —
every component is recorded regardless of vulnerability status.
The workflow fails only if the SBOM cannot be produced.

### Artifact: sbom-results

The SBOM is uploaded as a workflow artifact named `sbom-results`
containing `sbom.cdx.json`. Retention is set to 30 days — longer
than the 7-day retention used for SARIF files, because the SBOM
may need to be queried if a new CVE is published weeks after the
build.

---

## 4. Exception Management

There is no exception management for SBOM generation. Every
detected component is included in the SBOM without filtering.

Suppressing a component from the SBOM would defeat its purpose:
a SBOM that omits components is not an accurate inventory. If a
component should not be in the artifact, it should be removed
from the Dockerfile or the dependency manifest — not hidden from
the inventory.

---

## 5. Known Limitations

- **No runtime components.** Components loaded dynamically at
  runtime — plugins fetched from a remote source, JARs loaded
  via classpath scanning, Python packages installed by application
  code — do not appear in the SBOM. The SBOM reflects build-time
  composition only.

- **License accuracy.** License fields are populated from package
  metadata. Packages with missing, ambiguous, or incorrect license
  declarations in their metadata will have inaccurate or empty
  license fields in the SBOM. License review processes must account
  for this.

- **Short-term artifact storage.** The 30-day CI artifact retention
  is insufficient for long-term compliance or audit requirements.
  Organizations requiring SBOM retention beyond 30 days must store
  the SBOM in an external artifact store or attach it to the image
  in the registry. SEC-0402 (Image Signing) addresses the registry
  attachment path via OCI attestations.

- **No VEX.** The SBOM records what is present but not whether
  each component's known vulnerabilities are exploitable in this
  specific deployment. VEX (Vulnerability Exploitability eXchange)
  documents extend the SBOM with exploitability statements and are
  not generated by this control. This is a planned future
  improvement.

- **Single format output.** The workflow produces CycloneDX only.
  Consumers requiring SPDX for license compliance tooling must
  add a conversion step in their pipeline or request a platform
  extension.

---

## 6. Validation

Two scenarios must pass to confirm this implementation is working.
Full procedures are in [tests/README.md](tests/README.md).

| Scenario | Expected result |
|---|---|
| SBOM generated from a valid image | Workflow passes, `sbom-results` artifact produced, `sbom.cdx.json` is valid CycloneDX JSON containing at least one component |
| SBOM generated from an image with a known package | The known package appears in `components[]` with correct `purl` and `version` |

---

## 7. Future Improvements

**VEX generation**
A VEX document attached to the SBOM allows the organization to
formally declare that a CVE present in a dependency is not
exploitable in a specific deployment. This replaces `.trivyignore`
suppression entries with a structured, auditable, portable format
that any SBOM-aware tool can consume. CycloneDX VEX is the target
format; Trivy does not generate VEX natively but the format is
well-specified and can be produced by separate tooling.

**SPDX output**
A second workflow step generating `sbom.spdx.json` alongside the
CycloneDX output would serve consumers with license compliance
requirements. No new tooling is required — Trivy supports
`--format spdx-json` from the same image scan.

**Dependency-Track integration**
[Dependency-Track](https://dependencytrack.org/) is an open-source
platform that ingests CycloneDX SBOMs, continuously monitors them
against CVE feeds, and alerts when new vulnerabilities affect
recorded components. Uploading the SBOM to Dependency-Track as a
post-generation step would provide continuous CVE monitoring without
requiring a re-scan — directly solving the Log4Shell scenario.

**OCI attestation storage**
Storing the SBOM as an OCI artifact attached to the image in the
registry (using `cosign attach sbom`) makes the SBOM co-located
with the image it describes and survives beyond CI artifact
retention windows. This is the storage model used in SEC-0402.
