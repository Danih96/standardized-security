# SEC-0401 — Validation Scenarios

These scenarios validate that the Trivy implementation of
SEC-0401 is working correctly in a consuming repository.

Both scenarios must pass before Milestone 4 is considered complete.

SBOM validation differs from previous controls: there are no
findings to detect. Validation confirms that the SBOM was produced,
is structurally valid, and contains the components it should contain.

---

## Scenario 1 — SBOM produced and structurally valid

**Purpose:** confirm that the workflow produces a valid CycloneDX
SBOM containing the minimum required elements.

### Setup

1. Use any valid container image accessible from the runner.
   The image from SEC-0301 Scenario 1 (`alpine:3.21`) is suitable:

   ```
   docker build -t ghcr.io/<org>/<repo>:test-sbom .
   docker push ghcr.io/<org>/<repo>:test-sbom
   ```

2. Call the reusable workflow from `.github/workflows/ci.yml`:

   ```yaml
   jobs:
     call-sbom-generation:
       uses: your-org/standardized-security/.github/workflows/sbom-generation.yml@main
       with:
         image-ref: ghcr.io/<org>/<repo>:test-sbom
   ```

3. Open a pull request or trigger the workflow manually.

### Expected result

- The `sbom-generation` job passes.
- A workflow artifact named `sbom-results` is produced.
- The artifact contains `sbom.cdx.json`.

### How to verify

Download the `sbom-results` artifact and run the following checks:

**1. Valid JSON:**
```bash
cat sbom.cdx.json | python3 -m json.tool > /dev/null && echo "Valid JSON"
```

**2. Correct format declaration:**
```bash
cat sbom.cdx.json | jq '.bomFormat'
# Expected: "CycloneDX"

cat sbom.cdx.json | jq '.specVersion'
# Expected: "1.6"
```

**3. NTIA minimum elements present:**
```bash
# Author of SBOM data and timestamp
cat sbom.cdx.json | jq '.metadata.timestamp'
# Expected: a non-null timestamp string

# Top-level component (the image being inventoried)
cat sbom.cdx.json | jq '.metadata.component.name'
# Expected: the image reference (repo:tag)

cat sbom.cdx.json | jq '.metadata.component.purl'
# Expected: a pkg:oci/... purl containing the image digest (sha256:...)
# Trivy models the top-level component as type "container" and stores
# the digest in .purl (and in the "aquasecurity:trivy:RepoDigest"
# property), not in .version — .version is null for this component
# type, which is expected, not a misconfiguration.

# Components present
cat sbom.cdx.json | jq '.components | length'
# Expected: a number greater than zero
```

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Artifact not produced | Upload step is missing `if: always()` or SBOM file path does not match |
| `.components` is empty | Image has no detectable packages — verify the image has OS packages or app manifests |
| `.metadata.component.version` is `null` | Expected for `type: "container"` components — Trivy stores the digest in `.purl`, not `.version` |
| `.metadata.component.purl` has no `sha256:` digest | Image was referenced by tag only and could not be resolved to a digest — verify the registry push succeeded before scanning |

---

## Scenario 2 — Known component appears with correct purl

**Purpose:** confirm that Trivy correctly identified a specific,
known component in the image and recorded it with a valid purl
and exact version. This validates that the relevant image layer
was inspected, not just that a SBOM file was produced.

### Setup

1. Build an image that contains a known, verifiable component.
   Use the `lodash@4.17.21` npm package from SEC-0201 Scenario 1
   (the non-vulnerable version):

   `package.json`:
   ```json
   {
     "dependencies": {
       "lodash": "4.17.21"
     }
   }
   ```

   `Dockerfile`:
   ```dockerfile
   FROM alpine:3.21
   RUN apk add --no-cache nodejs npm
   COPY package.json package-lock.json ./
   RUN npm ci --omit=dev
   ```

   ```
   npm install
   docker build -t ghcr.io/<org>/<repo>:test-sbom-lodash .
   docker push ghcr.io/<org>/<repo>:test-sbom-lodash
   ```

2. Call the workflow with this image reference.

### Expected result

- The `sbom-generation` job passes.
- The SBOM contains `lodash@4.17.21` with the correct purl.

### How to verify

```bash
# Check lodash appears with correct purl and version
# (guard against null .purl on some components, or jq errors instead
# of just returning false)
cat sbom.cdx.json | jq '.components[] | select(.purl != null and (.purl | contains("pkg:npm/lodash")))'
```

Expected output includes:
```json
{
  "type": "library",
  "name": "lodash",
  "version": "4.17.21",
  "purl": "pkg:npm/lodash@4.17.21"
}
```

Also verify that Alpine OS packages are present alongside the
npm package — confirming that both application and OS layers
were inspected:

```bash
cat sbom.cdx.json | jq '[.components[] | select(.purl != null and (.purl | startswith("pkg:apk")))] | length'
# Expected: a number greater than zero
```

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| `lodash` not found in components | `package-lock.json` not committed — Trivy may have incomplete npm coverage |
| `lodash` found but purl is wrong | Verify the package type prefix: npm packages use `pkg:npm/`, not `pkg:pypi/` or others |
| No Alpine packages in SBOM | Trivy may be scanning filesystem only — verify `scan-type: image` in the workflow |
| Version is `4.17.20` instead of `4.17.21` | Lock file from a previous install — run `npm install` again and commit the updated lock file |
| `jq` errors with "cannot have their containment checked" | Some components have `.purl: null` — use the `.purl != null and (...)` guard shown above, not a bare `contains()`/`startswith()` |
