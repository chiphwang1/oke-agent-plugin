# `/oke-troubleshooter` — Symptom Triage Reference

Use this table to map the user's symptom description to diagnostic domains. Start with the listed prompts to confirm context before collecting evidence. Domains can be added or removed based on the user's answers.

| Symptom keywords | Primary domains | Clarifying questions |
|------------------|-----------------|----------------------|
| `ImagePullBackOff`, `ErrImagePull`, failed registry auth | Pod runtime, IAM/RBAC | Namespace? Image registry (OCIR/3rd-party)? Recently rotated secrets? |
| `Pending` pods, `Unschedulable`, `Insufficient` resources | Pod scheduling, Node health | Which namespace/workload? Any recent cluster scale events? Require specific node labels/shapes? |
| `CrashLoopBackOff`, `OOMKilled`, high restart counts | Pod runtime, Node health | First failure timestamp? Any recent config/secret changes? Container logs already reviewed? |
| `Node NotReady`, `NodeReady=False`, `Kubelet stopped posting` | Node health, Control plane | Specific node pool or AD? Recent maintenance events or OCI alarms? |
| Slow responses, high latency, throughput drop, users reporting "app is slow" | Application performance, Pod runtime, Networking/CNI/LB, Dependency path | Which Deployment/Service? Baseline latency? Any recent rollout or config change? HPA or autoscaling enabled? Which downstream dependencies are called on-request? |
| Service has no LB IP, `Pending` load balancer, ingress failing | Networking/CNI/LB, OCI infra | Public or private load balancer? Correct subnets/NSGs applied? Any recent network policy updates? |
| Timeout reaching API server, `x509` errors, control-plane degraded | Control plane, Networking | Using public or private endpoint? Any recent API endpoint visibility changes? |
| PVC stuck `Pending`, volume attachment failures, CSI errors | Storage, Node health | Block Volume or File Storage? Specific availability domain? Existing quota alarms? |
| OCI limits exceeded, `TooManyRequests`, throttling | OCI infra, Control plane | Which service returned the error? Was there a recent surge in provisioning? |
| `Forbidden`, RBAC denial, service account issues | IAM/RBAC, Pod runtime | Which user/service account? Recent policy updates? Using workload identity? |

### Additional triage prompts
- Confirm target namespace, cluster region, and compartment when not provided.
- Ask whether the symptom is impacting production or a lower environment to set urgency.
- Capture desired timeframe for evidence (`last 15m`, `last 1h`, etc.) to scope CLI queries.
- For latency incidents, capture dependency-path context:
  - Request entrypoint (ingress/API/worker trigger).
  - Downstream services called by the target deployment (internal and external).
  - Critical-path dependencies versus optional/background calls.
  - If known, end-to-end p95/p99 baseline and rough per-hop latency budget.
