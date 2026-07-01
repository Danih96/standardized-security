# SEC-0101 — Secret Detection: Implementation

## Status
Active

## Last Updated
2026-06

---

This document describes the current implementation of
[SEC-0101 — Secret Detection](spec.md).

Gitleaks is the tool used to satisfy this control.
It is the current implementation, not the definition of the control.
If Gitleaks is replaced by another tool, this document changes.
The spec does not.

---

## 1. Tool Selection

**Selected tool:** [Gitleaks](https://github.com/gitleaks/gitleaks)

### Why Gitleaks over alternatives

| Criterion | Gitleaks | TruffleHog | detect-secrets |
|---|---|---|---|
| Git-native scanning | Yes — walks git history natively | Yes | No — file-based only |
| Speed | High — written in Go | Moderate | Moderate |
| Default ruleset quality | Strong — broad provider coverage | Strong | Moderate |
| SARIF output | Native | Via flag | Third-party scripts |
| Active maintenance | Yes | Yes | Reduced activity |
| GitHub Actions integration | Official action available | Community action | Manual setup |

The deciding factors were git-native history scanning, native SARIF
output (required for GitHub Security tab integration), and the
availability of an official GitHub Actions action maintained by
the Gitleaks team.

TruffleHog was evaluated and is a viable alternative. Its verify
mode — which tests whether a detected secret is still active — is
a capability Gitleaks does not currently offer. This is noted as
a known limitation and a future improvement.

detect-secrets was not selected because it operates on files rather
than git history, which means secrets removed from the working tree
but present in earlier commits within the same branch are not detected.

---

## 2. How Gitleaks Works

### Primary mechanism: pattern matching

Gitleaks compares git content against a set of regular expression
rules. Each rule targets a specific secret type — AWS access keys,
GitHub tokens, private key headers, and similar. A match produces
a finding.

The default ruleset covers the most common credential types across
major cloud providers and SaaS platforms. It does not cover
internally generated tokens or generic high-entropy strings unless
custom rules are defined.

### Secondary mechanism: entropy filtering

Rules may include an entropy threshold. Content that matches a
pattern but falls below the entropy threshold is suppressed.
This reduces false positives for low-entropy placeholder values
that match a secret pattern syntactically but are unlikely to be
real secrets.

Entropy filtering is a heuristic, not a guarantee. A real secret
with low entropy will not be caught by entropy filtering alone.

### No live verification

Gitleaks does not contact any external service to verify whether
a detected secret is currently valid. This has two implications:

- **False positives:** a rotated or intentionally fake value that
  matches a rule pattern will produce a finding. The finding must
  be triaged manually.
- **False negatives:** a valid secret that does not match any rule
  pattern will not produce a finding, regardless of its entropy.

Verification-mode scanning (testing whether a detected secret is
still active) is a future improvement. See §7.

---

## 3. Configuration Decisions

### Scan scope: full branch history

The workflow checks out the repository with `fetch-depth: 0`,
giving Gitleaks access to the full git history of the branch.

This is required because a secret introduced in an earlier commit
within the same pull request is still an exposure, even if it was
removed in a later commit. Scanning only the diff of the latest
commit would miss this case.

### Failure mode: fail closed

The workflow fails (non-zero exit) when Gitleaks reports a finding.
The workflow also fails if Gitleaks cannot run — for example, due
to a missing action, a misconfigured environment, or a checkout
failure.

A scan that does not run is not a passing scan.
This is not configurable as a default. See the `fail-on-findings`
input in the workflow for the mechanism available to consumers
during initial rollout.

### Output format: SARIF

Gitleaks produces output in SARIF format. The workflow uploads this
file as a workflow artifact named `secret-detection-results`.

SARIF is the format accepted by the GitHub Security tab and by
many third-party security posture platforms. Producing SARIF
preserves optionality for downstream tooling without coupling
the workflow to any specific consumer.

### Custom rules: `.gitleaks.toml`

Custom rules are defined in a `.gitleaks.toml` file at the root
of the repository being scanned. Gitleaks merges custom rules
with its default ruleset.

A custom rule has this structure:

```toml
[[rules]]
id          = "internal-api-token"
description = "Internal API token"
regex       = '''TOKEN_[A-Z0-9]{32}'''
tags        = ["internal", "api"]
```

Custom rules are added when the default ruleset does not cover
a secret format used in the organization. They must be reviewed
alongside the exception allowlist (see §4).

---

## 4. Exception Management

Exceptions are declared in the `[allowlist]` section of
`.gitleaks.toml` in the repository being scanned.

### Required fields for every allowlist entry

```toml
[[allowlist.commits]]
# Human-readable description of why this finding is suppressed
description = "Fake AWS key used in unit test fixture — not a real credential"

# Regex matching the specific finding being suppressed
regex       = '''AKIAABCDEFGHIJKLMNOP'''

# Owner of this exception — team or individual responsible for review
# owner = "security-team"          # add as a comment field

# Review date — when this exception must be re-evaluated
# review-date = "2026-12"          # add as a comment field
```

`description`, `regex`, `owner`, and `review-date` are all required
in practice. `owner` and `review-date` are added as TOML comments
because Gitleaks does not enforce custom fields — the process must.

### Scope restriction

Allowlist entries must be scoped to the specific finding being
suppressed, identified by its regex or by the commit SHA.

**Not permitted:**

```toml
# This suppresses all findings in a directory — never acceptable
[allowlist]
paths = ["tests/fixtures/"]
```

**Permitted:**

```toml
# This suppresses one specific finding
[[allowlist.commits]]
description = "Fake key in test fixture — see issue #42"
regex       = '''AKIAABCDEFGHIJKLMNOP'''
```

File-level and directory-level suppression are not permitted because
they create a permanent blind spot. A future real secret placed in
the same path would not be detected.

---

## 5. Known Limitations

The following limitations are specific to Gitleaks as the
implementation of SEC-0101. For limitations that apply to the
control itself regardless of tooling, see [spec.md §6](spec.md).

- **No verify mode.** Gitleaks cannot determine whether a detected
  secret is currently valid. Confirmed findings always require
  manual triage.

- **Default ruleset coverage gaps.** Internally generated tokens,
  symmetric keys without a recognizable prefix, and simple
  passwords are not detected by default. Custom rules are required
  to extend coverage.

- **No pre-commit enforcement.** This implementation runs in CI
  only. A developer will not see a finding until the pull request
  pipeline runs. Pre-commit tooling (also Gitleaks, run locally)
  is a complementary convenience layer and is not a substitute
  for the CI control.

- **History depth depends on checkout configuration.** If the
  workflow is modified to use a shallow clone (`fetch-depth` set
  to a non-zero value), Gitleaks will silently scan less history.
  The current configuration uses `fetch-depth: 0` to prevent this.

- **SARIF file contains matched content.** The SARIF output
  includes the matched string from the source code. If the finding
  is a real secret, the SARIF artifact contains a copy of that
  secret. Artifact retention must be set appropriately in the
  consuming workflow.

---

## 6. Validation

To confirm that this implementation is working correctly, two
scenarios must pass. Full procedures are in
[tests/README.md](tests/README.md).

| Scenario | Expected result |
|---|---|
| Repository with no secrets | Workflow passes, SARIF artifact produced with zero findings |
| Repository with `AKIAABCDEFGHIJKLMNOP` in a committed file | Workflow fails, finding reported in SARIF artifact |

---

## 7. Future Improvements

**Verify mode**
TruffleHog and some commercial tools can test whether a detected
secret is still active by making a safe API call to the provider.
If Gitleaks adds native verify support, or if the workflow is
extended with a verification step, false positive rates on
real-format keys will decrease significantly.

**Custom ruleset expansion**
As internal token formats are identified, custom rules should be
added to a shared `.gitleaks.toml` maintained in this repository
and referenced by consumer repositories. This moves rule
maintenance to the platform rather than leaving it to individual
application teams.

**Pre-commit distribution**
A documented, opt-in pre-commit hook using Gitleaks can be
distributed to development teams as a convenience layer. This
does not replace the CI control and must not be presented as
an organizational control.
