# Threat Model Template

## How to use this template

Copy this file into your application repository and fill in each
section for your specific application and deployment context.

Application threat models belong in the application repository,
not in `standardized-security`. This repository provides the
methodology and the infrastructure threat model only.
`standardized-security` does not own application risk decisions.

Each section below contains brief instructions. Remove the
instructions when you fill in the section. Keep the structure.

---

## Metadata

**Application:** [Name of the application or service]
**Repository:** [GitHub repository URL]
**Owner:** [Team or individual responsible for this threat model]
**Status:** Draft | Review | Active
**Last Updated:** [YYYY-MM]
**Reviewed by:** [Name or team who reviewed this threat model]

---

## Scope

Describe what is in scope and what is out of scope for this threat
model. Identify the version or deployment context this model applies
to. Note any assumptions about the environment — for example,
"assumes deployment on Kubernetes in a private VPC" or "covers the
public API only, not the internal admin interface."

---

## 1. Assets

List the assets that this application is responsible for protecting.
Focus on what an attacker would want to access, steal, or destroy.

| Asset | Description |
|---|---|
| [Asset name] | [What it is, why it is sensitive, who it belongs to] |

Common asset categories for application threat models:

- User data and personal information
- Authentication credentials and session tokens
- Application secrets (database passwords, API keys, signing keys)
- Business logic or intellectual property
- Audit logs and compliance records
- Downstream systems accessible from this application

---

## 2. Trust Boundaries

Describe the boundaries across which data or control flows, and
what changes when a request crosses each boundary.

For each boundary, answer: what is trusted on each side, and what
is the risk if an attacker reaches one side?

Common trust boundaries for web applications:

- User browser → public API
- Public API → internal services
- Internal services → database
- Internal services → third-party APIs
- CI runner → production environment

---

## 3. Threat Actors

Describe who might attack this application and what they are capable
of. Use specific actors, not generic categories. For each actor,
note their likely motivation and their assumed level of access at
the start of an attack.

| Actor | Motivation | Initial access |
|---|---|---|
| [Actor name] | [What they want] | [What they start with] |

---

## 4. Threats

Document each threat using the structure below. Assign a unique ID
using the prefix `T-[APP]-` where `[APP]` is a short identifier for
your application (for example, `T-PAYMENTS-001`).

---

### T-[APP]-001 — [Short descriptive name]

**Actor:** [Which threat actor from §3]

**Attack vector:**
[How the attack enters the system. Be specific — describe the
exact path from the attacker's initial position to the affected
asset. One paragraph.]

**Impact:**
[What damage results if the attack succeeds. Include the
confidentiality, integrity, and availability dimensions where
relevant. One paragraph.]

**Affected assets:**
[Which assets from §1 are compromised or degraded]

**Mitigating control:**
[Which SEC-XXXX control from standardized-security addresses this,
or TBD if no control exists yet. If the mitigation is
application-specific rather than platform-level, describe it here.]

---

[Repeat the block above for each threat.]

---

## 5. Residual Risk Summary

List all threats and their current mitigation status. This table
is the output of the threat model — it shows what is protected,
what will be protected, and what is currently accepted as residual
risk.

| Threat ID | Name | Mitigated by |
|---|---|---|
| T-[APP]-001 | [Name] | [SEC-XXXX / Application control / No planned control] |

Threats with no planned control must be explicitly accepted by the
application owner. Acceptance is not permanent — residual risk must
be reviewed when the threat model is updated.

---

## 6. Review Notes

Record the outcome of each review, including who reviewed, what
changed, and whether any previously accepted risks were re-evaluated.

| Date | Reviewer | Notes |
|---|---|---|
| [YYYY-MM] | [Name or team] | [What was reviewed or changed] |
