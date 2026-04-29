# Implementation Notes — OKE Troubleshooter

This document records how the `oke-troubleshooter` skill is structured and how to extend it.

## Scope
The troubleshooter focuses on:
- Symptom-driven triage across Kubernetes and OCI layers
- Evidence collection via curated `kubectl` and `oci` commands
- Hypothesis ranking with remediation guidance
- Local execution first, with optional agent acceleration when the runtime supports it
- OKE-specific add-on, CNI/IPAM, autoscaler, DNS, ingress, private endpoint, OCIR, workload identity, and incident timeline paths

## Current Implementation
- **Skill spec**: `skills/oke-troubleshooter/SKILL.md`
- **Triage map**: `skills/oke-troubleshooter/symptom-triage.md`
- **Evidence recipes**: `skills/oke-troubleshooter/evidence-collectors.md`
- **Shared mapping**: `shared/oci-resource-map.md`
- **Discovery helper**: `scripts/oke-discover.sh`
- **Optional agents**: `agents/oke-evidence-collector.md`, `agents/oke-hypothesis-analyst.md`, `agents/oke-lb-log-collector.md`
- **OKE add-on helper**: `scripts/oke-addon-health.sh`
- **Pod networking helper**: `scripts/oke-pod-network-check.sh`
- **Autoscaler helper**: `scripts/oke-autoscaler-check.sh`
- **DNS helper**: `scripts/oke-dns-check.sh`
- **Ingress helper**: `scripts/oke-ingress-check.sh`
- **Private endpoint helper**: `scripts/oke-private-endpoint-check.sh`
- **OCIR image pull helper**: `scripts/oke-ocir-image-pull-check.sh`
- **Workload identity helper**: `scripts/oke-workload-identity-check.sh`
- **Incident timeline helper**: `scripts/oke-incident-timeline.sh`

## Discovery Flow (New)
1. User provides **cluster name** (or OCID).
2. `scripts/oke-discover.sh` resolves cluster OCID from `~/.kube/config`.
3. Region defaults are pulled from `~/.oci/config`.
4. `oci ce cluster get --cluster-id <ocid>` retrieves compartment and K8s version.
5. The skill auto-populates `cluster_ocid`, `compartment_ocid`, and `region`.
6. Prompt only for missing context (namespace, time window, resource names).

## Execution Model
- The parent skill remains authoritative and must be able to complete the investigation without spawning agents.
- Optional agents are accelerators only. If delegation is unavailable or fails, the skill runs the same evidence commands locally and ranks hypotheses with the built-in scoring rubric.
- Control-plane checks now use `kubectl get --raw='/readyz?verbose'` and `kubectl get --raw='/livez?verbose'` instead of the deprecated `kubectl get cs`.

## Assumptions
- `kubectl` is configured to access the target cluster.
- OCI CLI is installed when OCI-layer evidence is needed.

## Known Gaps
- No automated parsing of kubeconfig context names into region; relies on OCI discovery.
- No built-in caching; repeated runs re-discover context.
- Ingress, OCIR, private endpoint, and workload identity helpers collect evidence but do not yet perform full object graph correlation or IAM policy simulation.

## Follow-up Enhancements
- Add optional caching of discovery output per session.
- Add explicit region mismatch checks between kubeconfig and OCI cluster data.
- Add deeper object graph correlation for OCI native ingress, OCIR image pulls, private endpoint reachability, and workload identity policy simulation.
