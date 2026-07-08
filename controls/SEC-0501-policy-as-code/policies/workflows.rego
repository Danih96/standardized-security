package workflows

import rego.v1

# ---------------------------------------------------------------------------
# Policy 1 — action references must not be mutable branches (T-CICD-010)
#
# Every `uses:` reference is checked. The ref (after the last `@`) is
# accepted only if it is a semantic-version tag (vN[.N...]) or a full
# 40-character commit SHA. A branch reference such as `@main` is denied.
# Local (`./...`) and Docker (`docker://...`) references are out of scope.
# ---------------------------------------------------------------------------

# job-level `uses:` (reusable workflow calls)
all_uses contains u if {
	some job_name
	u := input.jobs[job_name].uses
}

# step-level `uses:` (action references)
all_uses contains u if {
	some job_name
	u := input.jobs[job_name].steps[_].uses
}

is_external(u) if {
	contains(u, "@")
	not startswith(u, "./")
	not startswith(u, "docker://")
}

ref_of(u) := r if {
	parts := split(u, "@")
	r := parts[count(parts) - 1]
}

acceptable_ref(r) if regex.match(`^v[0-9]+(\.[0-9]+)*$`, r)

acceptable_ref(r) if regex.match(`^[0-9a-f]{40}$`, r)

deny contains msg if {
	some u in all_uses
	is_external(u)
	r := ref_of(u)
	not acceptable_ref(r)
	msg := sprintf("uses '%s' pins a mutable ref '%s'; use a version tag (vN) or a full 40-char commit SHA", [u, r])
}

# ---------------------------------------------------------------------------
# Policy 2 — top-level workflows must declare explicit permissions (T-CICD-008)
#
# A workflow triggered by an event must declare a `permissions:` block, or
# GITHUB_TOKEN gets GitHub's broad default permissions. Reusable workflows
# (`on: workflow_call`) are exempt: they inherit permissions from the caller.
#
# Note: the YAML key `on:` is a YAML 1.1 boolean; after parsing it lands
# under the string key "true", not "on". Triggers live under input["true"].
# ---------------------------------------------------------------------------

triggers := input["true"]

is_reusable if {
	triggers.workflow_call
}

deny contains msg if {
	not is_reusable
	not input.permissions
	msg := "top-level workflow has no explicit 'permissions:' block; GITHUB_TOKEN defaults to broad permissions (declare least privilege)"
}
