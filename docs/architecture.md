# Architecture

How `standardized-security` is designed and why.

---

## Purpose

`standardized-security` centralizes reusable security controls for
all repositories in the organization. It is the single security
entry point for application repositories — exactly as
`standardized-deployment` centralizes deployment logic,
`standardized-security` centralizes security logic.

This is not a tool repository. It is a control repository.
Every capability starts from a threat, not from a tool:

```
Threat
  ↓
Security Control
  ↓
Implementation (current tool)
  ↓
Reusable Workflow
```

Tools are replaceable. Controls are long-lived.

---

## Design Principles

**Control-driven, not tool-driven.**
Controls are defined independently of their implementation.
Replacing a tool does not change a control specification.

**Fail closed by default.**
Every control blocks the pipeline on a finding.
Fail-open behavior requires an explicit, documented, time-limited
exception. It is never the default.

**Shift left.**
Controls are applied at the earliest effective enforcement point
in the SDLC — typically pre-merge in CI.

**Small iterations.**
One control at a time. One milestone at a time.
No abstraction is introduced until there is a proven need for it.

---

## Repository Structure

```
standardized-security/
│
├── controls/                        # One directory per control
│   └── SEC-XXXX-control-name/
│       ├── spec.md                  # Control specification (stable)
│       ├── implementation.md        # Implementation guide (evolves)
│       └── tests/                   # Validation scenarios
│
├── .github/
│   └── workflows/                   # Reusable GitHub Actions workflows
│
├── decisions/                       # Security Architecture Decision Records
│
├── docs/                            # Platform documentation
│
└── README.md
```

### Controls

Each control has a stable identifier (`SEC-XXXX`) and two documents:

- **spec.md** — the threat, security principle, assets protected,
  enforcement point, failure mode, and compliance mapping.
  This document does not mention tools. It changes rarely.

- **implementation.md** — the current tool, configuration,
  rationale for tool selection, known limitations, and
  validation procedure. This document evolves with tooling.

Control ID ranges are reserved by category:

| Range | Category |
|---|---|
| SEC-0100–0199 | Secret Management |
| SEC-0200–0299 | Dependency Management |
| SEC-0300–0399 | Container Security |
| SEC-0400–0499 | Supply Chain & Signing |
| SEC-0500–0599 | Infrastructure as Code |
| SEC-0600–0699 | Policy as Code |
| SEC-0700–0799 | Compliance & Evidence |

### Security Architecture Decision Records (SADRs)

Architectural decisions that are expensive to reverse are
documented as SADRs. Tool selection is not an SADR.
The decision to use a specific enforcement point, failure mode,
or integration pattern is an SADR.

---

## Relationship to Other Platform Repositories

```
Application Repository
        │
        ├──▶ standardized-security   (build-time controls)
        │           │
        │           └── Produces: scan results, SBOMs,
        │                         signatures, attestations
        │
        ├──▶ standardized-deployment (deploy-time verification)
        │           │
        │           └── Verifies: artifacts from
        │                         standardized-security
        │
        └──▶ standardized-backup     (backup and restore)
```

`standardized-security` produces security artifacts.
`standardized-deployment` verifies them before deployment.

See [SADR-001](../decisions/SADR-001-trust-boundary-split.md)
for the rationale behind this split.

---

## Consumer Interface

This section defines the stable API surface of the platform.
Application repositories may depend on everything in this section.
Everything outside this section is an implementation detail.

### Stable Interface

Consumers may depend on:

- **Workflow file paths and names**
  `workflows/<control-name>.yml` — stable once published.
  Renamed workflows are versioned as breaking changes.

- **Input parameter names, types, and defaults**
  Defined per workflow in its `on.workflow_call.inputs` block.
  Defaults are always secure — consumers with no configuration
  get the most secure behavior.

- **Output parameter names and types**
  Defined per workflow in its `on.workflow_call.outputs` block.

- **Output artifact formats**
  Scan results are produced in SARIF format.
  All other artifact formats are documented per control.

- **GitHub Actions status check names**
  The job name used in branch protection rules is stable.
  Renaming a job is a breaking change.

- **Failure semantics**
  A workflow fails (non-zero exit) when a control detects a
  violation or when the control cannot run. A workflow that
  cannot run is not a passing workflow.

### Implementation Details

Consumers must not depend on:

- Which tool implements a given control
- Internal workflow structure or step names
- Log output format or content
- Specific detection patterns, rules, or thresholds
- Performance characteristics

### Versioning

Reusable workflows follow semantic versioning via git tags.

```yaml
# Recommended — pin to major version
uses: your-org/standardized-security/.github/workflows/secret-detection.yml@v1

# Supported during early development only
uses: your-org/standardized-security/.github/workflows/secret-detection.yml@main
```

| Change type | Version increment |
|---|---|
| Breaking change to stable interface | Major (`v1` → `v2`) |
| New input with a default value | Minor |
| Bug fix, tool update, internal change | Patch |

`@main` is supported for early adopters during initial development.
Once `v1` is tagged, stable consumers should migrate to `@v1`.

### Deprecation Policy

Deprecated versions are announced via repository releases.
A minimum of 90 days notice is given before a version is removed.
At most two major versions are supported simultaneously.

---

## Non-Goals

This repository will not:

- Own application-specific threat models or risk decisions
- Make organizations compliant with any standard
- Replace a secrets management system
- Provide runtime security monitoring
- Enforce security policy outside the CI/CD pipeline
- Operate as a security information and event management (SIEM) system

---

## Further Reading

- [SADR-001 — Trust Boundary Split](../decisions/SADR-001-trust-boundary-split.md)
- [SADR-002 — Control-Centric Design](../decisions/SADR-002-control-centric-design.md)
- [Integration Guide](integration-guide.md)
- [Roadmap](roadmap.md)
