# SADR-002 — Control-Centric Design Over Tool-Centric Design

## Status
Accepted

## Date
2026-06

---

## Context

Security repositories are commonly organized around tools:
a Gitleaks workflow, a Trivy workflow, a Checkov workflow.
This approach is familiar and easy to bootstrap, but it creates
a structural problem: the tool becomes the unit of reasoning,
not the security requirement it satisfies.

When a tool is replaced or updated, the institutional knowledge
of why the control exists, what threat it mitigates, and what
standards it satisfies is lost or must be reconstructed.
When a new engineer joins, they learn which tools are installed
rather than which threats are being addressed.

A decision was needed on the primary organizing principle of
standardized-security.

Two options were considered:

**Option A — Tool-centric:** the repository is organized around
tools. Each tool has a workflow, configuration, and documentation.
Controls are implicitly defined by what the tools do.

**Option B — Control-centric:** the repository is organized around
security controls. Each control has a specification that defines
the threat, the security principle, and the compliance mapping
independently of any tool. The tool is documented separately as
the current implementation of the control.

---

## Decision

**Option B is adopted.**

Every security capability in standardized-security is defined
first as a control, then implemented with a tool. The control
specification is stable. The implementation guide is replaceable.

The design hierarchy is:

```
Threat
  ↓
Security Control
  ↓
Implementation (current tool)
  ↓
Reusable Workflow
```

The tool is always subordinate to the control. Replacing a tool
does not change the control specification — it produces a new
implementation guide.

---

## Consequences

- Every control in the repository has a stable identifier
  (SEC-XXXX) that remains constant regardless of which tool
  implements it. Compliance mappings and cross-references use
  this identifier, not tool names.

- Control specifications document what must be achieved.
  Implementation guides document how it is currently achieved.
  This separation allows auditors to review security requirements
  independently of implementation details.

- Onboarding a new engineer requires reading the control
  specification before touching the implementation. This is
  intentional — understanding the threat comes before
  understanding the tool.

- Option A was rejected because tool-centric repositories
  accumulate tools without accumulating security knowledge.
  They answer "what tools do we run?" but not "what threats
  do we mitigate?" or "why does this control exist?".

- This decision increases the initial cost of adding a new
  control — a specification must be written before implementation
  begins. This cost is accepted because it produces a repository
  that teaches security engineering rather than tool operation.
