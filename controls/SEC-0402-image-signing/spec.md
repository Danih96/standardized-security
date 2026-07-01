# SEC-0402 — Image Signing and Verification

## Status
Active

## Last Updated
2026-07

---

## 1. Threat

A container image may be replaced or tampered with after it is
produced by CI, either in the registry or in transit to the
deployment environment, enabling an attacker to deploy malicious
code without modifying the source repository or triggering CI
controls.

**Likelihood without this control:** Medium
Replacing a tag in a container registry requires write access to
the registry, which is a higher bar than read access. However,
registry write access is often broader than necessary — service
accounts, CI tokens, and developer credentials frequently have
push permissions across multiple repositories. A compromised token
is sufficient.

**Impact:** Critical
An attacker who successfully replaces a production image with a
malicious one achieves arbitrary code execution in the production
environment, with whatever privileges the container runs with.
All prior controls — secret detection, dependency scanning,
container scanning, SBOM generation — are bypassed entirely,
because the attack happens after those controls have run.

**Relationship to threat model:**
This control directly mitigates
[T-CICD-005](../../threat-models/infrastructure/ci-cd-pipeline.md)
(unsigned or tampered container image deployed) and
[T-CICD-009](../../threat-models/infrastructure/ci-cd-pipeline.md)
(artifact tampering between build and deployment).

---

## 2. Assets Protected

- Build artifacts — container images in the registry are protected
  against unauthorized replacement or modification
- The production deployment environment — only images produced by
  the authorized CI pipeline can be deployed
- The integrity of the entire security pipeline — an attacker who
  bypasses signing cannot benefit from having circumvented earlier
  controls, because the deployment gate will reject the image

---

## 3. Security Principle

**Integrity** — A cryptographic signature over the image digest
makes tampering detectable. Any modification to the image after
signing changes the digest and invalidates the signature.

**Non-repudiation** — The signature is bound to a specific CI
identity via a short-lived certificate recorded in a public
transparency log. The signing event cannot be denied or removed
from the historical record.

**Defense in Depth** — This control operates at the boundary
between build and deploy. It does not replace the controls that
run during build (SEC-0101 through SEC-0401). It provides a final
gate that ensures the artifact reaching production is the same
artifact that passed all prior controls.

---

## 4. Enforcement Point

This control has two distinct enforcement points that must both
be implemented for the control to be effective.

**Signing — post-build (standardized-security)**

The image is signed immediately after it is produced and scanned,
before it is promoted to the production registry. Signing is
performed by `standardized-security` as the last step of the
build pipeline.

Signing must occur after:
- SEC-0301 (Container Image Scanning) has passed
- SEC-0401 (SBOM Generation) has completed

The SBOM is signed alongside the image as an OCI attestation,
binding the inventory to the artifact.

**Verification — pre-deploy (standardized-deployment)**

The image signature and the SBOM attestation are verified before
any deployment action is taken. Verification is performed by
`standardized-deployment` and is a blocking gate.

A deployment that cannot verify the image signature must not
proceed. An unsigned image and a tampered image are
indistinguishable from the verifier's perspective — both
must be rejected.

**Why two repositories own the two halves of this control:**

`standardized-security` owns the build pipeline. It signs because
it produced the artifact and can attest to what controls ran.
`standardized-deployment` owns the deployment pipeline. It verifies
because it is the last trust boundary before production.
Neither can own both without collapsing the trust boundary that
makes the separation meaningful.

See [SADR-001](../../decisions/SADR-001-trust-boundary-split.md).

---

## 5. Failure Mode

**Signing fails → build fails**

If Cosign cannot sign the image — because the OIDC token is
unavailable, the registry is inaccessible, or Fulcio cannot issue
a certificate — the pipeline fails. An unsigned image must not
be promoted to the production registry.

**Verification fails → deployment blocked**

If Cosign cannot verify the image signature — because the image
is unsigned, the signature is invalid, or the signing identity
does not match the expected identity — the deployment fails.
The deployment system must not proceed with an unverified image.

**Verification must check identity, not just validity**

A valid signature from an unexpected identity — a fork, a
different workflow, a compromised account — must be treated as
a verification failure. The expected signing identity is part
of the control configuration, not an optional check.

---

## 6. Limitations

- **Registry write access is not revoked by signing.** Signing
  proves that the CI pipeline produced the image. It does not
  prevent a privileged attacker from pushing an additional
  unsigned image under a different tag or digest. Registry
  access controls remain necessary.

- **Keyless signing depends on the OIDC provider.** If GitHub's
  OIDC endpoint is unavailable, signing fails. The control has
  a runtime dependency on an external service. This is an accepted
  tradeoff against the key management risk of traditional signing.

- **Fulcio and Rekor are public infrastructure.** Signing events
  are recorded in a public transparency log. The image reference,
  the signing timestamp, and the signing identity (GitHub org,
  repo, workflow, branch) are publicly visible. Organizations
  with confidentiality requirements for build metadata must
  evaluate this before adoption.

- **Verification requires registry access at deploy time.** The
  verifier must be able to reach the registry to retrieve the
  signature. Air-gapped or restricted deployment environments
  require additional configuration to mirror or cache signatures.

- **This control does not cover base image provenance.** The
  signature attests that the CI pipeline produced the final image.
  It does not attest to the provenance of the base image layer.
  Base image integrity requires a separate supply chain control
  not in scope for this milestone.

---

## 7. Related Controls

| Control | Relationship |
|---|---|
| SEC-0301 — Container Image Scanning | Upstream — the image must pass scanning before it is signed |
| SEC-0401 — SBOM Generation | Upstream — the SBOM is signed as an OCI attestation alongside the image |
| SADR-001 — Trust Boundary Split | Architectural decision that explains why signing and verification are split across two repositories |

---

## 8. Compliance Mapping

| Standard | Reference | Notes |
|---|---|---|
| SLSA | Level 2 — Hosted build platform | Signing with a hosted CI identity satisfies SLSA Level 2 provenance requirements |
| SLSA | Level 3 — Hardened build platform | Full SLSA Level 3 requires additional build isolation beyond signing alone |
| US Executive Order 14028 | §4(e) — Software Supply Chain Security | Image signing with attestations contributes to supply chain integrity requirements |
| SSDF (NIST SP 800-218) | PW.4.1 — Protect code | Signing protects the artifact integrity from build to deploy |
| ISO 27001:2022 | A.8.20 — Networks security | Signing ensures integrity of artifacts transiting the registry |
| ISO 27001:2022 | A.5.33 — Protection of records | Transparency log entries provide tamper-evident records of signing events |

---

## 9. Evidence Generated

When this control executes, it produces:

**At signing time:**
- A Cosign signature stored as an OCI artifact in the registry,
  co-located with the signed image
- A CycloneDX SBOM attestation stored as an OCI artifact in the
  registry, co-located with the signed image
- A Rekor transparency log entry containing the signing timestamp,
  the image digest, and the signing certificate identifying the
  GitHub Actions workflow that performed the signing

**At verification time:**
- A pass or fail result indicating whether the image meets the
  expected identity and signature requirements
- The Rekor log entry URL confirming the signing event is recorded

The Rekor entry is the authoritative, tamper-evident record of
when the image was signed and by what identity. It persists
indefinitely in the public transparency log regardless of the
image's lifecycle in the registry.

---

## 10. Operational Requirements

1. **Registry permissions:** the CI identity used for signing must
   have push access to store the signature artifact in the registry.
   The deployment identity must have pull access to retrieve it.

2. **Verification configuration:** the expected signing identity
   (OIDC issuer, certificate identity regexp) must be maintained
   as configuration in `standardized-deployment`. Changes to the
   signing workflow that alter the identity require a coordinated
   update to the verification configuration.

3. **Key rotation (not applicable for keyless signing):** keyless
   signing uses ephemeral certificates. There are no long-lived
   keys to rotate. If the OIDC provider or Fulcio is compromised,
   the response is to re-evaluate all images signed during the
   compromise window using Rekor log entries.

4. **Incident response for signature compromise:** if an
   unauthorized signing event is discovered in Rekor, all images
   signed by the compromised identity during the exposure window
   must be treated as potentially tampered and must not be deployed
   until re-signed by a verified CI run.
