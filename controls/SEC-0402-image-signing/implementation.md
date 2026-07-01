# SEC-0402 — Image Signing and Verification: Implementation

## Status
Active

## Last Updated
2026-07

---

This document describes the current implementation of
[SEC-0402 — Image Signing and Verification](spec.md).

Cosign (Sigstore) is the tool used to satisfy this control.
It is the current implementation, not the definition of the control.
If Cosign is replaced by another tool, this document changes.
The spec does not.

---

## 1. Tool Selection

**Selected tool:** [Cosign](https://github.com/sigstore/cosign)
(Sigstore / Linux Foundation)

### Why Cosign with keyless signing

| Criterion | Cosign keyless | Cosign with key | Notary v2 |
|---|---|---|---|
| Key management required | No | Yes | Yes |
| GitHub Actions native | Yes (OIDC) | Via secrets | Via secrets |
| Transparency log | Rekor (public) | Optional | Optional |
| OCI-native storage | Yes | Yes | Yes |
| SBOM attestation | Yes | Yes | Partial |
| Active maintenance | Yes | Yes | Yes |

Keyless signing is selected over key-based signing for the reason
documented in the spec: a private key is a permanent secret that
must be stored, rotated, and protected. Keyless signing using
GitHub Actions OIDC eliminates the key management problem without
sacrificing cryptographic strength.

Notary v2 is a competing standard for OCI artifact signing. It
requires a key or a signing service and does not have native
keyless support with GitHub Actions OIDC at the level of maturity
that Cosign has. It was not selected for this milestone.

---

## 2. How Cosign Keyless Signing Works

### The signing flow

```
GitHub Actions runner (during workflow execution):

1. Runner requests OIDC token from GitHub
   Token contains: repo, branch, workflow path, commit SHA, run ID

2. Cosign sends OIDC token to Fulcio (Sigstore CA)
   Fulcio verifies the token with GitHub's OIDC endpoint
   Fulcio issues a short-lived X.509 certificate (10 min TTL)
   Certificate subject: the workflow's GitHub Actions identity

3. Cosign generates an ephemeral key pair
   Signs the image digest with the ephemeral private key
   Immediately discards the private key

4. Cosign uploads the signature + certificate to the registry
   Stored as an OCI artifact under a tag derived from the digest:
   sha256-<digest>.sig

5. Cosign records the signing event in Rekor
   Entry contains: digest, certificate, signature, timestamp
   Entry is append-only and publicly verifiable
```

### Where signatures are stored

Signatures are stored in the same registry as the image, not in
a separate system:

```
ghcr.io/org/myapp@sha256:abc123      ← the image
ghcr.io/org/myapp:sha256-abc123.sig  ← the Cosign signature
ghcr.io/org/myapp:sha256-abc123.att  ← the SBOM attestation
```

When the image is copied to another registry, the `.sig` and
`.att` artifacts must be copied alongside it. Tools like Crane
and Skopeo support this with `--all-tags` or equivalent flags.
Failure to copy signatures causes verification to fail in the
destination registry.

### SBOM attestation

When a SBOM is provided, Cosign signs an attestation that binds
the SBOM content to the image digest:

```bash
cosign attest \
  --yes \
  --predicate sbom.cdx.json \
  --type cyclonedx \
  ghcr.io/org/myapp@sha256:abc123
```

The attestation is stored alongside the image as an OCI artifact.
This replaces the 30-day CI artifact retention from SEC-0401 with
permanent co-location in the registry.

---

## 3. Configuration Decisions

### Keyless signing — no `--key` flag

The workflow uses `cosign sign --yes` without a key argument.
Cosign detects the GitHub Actions OIDC environment automatically
and requests a Fulcio certificate. No secret configuration is
required in the consuming repository.

### Sign by digest, not by tag

The workflow signs `image-ref` which must be a digest-pinned
reference (`sha256:...`). Tag-based references are not accepted
because:

- Tags are mutable — the tag may point to a different image by
  the time verification runs
- Evidence recording a tag is not auditable — "which image was
  `latest` at 14:32?" cannot be answered after the fact
- Cosign resolves tags to digests internally, but the recorded
  evidence reflects the tag, not the digest

The consuming pipeline must resolve the image tag to a digest
before calling this workflow. This is typically available as an
output from `docker push` or from the registry API.

### SBOM attestation: optional input

The workflow accepts `sbom-path` as an optional input. When
provided, Cosign attests the SBOM alongside the image signature.
When omitted, only the image is signed.

Consuming pipelines that have completed SEC-0401 should always
provide `sbom-path` to produce the full attestation chain.
Signing without SBOM attestation satisfies the tamper-detection
requirement but loses the permanent inventory storage benefit.

### Registry authentication

The workflow uses `GITHUB_TOKEN` for `ghcr.io`. The token must
have `packages: write` permission to push the signature artifact
to the registry. This permission is declared in the workflow's
`permissions:` block.

---

## 4. Exception Management

There is no exception management for image signing. Either the
image is signed or it is not. There is no concept of a "partial
signature" or a "suppressed signing requirement."

If a consuming pipeline cannot complete signing — because the
image failed scanning, the OIDC token is unavailable, or the
registry is inaccessible — the pipeline fails. The image must
not be deployed unsigned.

---

## 5. Verification (standardized-deployment)

Verification is implemented in `standardized-deployment` and
is documented here for reference. The verification command that
must be run before any deployment:

```bash
# Verify image signature
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp \
    "^https://github.com/<org>/<repo>/.github/workflows/release.yml@refs/heads/main$" \
  ghcr.io/org/myapp@sha256:abc123

# Verify SBOM attestation
cosign verify-attestation \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp \
    "^https://github.com/<org>/<repo>/.github/workflows/release.yml@refs/heads/main$" \
  --type cyclonedx \
  ghcr.io/org/myapp@sha256:abc123
```

`--certificate-identity-regexp` must specify the exact workflow
that is authorized to sign production images. Using a broad regexp
(e.g., matching all workflows in the org) weakens the control to
the point of ineffectiveness.

---

## 6. Known Limitations

- **Signatures must be copied with the image.** Moving an image
  to a different registry without copying its `.sig` and `.att`
  artifacts causes verification to fail. All mirror and promotion
  processes must be updated to copy OCI artifacts, not just the
  image layers.

- **Rekor entries are public.** The signing identity (org, repo,
  workflow, branch, commit SHA) and the image digest are recorded
  publicly in Rekor. This is inherent to keyless signing with a
  public transparency log. Organizations with build metadata
  confidentiality requirements must evaluate this before adoption
  or operate a private Rekor instance.

- **Fulcio and Rekor availability.** Signing has a runtime
  dependency on Sigstore's public infrastructure. If Fulcio is
  unavailable, signing fails and the pipeline is blocked. Sigstore
  operates at high availability, but the dependency exists.

- **10-minute certificate TTL.** The Fulcio-issued certificate is
  valid for 10 minutes. Signing must complete within this window.
  For very large images where push takes more than 10 minutes,
  the certificate may expire before signing completes.

- **Verification requires registry access.** `cosign verify`
  fetches the signature from the registry at verification time.
  Air-gapped or restricted environments must mirror or cache
  signatures alongside images.

---

## 7. Validation

Two scenarios must pass to confirm this implementation is working.
Full procedures are in [tests/README.md](tests/README.md).

| Scenario | Expected result |
|---|---|
| Image signed successfully | Cosign reports success, signature artifact present in registry, Rekor entry URL returned |
| Unsigned image fails verification | `cosign verify` exits non-zero, deployment blocked |

---

## 8. Future Improvements

**Private Rekor instance**
Organizations with build metadata confidentiality requirements can
operate a private Rekor instance and configure Cosign to use it
instead of the public Sigstore infrastructure. This preserves the
transparency log model without public disclosure of build metadata.

**SLSA provenance attestation**
In addition to the SBOM attestation, a SLSA provenance document
can be generated and attested using `cosign attest --type slsaprovenance`.
This provides a machine-verifiable record of how the artifact was
built — which source commit, which build system, which inputs —
satisfying SLSA Level 2 provenance requirements.

**Policy enforcement with Sigstore Policy Controller**
The Sigstore Policy Controller is a Kubernetes admission controller
that enforces signing policies at the cluster level — rejecting
pods that reference unsigned or improperly signed images before
they are scheduled. This provides a runtime enforcement layer
complementing the pipeline gate in `standardized-deployment`.

**VEX attestation**
As discussed in SEC-0401, VEX documents can be attached as Cosign
attestations using `--type vex`. This is the production form of
exception management for CVEs: instead of `.trivyignore` entries
visible only to Trivy, the exploitability assessment is signed
and co-located with the image in the registry.
