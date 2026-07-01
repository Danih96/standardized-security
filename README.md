# standardized-security

A control-driven Security Engineering platform for all repositories
in the organization.

This repository centralizes reusable security controls, DevSecOps
workflows, and compliance mappings. It is the single security entry
point for all application repositories — exactly as
`standardized-deployment` centralizes deployment logic,
`standardized-security` centralizes security logic.

---

## Philosophy

This is not a tool repository. It is a control repository.

Every capability starts from a threat, not from a tool:

```
Threat
  ↓
Security Control
  ↓
Implementation
  ↓
Reusable Workflow
```

Tools are replaceable. Controls are what matter.

---

## What Exists Today

This repository is at **Milestone 1**. One control is implemented.

| Control | Status | Workflow |
|---|---|---|
| [SEC-0101 — Secret Detection](controls/SEC-0101-secret-detection/spec.md) | Active | `workflows/secret-detection.yml` |

---

## How to Use This Repository

Application repositories consume security controls by calling
reusable workflows:

```yaml
jobs:
  secret-detection:
    uses: your-org/standardized-security/.github/workflows/secret-detection.yml@main
    with:
      fail-on-findings: true
```

See [docs/integration-guide.md](docs/integration-guide.md) for
the full integration guide.

---

## Repository Structure

```
standardized-security/
│
├── controls/                        # Security control specifications
│   └── SEC-0101-secret-detection/
│       ├── spec.md                  # Control specification (stable)
│       ├── implementation.md        # Implementation guide (tool-specific)
│       └── tests/                   # Validation scenarios
│
├── workflows/                       # Reusable GitHub Actions workflows
│   └── secret-detection.yml
│
├── decisions/                       # Security Architecture Decision Records
│   ├── SADR-001-trust-boundary-split.md
│   └── SADR-002-control-centric-design.md
│
├── docs/                            # Documentation
│   └── integration-guide.md
│
└── README.md
```

---

## Architectural Decisions

Key decisions that shape this repository are documented as
Security Architecture Decision Records (SADRs):

- [SADR-001 — Trust Boundary Split](decisions/SADR-001-trust-boundary-split.md)
- [SADR-002 — Control-Centric Design](decisions/SADR-002-control-centric-design.md)

---

## Relationship to Other Standardized Repositories

```
Application Repository
        │
        ├──▶ standardized-security   (build-time security controls)
        │           │
        │           └── Produces: scan results, SBOMs, signatures
        │
        ├──▶ standardized-deployment (deploy-time verification)
        │           │
        │           └── Verifies: artifacts from standardized-security
        │
        └──▶ standardized-backup     (backup and restore)
```

standardized-security produces security artifacts.
standardized-deployment verifies them before deployment.
See [SADR-001](decisions/SADR-001-trust-boundary-split.md)
for the rationale behind this split.

---

## Standards Coverage

Controls in this repository are mapped to:

- ISO 27001:2022
- OWASP CI/CD Security Top 10
- NIS2 (where applicable by sector)
- IEC 62443 (where applicable to OT/ICS projects)
- SLSA

Compliance mappings are documented inside each control
specification. **Implementing controls from this repository
does not make an organization compliant with any standard.**
Organizations achieve compliance. Repositories implement
technical controls that contribute to it.
