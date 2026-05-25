# OKE Troubleshooter Usage Guide

Use the `oke-troubleshooter` skill when you need to diagnose an OCI Kubernetes Engine incident from both the Kubernetes and OCI sides. The skill is designed to collect read-only evidence, correlate related objects, rank likely root causes, and produce remediation steps.

## Before You Start

Verify your local tools point at the right cluster:

```bash
kubectl config current-context
kubectl version --client
oci --version
```

For OCI-layer evidence, the OCI CLI profile must be authenticated and authorized to read OKE, Compute, Network, Load Balancer, Block Volume, IAM, Logging, Monitoring, and Limits data in the target compartment.

If your kubeconfig uses OCI security-token auth and `kubectl` fails with an OCI exec error, renew the OCI session first. Typical symptoms include `This CLI session has expired` and `getting credentials: exec: executable oci failed`. Use `oci session authenticate`, `oci session refresh` when still valid, or the workspace login helper your team provides, such as `oci-login.sh`. This repo does not assume a default cluster or default region during troubleshooting.

## Basic Skill Usage

Start with the symptom in plain English:

```bash
/oke-agent-plugin:oke-troubleshooter "pods stuck Pending in prod namespace"
/oke-agent-plugin:oke-troubleshooter "service web has no external IP"
/oke-agent-plugin:oke-troubleshooter "private OKE API endpoint unreachable"
/oke-agent-plugin:oke-troubleshooter "OCIR ImagePullBackOff unauthorized"
/oke-agent-plugin:oke-troubleshooter "workload identity pod gets NotAuthorized"
```

The skill will ask for missing context such as:

- Cluster name or OCID.
- Region.
- Namespace.
- Pod, Deployment, Service, Ingress, PVC, or Node name.
- Time window, such as `15m` or `1h`.
- Impact level, such as production or non-production.

## How To Pick The Right Object

Start with the object where the symptom appears. Add related objects when you know them.

| Symptom | Provide |
|---|---|
| Pod Pending, CrashLoopBackOff, ImagePullBackOff | Pod and namespace |
| Deployment is slow or unavailable | Deployment, namespace, and optionally a pod |
| Service has no IP or LB is unhealthy | Service and namespace; add one backend pod if known |
| Ingress route or TLS is broken | Ingress and namespace; add backend Service if known |
| PVC is Pending or volume attach fails | PVC and namespace; add the consuming pod if known |
| Node is NotReady or unstable | Node; add one affected pod if known |
| Multus, GVA, or pod sandbox failure | Pod, namespace, and any related NetworkAttachmentDefinition details |

## What The Skill Does

1. **Preflight and discovery**
   - Confirms the active kube context.
   - Resolves the OKE cluster OCID from kubeconfig when possible.
   - Uses the explicit region for all OCI CLI calls.
   - Enforces single-cluster scope.

2. **Symptom triage**
   - Maps the symptom to diagnostic domains such as scheduling, node health, DNS, CNI/IPAM, autoscaler, Load Balancer, Ingress, OCIR, Workload Identity, storage, or control plane.

3. **OCI object correlation**
   - Builds a read-only graph connecting Kubernetes objects to OCI resources.
   - Example graph paths:

```text
pod/default/web-0 -> node/node-a -> instance/ocid1.instance...
service/default/web -> loadbalancer/ocid1.loadbalancer...
pvc/default/data -> pv/pvc-123 -> volume/ocid1.volume...
```

4. **Evidence collection**
   - Runs focused read-only `kubectl` and `oci` commands.
   - Uses helper scripts for OKE add-ons, pod networking, autoscaler, DNS, Ingress, private endpoint, OCIR image pulls, Workload Identity, incident timeline, and object correlation.

5. **Hypothesis ranking**
   - Ranks likely root causes with evidence.
   - Prefers causes supported by explicit Kubernetes-to-OCI graph edges.

6. **Report**
   - Summarizes findings, anomalies, confidence, remediation commands, and evidence gaps.

## Direct Object Graph Usage

Use the object correlator directly when you want a graph without a full troubleshooting session.

```bash
./scripts/oke-object-correlator.sh \
  --namespace <namespace> \
  --cluster-id <cluster_ocid> \
  --compartment-id <compartment_ocid> \
  --region <region> \
  --pod <pod_name> \
  --service <service_name>
```

For a storage issue:

```bash
./scripts/oke-object-correlator.sh \
  --namespace <namespace> \
  --cluster-id <cluster_ocid> \
  --compartment-id <compartment_ocid> \
  --region <region> \
  --pvc <claim_name> \
  --pod <pod_name>
```

The output includes:

- `graph.kubernetes`: Kubernetes objects found.
- `graph.oci`: OCI resources found.
- `graph.edges`: relationships between objects.
- `findings`: useful correlations.
- `anomalies`: broken or suspicious links.
- `fallback_used`: whether any command failed or had partial coverage.

## Reading The Graph

A healthy Service-to-LB path might look like:

```text
Service/neuvector-service-webui
  -> OCI Load Balancer ACTIVE
  -> subnet ocid1.subnet...

Pod/neuvector-manager
  -> Node 10.0.5.128
  -> OCI Compute instance
```

Use the graph to decide where to investigate next:

- If the Service has no endpoints, focus on selectors, pod readiness, and EndpointSlices.
- If the Load Balancer is not healthy, focus on backend health, node ports, NSGs, and subnets.
- If a pod maps to a NotReady node, focus on node health, instance lifecycle, kubelet, and CNI.
- If a PVC maps to a volume with an attachment issue, focus on CSI and Block Volume attachment state.

## Safety Rules

- The default troubleshooting flow is read-only.
- The skill may auto-run read-only evidence commands.
- It must ask before every remediation or mutating action, including `kubectl apply`, `kubectl patch`, `kubectl annotate`, `kubectl delete`, restarts, scaling, drains, privileged node diagnostics, OCI update/create/delete operations, and LB logging enablement.
- Approval must be for the exact command or action shown in the current session. Approval for one command does not approve follow-up mutations.
- Node Doctor diagnostics use `kubectl debug` and require explicit confirmation.

## Common Examples

Pod scheduling:

```bash
/oke-agent-plugin:oke-troubleshooter "pods are Pending in namespace payments"
```

Service or Load Balancer:

```bash
/oke-agent-plugin:oke-troubleshooter "service neuvector-service-webui load balancer is unhealthy"
```

DNS:

```bash
/oke-agent-plugin:oke-troubleshooter "pods cannot resolve web.default.svc.cluster.local"
```

Multus or GVA:

```bash
/oke-agent-plugin:oke-troubleshooter "FailedCreatePodSandBox with Multus and ipvlan"
```

Workload Identity:

```bash
/oke-agent-plugin:oke-troubleshooter "pod gets NotAuthorized when calling OCI API"
```

## Troubleshooting The Troubleshooter

- If `kubectl` fails with an OCI exec error, renew your OCI security-token session.
- If OCI evidence is missing, verify the profile, region, compartment permissions, and `--auth security_token` when applicable.
- If the object graph is sparse, rerun with more selectors, such as both `--service` and `--pod`.
- If only Kubernetes evidence is available, the skill can still rank Kubernetes-side causes but should mark OCI visibility as partial.
