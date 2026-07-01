# SEC-0301 — Validation Scenarios

These scenarios validate that the Trivy implementation of
SEC-0301 is working correctly in a consuming repository.

Both scenarios must pass before Milestone 3 is considered complete.

---

## Scenario 1 — Negative: clean base image

**Purpose:** confirm that an image built from a current,
non-vulnerable base produces a passing workflow run and a
clean SARIF artifact.

### Setup

1. Create a minimal Dockerfile using a recent, actively maintained
   base image:

   ```dockerfile
   FROM alpine:3.21
   ```

   Alpine 3.21 is a current, actively maintained release.
   At the time of writing it contains no HIGH or CRITICAL CVEs
   in its default package set. This may change as new CVEs are
   published — if the workflow fails unexpectedly, check for
   newly published CVEs in the Alpine SecDB before concluding
   the control is misconfigured.

2. Build and push the image to GitHub Container Registry:

   ```
   docker build -t ghcr.io/<org>/<repo>:test-clean .
   docker push ghcr.io/<org>/<repo>:test-clean
   ```

3. Call the reusable workflow from `.github/workflows/ci.yml`:

   ```yaml
   jobs:
     call-container-scanning:
       uses: your-org/standardized-security/.github/workflows/container-scanning.yml@main
       with:
         image-ref: ghcr.io/<org>/<repo>:test-clean
   ```

4. Open a pull request or trigger the workflow manually.

### Expected result

- The `container-scanning` job passes.
- A workflow artifact named `container-scanning-results` is produced.
- The SARIF file contains zero findings at HIGH or CRITICAL severity.

### How to verify

- In the GitHub Actions run, the `container-scanning` job shows
  a green check.
- Download the `container-scanning-results` artifact. Under
  `runs[].results`, no result should have a severity of `error`
  or above.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Job fails despite a recent base image | A new CVE was published after this test was written — verify using Alpine SecDB before concluding misconfiguration |
| Artifact not produced | Upload step is missing `if: always()` — verify the workflow definition |
| Trivy cannot pull the image | Registry authentication issue — verify GITHUB_TOKEN has `packages: read` permission |

---

## Scenario 2 — Positive: vulnerable base image

**Purpose:** confirm that an image built from a base image
with known HIGH or CRITICAL CVEs produces a failing workflow run.

### Test image

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
```

`package.json` pins `lodash` to `4.17.20`, which contains
`CVE-2021-23337` (command injection, CVSS 7.2 HIGH) — the same
dependency and CVE used to validate SEC-0201 (dependency-scanning).

**Why not an EOL OS base image (e.g. `ubuntu:18.04`):** this
scenario previously used `ubuntu:18.04` for its unpatched OS CVEs.
That approach decays over time — once a distribution goes far
enough past end of life, the vendor stops publishing new OVAL/USN
data for it, and Trivy can no longer confirm vulnerability status
for its packages at all (`WARN This OS version is no longer
supported by the distribution`), producing zero findings instead
of the expected failure. A pinned application-level dependency
with a permanent GHSA/OSV advisory does not have this problem —
`CVE-2021-23337` will not disappear from the vulnerability database
as `lodash 4.17.20` ages.

This also validates something an OS-CVE-only scenario would not:
that `container-scanning` catches vulnerable application
dependencies baked into the image (`node_modules`), not just OS
packages — defense in depth alongside `dependency-scanning`, which
only sees the source repository, not what actually ships in the
image.

This is an intentionally vulnerable dependency used only for
validation purposes. It must never be used in a production image.

### Setup

1. Create the Dockerfile and `package.json`/`package-lock.json`
   above (matching the SEC-0201 test fixture), then build the image:

   ```
   docker build -t ghcr.io/<org>/<repo>:test-vulnerable .
   docker push ghcr.io/<org>/<repo>:test-vulnerable
   ```

2. Call the reusable workflow:

   ```yaml
   jobs:
     call-container-scanning:
       uses: your-org/standardized-security/.github/workflows/container-scanning.yml@main
       with:
         image-ref: ghcr.io/<org>/<repo>:test-vulnerable
   ```

3. Open a pull request or trigger the workflow manually.

### Expected result

- The `container-scanning` job fails.
- A workflow artifact named `container-scanning-results` is produced.
- The SARIF file contains at least one finding referencing
  `lodash` and `CVE-2021-23337` at HIGH severity.

### How to verify

- In the GitHub Actions run, the `container-scanning` job shows
  a red cross.
- The failing step is the Trivy scan step.
- Download the `container-scanning-results` artifact. Under
  `runs[].results`, at least one result must reference `lodash`
  with rule ID matching `CVE-2021-23337`.

### Cleanup

After validation, delete the test image from the registry and
update `lodash` to `4.17.21` or later.
Do not use `lodash 4.17.20` in any non-test image.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Job passes despite `lodash@4.17.20` | Severity threshold is set above HIGH — verify input values |
| Job passes despite `lodash@4.17.20` | `package-lock.json` was not copied into the image before `npm ci` — Trivy only sees what's actually in the image filesystem |
| Different CVE reported than expected | Trivy may report additional CVEs in the same version — this is expected and correct |
| Trivy cannot pull the image | Registry authentication issue — verify GITHUB_TOKEN has `packages: read` permission |
| No artifact produced | Upload step is missing `if: always()` — verify the workflow definition |
