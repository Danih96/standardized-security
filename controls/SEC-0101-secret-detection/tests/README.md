# SEC-0101 — Validation Scenarios

These scenarios validate that the Gitleaks implementation of
SEC-0101 is working correctly in a consuming repository.

Both scenarios must pass before Milestone 1 is considered complete.

---

## Scenario 1 — Negative: clean repository

**Purpose:** confirm that a repository with no secrets produces a
passing workflow run and a clean SARIF artifact.

### Setup

1. Create a test repository (or use an existing one with no secrets).
2. Add the reusable workflow call to `.github/workflows/ci.yml`:

```yaml
jobs:
  call-secret-detection:
    uses: your-org/standardized-security/.github/workflows/secret-detection.yml@main
```

3. Commit a file with no sensitive content, for example:

```
echo "Hello, world." > hello.txt
git add hello.txt
git commit -m "test: add clean file for secret detection validation"
```

4. Open a pull request.

### Expected result

- The `secret-detection` job passes.
- A workflow artifact named `secret-detection-results` is produced.
- The SARIF file inside the artifact contains zero findings.

### How to verify

- In the GitHub Actions run, the `secret-detection` job shows a green check.
- Download the `secret-detection-results` artifact and inspect the SARIF file.
  Under `runs[].results`, the array must be empty (`[]`).

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Job not found in branch protection | Job name in the workflow was changed from `secret-detection` |
| Artifact not produced | Upload step did not run — check that `if: always()` is present |
| SARIF file missing from artifact | Gitleaks did not write the report — check the `--report-path` argument |

---

## Scenario 2 — Positive: secret present

**Purpose:** confirm that a repository containing a known secret
format produces a failing workflow run and a SARIF artifact with
at least one finding.

### Test value

```
AKIAIOSFODNN7EXAMPLE
```

This is an intentionally fake AWS access key used only for
validation purposes. It matches the AWS access key pattern
(`AKIA[A-Z0-9]{16}`) and is listed in AWS documentation as a
non-functional example value. It does not grant access to any
AWS account.

### Setup

1. In the test repository, commit a file containing the test value:

```
echo "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE" > test-secret.txt
git add test-secret.txt
git commit -m "test: add fake AWS key to validate secret detection"
```

2. Open a pull request.

### Expected result

- The `secret-detection` job fails.
- A workflow artifact named `secret-detection-results` is produced.
- The SARIF file inside the artifact contains at least one finding
  referencing `test-secret.txt`.

### How to verify

- In the GitHub Actions run, the `secret-detection` job shows a red cross.
- The failing step is `Scan for secrets`, not a later step.
- Download the `secret-detection-results` artifact and inspect the SARIF file.
  Under `runs[].results`, at least one result must reference
  `test-secret.txt` with a rule matching the AWS access key pattern.

### Cleanup

After validation, remove the test file and close or delete the
pull request. Do not merge a branch containing this file, even
though the key is fake.

```
git rm test-secret.txt
git commit -m "test: remove fake AWS key after validation"
```

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Job passes despite the fake key | `fetch-depth` is not `0` — Gitleaks is scanning less history than expected |
| Job passes despite the fake key | The test value was modified and no longer matches the AWS rule pattern |
| Artifact not produced | The upload step requires `if: always()` — verify the workflow definition |
