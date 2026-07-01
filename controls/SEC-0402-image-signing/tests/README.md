# SEC-0402 — Validation Scenarios

These scenarios validate that the Cosign implementation of
SEC-0402 is working correctly in a consuming repository.

Both scenarios must pass before Milestone 5 is considered complete.

---

## Scenario 1 — Image signed successfully

**Purpose:** confirm that the workflow signs the image, stores the
signature in the registry, and records the signing event in Rekor.

### Setup

1. Use the image from SEC-0301 Scenario 1 (clean Alpine image).
   Push it to the registry and capture the digest:

   ```bash
   docker build -t ghcr.io/<org>/<repo>:test-sign .
   docker push ghcr.io/<org>/<repo>:test-sign

   # Capture digest — required for signing and verification
   DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' \
     ghcr.io/<org>/<repo>:test-sign | cut -d@ -f2)
   ```

2. Call the reusable workflow with the digest-pinned reference:

   ```yaml
   jobs:
     call-image-signing:
       uses: your-org/standardized-security/.github/workflows/image-signing.yml@main
       with:
         image-ref: ghcr.io/<org>/<repo>@${{ env.DIGEST }}
       permissions:
         id-token: write    # required for Cosign OIDC
         packages: write    # required to push signature to registry
   ```

3. Open a pull request or trigger the workflow manually.

### Expected result

- The `image-signing` job passes.
- Cosign outputs a Rekor entry URL in the job logs.
- The signature artifact is present in the registry.

### How to verify

**Signature present in registry:**
```bash
cosign triangulate ghcr.io/<org>/<repo>@<digest>
# Returns: ghcr.io/<org>/<repo>:sha256-<digest>.sig
# Verify the tag exists in the registry
```

**Signature is valid and identity matches:**
```bash
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp \
    "^https://github.com/<org>/<repo>/.github/workflows/.*" \
  ghcr.io/<org>/<repo>@<digest>
# Expected: verified OK — certificate identity logged to stdout
```

**Rekor entry exists:**
```bash
# The Rekor URL is printed in the Cosign step logs
# Open it in a browser or query with:
rekor-cli get --uuid <uuid-from-logs>
```

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Error: no matching signatures` | `id-token: write` permission not set on the calling job |
| `Error: DENIED: requested access to the resource is denied` | `packages: write` permission not set, or image not in `ghcr.io` |
| `Error: certificate has expired` | Image push took more than 10 minutes — signing must occur immediately after push |
| Rekor URL not in logs | `--yes` flag missing — Cosign waited for interactive confirmation |

---

## Scenario 2 — Unsigned image fails verification

**Purpose:** confirm that an image without a valid signature is
rejected by the verification step, blocking deployment.

### Setup

1. Push an image to the registry **without** calling the signing
   workflow:

   ```bash
   docker build -t ghcr.io/<org>/<repo>:test-unsigned .
   docker push ghcr.io/<org>/<repo>:test-unsigned
   DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' \
     ghcr.io/<org>/<repo>:test-unsigned | cut -d@ -f2)
   ```

2. Run `cosign verify` directly against the unsigned image:

   ```bash
   cosign verify \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
     --certificate-identity-regexp \
       "^https://github.com/<org>/<repo>/.github/workflows/.*" \
     ghcr.io/<org>/<repo>@$DIGEST
   ```

### Expected result

- `cosign verify` exits with a non-zero exit code.
- Output contains: `Error: no matching signatures`
- No deployment proceeds.

### How to verify

```bash
cosign verify [...] ghcr.io/<org>/<repo>@<digest>
echo "Exit code: $?"
# Expected exit code: 1
```

### Note on verification ownership

In production, this verification runs in `standardized-deployment`,
not in `standardized-security`. This scenario is run manually or
in a dedicated test job to confirm the verification tooling is
correctly configured before it is wired into the deployment pipeline.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Unsigned image passes verification | `--certificate-identity-regexp` too broad or missing |
| Command not found: cosign | `sigstore/cosign-installer` action not run before verification step |
