# SEC-0201 — Validation Scenarios

These scenarios validate that the Trivy implementation of
SEC-0201 is working correctly in a consuming repository.

Both scenarios must pass before Milestone 2 is considered complete.

---

## Scenario 1 — Negative: clean dependencies

**Purpose:** confirm that a repository with no vulnerable
dependencies produces a passing workflow run and a clean
SARIF artifact.

### Setup

1. Create a test repository with a dependency manifest that
   contains no known HIGH or CRITICAL vulnerabilities.
   A minimal example using a recent, non-vulnerable version:

   `package.json`:
   ```json
   {
     "dependencies": {
       "express": "4.21.2"
     }
   }
   ```

   Commit the manifest and its lock file:
   ```
   npm install
   git add package.json package-lock.json
   git commit -m "test: add clean dependency for scanning validation"
   ```

2. Add the reusable workflow call to `.github/workflows/ci.yml`:

   ```yaml
   jobs:
     call-dependency-scanning:
       uses: your-org/standardized-security/.github/workflows/dependency-scanning.yml@main
   ```

3. Open a pull request.

### Expected result

- The `dependency-scanning` job passes.
- A workflow artifact named `dependency-scanning-results` is produced.
- The SARIF file contains zero findings at HIGH or CRITICAL severity.

### How to verify

- In the GitHub Actions run, the `dependency-scanning` job shows
  a green check.
- Download the `dependency-scanning-results` artifact and inspect
  the SARIF file. Under `runs[].results`, no result should have
  a severity of `error` (which maps to HIGH) or above.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Job fails on a version you expect to be clean | A new CVE was published after this test was written — update the version |
| SARIF artifact not produced | Upload step is missing `if: always()` — verify the workflow definition |
| Transitive CVEs appear unexpectedly | Lock file was committed — this is correct behavior, not a false positive |

---

## Scenario 2 — Positive: vulnerable dependency present

**Purpose:** confirm that a repository containing a dependency
with a known HIGH or CRITICAL CVE produces a failing workflow run.

### Test dependency

Use a pinned version of `lodash` with CVE-2021-23337 (command
injection, CVSS 7.2 HIGH):

`package.json`:
```json
{
  "dependencies": {
    "lodash": "4.17.20"
  }
}
```

`lodash` version `4.17.20` contains CVE-2021-23337. The fix is
present in `4.17.21`. This CVE is well-established in all major
vulnerability databases and reliably detected by Trivy.

### Setup

1. Commit the vulnerable manifest and lock file:

   ```
   npm install
   git add package.json package-lock.json
   git commit -m "test: add vulnerable lodash version to validate dependency scanning"
   ```

2. Open a pull request.

### Expected result

- The `dependency-scanning` job fails.
- A workflow artifact named `dependency-scanning-results` is
  produced.
- The SARIF file contains at least one finding referencing
  `lodash` and `CVE-2021-23337` at HIGH severity.

### How to verify

- In the GitHub Actions run, the `dependency-scanning` job shows
  a red cross.
- The failing step is the Trivy scan step, not a later step.
- Download the `dependency-scanning-results` artifact. Under
  `runs[].results`, at least one result must reference `lodash`
  with rule ID matching `CVE-2021-23337`.

### Cleanup

After validation, update `lodash` to `4.17.21` or later and
re-run the workflow to confirm the job now passes.

```
npm install lodash@4.17.21
git add package.json package-lock.json
git commit -m "test: update lodash to non-vulnerable version after validation"
```

Do not merge the branch containing `4.17.20` into the main branch.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Job passes despite `lodash@4.17.20` | Lock file not committed — Trivy only sees the manifest, may miss transitive resolution |
| Job passes despite `lodash@4.17.20` | Trivy database is stale — check if the runner is reusing a cached database |
| CVE appears but job does not fail | Severity threshold is set above HIGH — verify `fail-on-findings` and severity input values |
| Different CVE reported than expected | Trivy may report additional CVEs in the same version — this is expected and correct |
