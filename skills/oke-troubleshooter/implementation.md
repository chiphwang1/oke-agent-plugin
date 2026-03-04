# Implementation Notes — OKE Troubleshooter

This document records how the `oke-troubleshooter` skill is structured and how to extend it.

## Scope
The troubleshooter focuses on:
- Symptom-driven triage across Kubernetes and OCI layers
- Evidence collection via curated `kubectl` and `oci` commands
- Hypothesis ranking with remediation guidance

## Current Implementation
- **Skill spec**: `skills/oke-troubleshooter/SKILL.md`
- **Triage map**: `skills/oke-troubleshooter/symptom-triage.md`
- **Evidence recipes**: `skills/oke-troubleshooter/evidence-collectors.md`
- **Shared mapping**: `shared/oci-resource-map.md`
- **Discovery helper**: `scripts/oke-discover.sh`

## Discovery Flow (New)
1. User provides **cluster name** (or OCID).
2. `scripts/oke-discover.sh` resolves cluster OCID from `~/.kube/config`.
3. Region defaults are pulled from `/Users/chipinghwang/.oci/config`.
4. `oci ce cluster get --cluster-id <ocid>` retrieves compartment and K8s version.
5. The skill auto-populates `cluster_ocid`, `compartment_ocid`, and `region`.
6. Prompt only for missing context (namespace, time window, resource names).

## Assumptions
- `kubectl` is configured to access the target cluster.
- OCI CLI is installed when OCI-layer evidence is needed.

## Known Gaps
- No automated parsing of kubeconfig context names into region; relies on OCI discovery.
- No built-in caching; repeated runs re-discover context.

## Follow-up Enhancements
- Add optional caching of discovery output per session.
- Add explicit region mismatch checks between kubeconfig and OCI cluster data.
