# Skill 2 Implementation Notes — `/oke-troubleshooter`

## Overview
`/oke-troubleshooter` augments the plugin with an operational runbook that correlates Kubernetes-level symptoms with Oracle Cloud Infrastructure (OCI) telemetry. It complements the existing cluster generator by answering “what went wrong?” when workloads become unhealthy.

The skill is defined in `skills/oke-troubleshooter/SKILL.md` and relies on supporting references plus two dedicated subagents.

## Architecture Summary

| Component | Purpose | File |
|-----------|---------|------|
| Skill spec | Five-phase troubleshooting dialogue and state management | `skills/oke-troubleshooter/SKILL.md` |
| Symptom→domain heuristics | Maps user-reported keywords to diagnostic domains (including application performance) | `skills/oke-troubleshooter/symptom-triage.md` |
| Evidence recipes | Curated `kubectl` and `oci` commands per domain | `skills/oke-troubleshooter/evidence-collectors.md` |
| Resource correlation | Quick lookups from K8s objects to OCI OCIDs | `shared/oci-resource-map.md` |
| Haiku subagent | Executes command batches, normalizes findings | `agents/oke-evidence-collector.md` |
| Sonnet subagent | Scores hypotheses, recommends remediation | `agents/oke-hypothesis-analyst.md` |

The plugin manifest version was bumped to `0.2.0` in `.claude-plugin/plugin.json` to advertise the new capability. `README.md` documents the workflow and verification scenarios.

## Execution Flow

1. **Input & Preflight**  
   - Parse symptom from invocation arguments.  
   - Gather namespace, compartment, and severity details.  
   - Run `kubectl version --client` and `oci --version` to detect tooling availability, setting fallback flags when a CLI is missing.

2. **Symptom Triage**  
   - Consult `symptom-triage.md` to propose diagnostic domains (e.g., Pod Runtime, Networking, Storage, Application Performance).  
   - Present rationale and follow-up questions to refine scope.

3. **Evidence Collection**  
   - Build per-domain command batches using `evidence-collectors.md` and the OCI mapping cheatsheet (for performance cases, include deployment history, autoscaler status, metrics queries).  
   - Invoke the Haiku subagent (`oke-evidence-collector`) with `context: fork`.  
   - Collector returns structured JSON containing findings, trimmed raw snippets, anomalies, and fallback usage.

4. **Hypothesis Ranking**  
   - Aggregate evidence payload and invoke the Sonnet subagent (`oke-hypothesis-analyst`).  
   - Analyst outputs 1–3 hypotheses with scores (0–10), evidence citations, remediation commands, and prevention guidance.  
   - Low-confidence entries request additional evidence when necessary.

5. **Report & Next Steps**  
   - Skill renders a summary table, remediation command blocks, prevention bullets, and any limitations (e.g., OCI CLI unavailable).  
   - Offers rerun options for other namespaces or deeper domain dives.

All phases adhere to the shared error contract: exit code `0` for success, `1` for expected issues (missing CLI, permission errors), and `2` for unexpected failures, with JSON emitted on stderr.

## Usage Guidelines

### Prerequisites
- `kubectl` configured against the target OKE cluster.  
- OCI CLI authenticated (`oci setup config`) for infrastructure-layer evidence.  
- Operator permissions to read Kubernetes objects and relevant OCI resources.

### Invocation Examples
```bash
/oke-agent-plugin:oke-troubleshooter "pods stuck Pending in prod namespace"
/oke-agent-plugin:oke-troubleshooter "service payments-lb has no IP us-phoenix-1"
/oke-agent-plugin:oke-troubleshooter "cluster api timing out"
```
Override defaults (namespace, timeframe) by responding to the Phase 0 prompts.

### Expected Output
- Ranked hypotheses with confidence scores.  
- Command snippets to remediate each issue (e.g., `kubectl describe`, `oci ce node-pool update`).  
- Preventative recommendations (autoscaling, quota alarms, policy adjustments).  
- Warnings when evidence is partial due to missing tools or permission limits.

## Verification Checklist
- **ImagePullBackOff:** Inject a bad image tag; confirm the top hypothesis references the FailedScheduling/ErrImagePull evidence and remediation suggests credential or tag fixes.
- **Load Balancer Pending:** Misconfigure subnets/NSGs; expect networking hypothesis citing OCI load balancer lifecycle and security rules.
- **Deployment Slowdown:** Use a traffic generator to induce high latency on Deployment `nginx`; `/oke-troubleshooter "deployment nginx slow in prod"` should surface the Application Performance domain with replica/mismatch findings and remediation (scale out, add HPA, inspect backend latency).
- **PVC Pending:** Exhaust Block Volume quota; verify storage hypothesis references CSI controller logs and OCI quota metrics.
- **Missing OCI CLI:** Temporarily hide `oci`; report should flag the gap yet still provide Kubernetes-focused insight.
- **Healthy Cluster:** Supply a benign symptom; analyst returns low scores with monitoring advice.

Document testing outcomes in a project journal or future automated suite as needed.
