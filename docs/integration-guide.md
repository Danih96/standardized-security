# Integration Guide

How application repositories consume standardized-security.

---

## Prerequisites

- A GitHub repository with Actions enabled
- Branch protection rules enabled on your default branch
- At minimum one protected branch that requires status checks
  to pass before merging

---

## Step 1 — Call the Secret Detection Workflow

In your application repository, create or update your pull
request workflow:

```yaml
# .github/workflows/security.yml

name: Security

on:
  pull_request:
    branches:
      - main

jobs:
  secret-detection:
    uses: your-org/standardized-security/.github/workflows/secret-detection.yml@main
    with:
      fail-on-findings: true
```

---

## Step 2 — Require the Check in Branch Protection

In your repository settings, under Branch Protection Rules
for your default branch, add `secret-detection` as a required
status check.

This ensures the security check cannot be bypassed by merging
without running it.

---

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `fail-on-findings` | boolean | `true` | Fail the pipeline if secrets are found. Set to `false` only during initial rollout calibration. |

---

## What Happens When a Secret Is Found

The pipeline fails and the merge is blocked.

The finding includes:
- File path and line number
- Rule that matched
- Secret type (not the secret value itself)

**Do not suppress the finding without following the exception
process.** See the exception management section below.

---

## Exception Management

If a finding is a confirmed false positive, you may add a scoped
allowlist entry to your repository's Gitleaks configuration.

Every allowlist entry must include:
- The specific finding being suppressed (not a file or directory)
- A justification comment
- An owner (GitHub username)
- A review date

```toml
# .gitleaks.toml

[[allowlist]]
description = "SHA-256 hash used as test vector in unit tests — not a secret. Owner: @your-username. Review: 2026-12-01"
regexTarget = "match"
regex = '''a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3'''
```

Suppressions scoped to a file or directory are not permitted.

---

## Operational Requirements

Before enabling this control in production, ensure the following
processes exist in your team:

1. A defined owner who triages security findings within 24 hours
2. A rotation runbook for each type of secret your application uses
3. An escalation path for confirmed secret leaks
