# SEC-0401 — SBOM Generation

## Status
Active

## Last Updated
2026-06

---

## 1. Threat

Without an accurate, up-to-date inventory of all components in a
deployed artifact, an organization cannot rapidly determine whether
it is affected by a newly published vulnerability — forcing slow,
manual investigation at exactly the moment when speed matters most.

**Likelihood without this control:** Certain
Every software artifact contains dependencies. Without an explicit
inventory, the only way to assess exposure is to re-scan every
artifact or manually trace every dependency tree at incident time.
This is slow, error-prone, and does not scale across multiple
repositories and environments.

**Impact:** High (on response time, not directly on the attack)
The SBOM does not prevent any attack. Its absence increases the
time between CVE publication and organizational awareness of
exposure — extending the window in which a known-vulnerable
component may be exploited without the organization knowing it
is at risk.

The Log4Shell incident (CVE-2021-44228) is the canonical example.
Organizations with component inventories identified their exposure
in minutes. Organizations without them spent days or weeks in
manual triage across hundreds of repositories while the
vulnerability was actively exploited.

**Relationship to threat model:**
This control does not directly mitigate any threat in
[ci-cd-pipeline.md](../../threat-models/infrastructure/ci-cd-pipeline.md).
It is an enabling control — it produces the inventory that makes
other controls and processes faster and more reliable.

---

## 2. Assets Protected

This control does not protect assets directly. It enables the
protection of:

- All assets listed in SEC-0201 and SEC-0301, by accelerating
  exposure assessment when new CVEs are published
- Compliance records, by providing auditable component inventories
- The artifact integrity chain, by producing a signed inventory
  when combined with SEC-0402 (Image Signing and Verification)

---

## 3. Security Principle

**Transparency** — A SBOM makes the composition of every artifact
visible and auditable. It shifts the answer to "what do we have?"
from a manual investigation to a query against a structured artifact.

**Shift Left** — The SBOM is generated at build time, when the
exact composition of the artifact is known and fixed. A SBOM
generated post-deployment is an approximation; a SBOM generated
at build time is authoritative.

---

## 4. Enforcement Point

**Primary:** Post-build, co-located with container image scanning

The SBOM is generated from the built container image immediately
after the image scan (SEC-0301). This produces an inventory of
the exact artifact that passed scanning and will be deployed.

Generating the SBOM from the image rather than from source
manifests ensures that:

- OS-level packages from the base image are included
- Packages installed via Dockerfile instructions are included
- The inventory reflects the final artifact, not an approximation
  from source files

**Output:** A CycloneDX JSON file attached to the build as a
persistent artifact, stored alongside the image in the registry
or artifact store, and signed in Milestone 5.

---

## 5. Failure Mode

**Fail if SBOM cannot be generated**

Unlike controls that fail on findings, SBOM generation has no
findings. The failure condition is simpler: if the SBOM cannot
be generated — because the tool is unavailable, the image is
inaccessible, or the output cannot be written — the pipeline
fails.

A build without a SBOM is a build without an inventory.
Deploying an artifact whose composition is not recorded is
not acceptable.

There is no `fail-on-findings` equivalent for this control.
The SBOM always passes if it is produced. What is done with
the SBOM — querying it, signing it, publishing it — is handled
by downstream processes and controls.

---

## 6. Limitations

- **Point-in-time inventory:** the SBOM reflects the composition
  of the artifact at build time. It does not update automatically
  when new CVEs are published. Querying a SBOM for new CVEs
  requires a separate process that correlates SBOM contents
  against a current vulnerability database.

- **Accuracy depends on the scanner:** the SBOM is only as
  complete as the tool that generates it. Components that Trivy
  cannot detect — dynamically loaded plugins, runtime-fetched
  dependencies, obfuscated packages — will not appear in the SBOM.

- **No enforcement value alone:** a SBOM that is generated but
  never queried provides no security value. The operational
  processes that use the SBOM — CVE triage, compliance reporting,
  license auditing — must exist for this control to have effect.

- **Format compatibility:** CycloneDX is the format used by this
  platform. Consumers requiring SPDX for compliance tooling must
  convert the output. Trivy supports both formats; the workflow
  can be extended with an additional step if SPDX output is needed.

- **Not a substitute for scanning:** a SBOM identifies what is
  present. It does not assess whether what is present is
  vulnerable. SEC-0201 and SEC-0301 remain the controls that
  block vulnerable components from reaching production.

---

## 7. Related Controls

| Control | Relationship |
|---|---|
| SEC-0201 — Dependency Scanning | Complementary — SEC-0201 blocks CVEs in app dependencies; SEC-0401 inventories them |
| SEC-0301 — Container Image Scanning | Upstream — SEC-0401 generates the SBOM from the same image that SEC-0301 scanned |
| SEC-0402 — Image Signing and Verification | Downstream — the SBOM produced here is signed alongside the image in SEC-0402, making the inventory tamper-evident |

---

## 8. Compliance Mapping

| Standard | Reference | Notes |
|---|---|---|
| US Executive Order 14028 | §4(e) — Software Supply Chain Security | Mandates SBOM for software sold to US federal agencies |
| NTIA Minimum Elements | All seven elements | CycloneDX satisfies all NTIA minimum elements for a SBOM |
| ISO 27001:2022 | A.8.8 — Management of technical vulnerabilities | SBOM enables accurate vulnerability management across the component inventory |
| ISO 27001:2022 | A.8.32 — Change management | SBOM provides an auditable record of component changes per build |
| SLSA | Level 2–3 | SBOM is a prerequisite for supply chain attestation at higher SLSA levels |
| CycloneDX Specification | v1.6 | The format used by this control |

---

## 9. Evidence Generated

When this control executes, it produces:

- A CycloneDX JSON file containing the full component inventory
  of the scanned image, including package name, version, type,
  ecosystem, and license information where available
- Timestamp of generation
- Image reference (name, tag, digest) from which the SBOM
  was generated

The image digest in the SBOM binds the inventory to the exact
image artifact. This binding is what makes the SBOM signable
and auditable in SEC-0402.

---

## 10. Operational Requirements

1. **SBOM storage:** SBOMs must be stored alongside or linked
   to the image they describe. A SBOM that cannot be correlated
   to a deployed artifact is not useful.

2. **CVE correlation process:** a defined process for querying
   the SBOM inventory against newly published CVEs — either
   manually on high-severity CVE publication, or via automated
   tooling that monitors CVE feeds and cross-references the
   component inventory.

3. **Retention policy:** SBOMs must be retained for at least
   as long as the artifact they describe is in production.
   A SBOM for a decommissioned artifact serves no operational
   purpose but may be required for compliance or audit.

4. **License review process:** the SBOM contains license
   information for all components. A process for reviewing
   license compatibility — particularly for GPL or AGPL
   components in proprietary products — must exist independently
   of this control.
