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

### Test base image

```dockerfile
FROM ubuntu:18.04
```

Ubuntu 18.04 reached end of life in April 2023. It contains
numerous unpatched HIGH and CRITICAL CVEs across OS packages
including OpenSSL, curl, and glibc. It will not receive further
security updates and will reliably produce findings for the
foreseeable future.

This is an intentionally vulnerable base image used only for
validation purposes. It must never be used in a production image.

### Setup

1. Create the Dockerfile above and build the image:

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
- The SARIF file contains multiple findings at HIGH or CRITICAL
  severity, referencing Ubuntu 18.04 OS packages.

### How to verify

- In the GitHub Actions run, the `container-scanning` job shows
  a red cross.
- The failing step is the Trivy scan step.
- Download the `container-scanning-results` artifact. Under
  `runs[].results`, multiple results reference OS packages
  (curl, libssl, libc-bin, or similar) at HIGH or CRITICAL severity.
- Findings should reference Ubuntu Security Notices (USN) as
  the advisory source — confirming that OS-specific databases
  are being consulted, not only OSV or GHSA.

### Cleanup

After validation, delete the test image from the registry.
Do not use `ubuntu:18.04` as a base in any non-test image.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Job passes despite ubuntu:18.04 | Severity threshold is set above HIGH — verify input values |
| Findings reported but source is OSV/GHSA only | Ubuntu SecDB may not be loading — check Trivy database initialization in the workflow logs |
| Trivy cannot pull the image | Registry authentication issue — verify GITHUB_TOKEN has `packages: read` permission |
| No artifact produced | Upload step is missing `if: always()` — verify the workflow definition |
