# SADR-001 — Trust Boundary Split Between standardized-security and standardized-deployment

## Status
Accepted

## Date
2026-06

---

## Context

The standardized-security repository produces security artifacts
as part of the CI pipeline: scan results, SBOMs, image signatures,
and attestations. The standardized-deployment repository is
responsible for deploying application workloads to target environments.

Several security controls span both concerns. Image signing, for
example, involves producing a signature (a security action) and
verifying it before deployment (a deployment gate). A decision was
needed on where each responsibility lives.

Three options were considered:

**Option A:** standardized-security owns the full lifecycle of every
security artifact, including verification at deploy time.
standardized-deployment calls into standardized-security for
verification.

**Option B:** standardized-security owns production of security
artifacts. standardized-deployment owns verification of those
artifacts before deployment. Each repository is responsible for
its side of the trust boundary.

**Option C:** standardized-deployment absorbs security verification
as an internal concern, with no formal dependency on
standardized-security.

---

## Decision

**Option B is adopted.**

standardized-security is responsible for:
- Running security controls during the build and pre-merge phases
- Producing security artifacts (scan results, SBOMs, signatures,
  attestations)

standardized-deployment is responsible for:
- Verifying security artifacts produced by standardized-security
  before deployment proceeds
- Rejecting deployments that do not satisfy verification requirements

This creates an explicit trust boundary: standardized-security
produces, standardized-deployment verifies. The boundary maps
cleanly to where trust changes in the pipeline — from the build
environment to the deployment environment.

---

## Consequences

- Application repositories have two explicit dependencies:
  one on standardized-security (build-time controls) and one
  on standardized-deployment (deploy-time verification).
  This makes the security posture of a deployment visible
  and auditable.

- standardized-deployment has an implicit dependency on
  standardized-security for any deployment requiring verified
  artifacts. This dependency is accepted and made explicit
  in the integration documentation.

- Changing the verification requirements for deployment requires
  a change in standardized-deployment, not in
  standardized-security. This separation of concerns allows
  each repository to evolve independently.

- Option A was rejected because it would make
  standardized-deployment dependent on standardized-security
  at runtime, creating a coupling that complicates deployment
  operations independently of security concerns.

- Option C was rejected because it would hide security
  verification inside deployment logic, making it invisible
  to security reviews and difficult to enforce consistently.
