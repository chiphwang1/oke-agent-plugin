# OKE Agent Plugin

A Claude Code plugin for OCI Kubernetes Engine (OKE) on Oracle Cloud Infrastructure (OCI).
The bundled skills also work with Codex when installed as local Codex skills.
Fills the gap in AI-assisted Kubernetes tooling.

## Codex Support

This repo is also Codex-friendly:

- `AGENTS.md` gives Codex repository-specific working rules, validation commands, and OKE safety guardrails.
- `skills/AGENTS.md` gives nested guidance for editing skill packages.
- `.codex-plugin/plugin.json` exposes this repository as a Codex plugin and points Codex at `./skills/`.
- `.claude-plugin/plugin.json` remains in place for Claude Code compatibility.

Use the repo with Codex from the repository root. For local validation, run:

```bash
bash tests/scripts-smoke.sh
git diff --check
```

Live OCI/OKE validation still requires a valid OCI CLI session and kubeconfig. The smoke tests are intentionally offline and mocked so Codex cloud or CI can run them without access to a tenancy.

## Skills

**New DPDK/SR-IOV coverage:** the troubleshooting and multihome skills now include evidence-driven checks for OKE workloads that combine DPDK, Multus, SR-IOV device-plugin resources, Mellanox `mlx5`, `vfio-pci`, RDMA/verbs devices, and hugepages. The workflow keeps Kubernetes resource allocation, Multus `NetworkAttachmentDefinition` attachment, driver binding, and DPDK application configuration as separate diagnostic facts.

**Implementation Notes:**
- `skills/oke-cluster-generator/implementation.md`
- `implementation.md` (Skill 2 — `/oke-troubleshooter`)
- `skills/oke-gva-deployer/implementation.md`

### `/oke-agent-plugin:oke-cluster-generator`

Guides you through a structured, conversational workflow to generate a production-ready OKE Terraform stack and OCI Resource Manager (ORM) schema.

**Phases:**
1. **Pre-flight** — OCI CLI auth, tenancy OCID and home region discovery, region and compartment selection
2. **Discovery** — 7-domain guided questionnaire:
   - D1 Cluster Fundamentals (workload type, K8s version, API visibility, cluster type)
   - D2 Networking (VCN, CNI, access infra, gateways, RDMA/RoCE)
   - D3 Node Pools (shape family, scaling strategy, boot volume, OS image)
   - D4 Storage (Block Volume CSI, FSS, Object Storage)
   - D5 Security & Access (IAM policies, encryption, Workload Identity)
   - D6 Add-ons & Observability (OKE managed add-ons, OCI logging/monitoring, GPU metrics)
   - D7 ORM Schema Preferences (audience, variable groups, validation)
3. **Architecture Summary** — confirm all choices before code generation
4. **Code Generation** — `main.tf`, `variables.tf`, `outputs.tf`, `provider.tf`, `terraform.tfvars.example`, `schema.yaml`
5. **Iteration** — revise any domain, cascade updates, regenerate

**Prerequisites:**
- OCI CLI installed and configured (`oci setup config`)
- Read access to IAM, CE (Container Engine), Compute, Network, KMS, and Limits

**Usage:**

```bash
# Full questionnaire
/oke-agent-plugin:oke-cluster-generator

# With pre-filled arguments (workload-type, region, cluster-name)
/oke-agent-plugin:oke-cluster-generator ai/ml us-ashburn-1 prod-cluster
/oke-agent-plugin:oke-cluster-generator hpc us-frankfurt-1
```

### `/oke-agent-plugin:oke-troubleshooter`

Performs end-to-end diagnosis of OKE incidents by correlating Kubernetes symptoms with OCI infrastructure signals.

**Phases:**
1. **Input & Preflight** — capture symptom, namespace, and verify `kubectl`/`oci` availability.
2. **Symptom Triage** — map keywords to diagnostic domains (pod runtime, OKE add-ons, CNI/IPAM, DNS, autoscaler, networking, storage, control plane, IAM, OCI limits).
3. **Evidence Collection** — run curated command batches locally by default; use the optional evidence-collector agent only when delegation is available.
4. **Hypothesis Ranking** — rank causes locally by default; use the optional analyst agent only when delegation is available.
5. **Report & Next Steps** — present remediation commands, prevention guidance, and note any evidence gaps.

**OKE-specific coverage:**
- kube-system add-on health: CoreDNS, OCI CNI, CSI, metrics, and daemonset/deployment readiness
- Pod networking: OCI CNI/IPAM, Multus, NADs, pod sandbox creation, and secondary-interface failures
- DPDK/SR-IOV: Mellanox `mlx5`, `vfio-pci`, RDMA/verbs, hugepage, and Multus attachment evidence
- Cluster autoscaler and node-pool scaling: Pending pods, FailedScheduling, scale-up refusal, node pool limits
- DNS and service discovery: CoreDNS, Service/EndpointSlice state, and pod-local lookups
- Ingress, private endpoint, OCIR image pulls, workload identity, and incident timeline evidence

**Prerequisites:**
- `kubectl` configured for the target cluster.
- OCI CLI authenticated (`oci setup config`) when OCI-layer evidence is required.

**Usage:**

```bash
/oke-agent-plugin:oke-troubleshooter "pods stuck Pending in prod namespace"
/oke-agent-plugin:oke-troubleshooter "service payments-lb has no IP us-phoenix-1"
/oke-agent-plugin:oke-troubleshooter "customer is indicating poor performance for deployment"
```

### `/oke-agent-plugin:oke-gva-deployer`

Deploys OKE node pools configured with Generic VNIC Attachment (GVA), including secondary VNIC profiles, Application Resource labels, and validation guidance.

**Highlights:**
- Auto-discovers cluster context from kubeconfig and OCI config
- Lists VCNs and subnets for selection
- Lists OKE images for the cluster’s Kubernetes version and selected node-shape compatibility
- Uses one-by-one numeric menus, including repeat prompts for additional secondary VNIC profiles
- Validates secondary VNIC subnets are IPv4-only before create
- Generates a ready-to-run `oci ce node-pool create` command
- Provides a test Deployment manifest for GVA validation

**Prerequisites:**
- OCI CLI installed and configured
- `kubectl` configured for the target cluster

**Usage:**

```bash
/oke-agent-plugin:oke-gva-deployer
```

### `/oke-agent-plugin:oke-multihome-deployer`

Deploys and validates Multus-based multi-home pods on an OKE node pool that already has GVA secondary VNIC profiles attached.

**Highlights:**
- Auto-discovers OKE cluster, node pool, placement subnet, and secondary VNIC subnet data
- Generates Multus `NetworkAttachmentDefinition` resources for default and secondary pod networks
- Generates pinned netshoot test pods using fully qualified images
- Verifies pod `network-status`, `eth0`/`net1` interfaces, and pod-to-pod connectivity over `net1`
- Includes troubleshooting guidance for missing `ipvlan`, CRI-O short-name rejection, OCI IPAM state, Multus pod sandbox failures, and DPDK/SR-IOV Mellanox `mlx5` validation

**Prerequisites:**
- `kubectl` configured for the target cluster
- OCI CLI authenticated when discovery needs OCI-layer node pool and subnet data
- Existing GVA-enabled node pool; use `/oke-agent-plugin:oke-gva-deployer` first if the node pool still needs secondary VNIC profiles

**Usage:**

```bash
/oke-agent-plugin:oke-multihome-deployer
```

## Project Structure

```
oke-agent-plugin/
├── AGENTS.md                              # Codex repo instructions
├── .claude-plugin/
│   └── plugin.json                         # Plugin manifest
├── .codex-plugin/
│   └── plugin.json                         # Codex plugin manifest
├── agents/
│   ├── oke-evidence-collector.md           # Haiku subagent for command execution
│   ├── oke-hypothesis-analyst.md           # Sonnet subagent for hypothesis scoring
│   ├── oke-lb-log-collector.md             # Haiku subagent for LB logging evidence
├── settings.json                           # Claude Code settings
├── skills/
│   ├── AGENTS.md                           # Codex skill-editing instructions
│   ├── oke-cluster-generator/
│   │   ├── SKILL.md                        # 4-phase orchestration (Pre-flight → Discovery → Summary → Generate)
│   │   ├── reference.md                    # terraform-oci-oke variable catalog (D1–D6 mapping)
│   │   └── output-templates/
│   │       ├── terraform.md                # provider.tf, main.tf, outputs.tf templates
│   │       └── schema.md                   # ORM schema.yaml structure + conditional visibility patterns
│   ├── oke-troubleshooter/
│   │   ├── SKILL.md                        # 5-phase troubleshooting workflow
│   │   ├── symptom-triage.md               # Symptom → domain decision table
│   │   └── evidence-collectors.md          # Command recipes per diagnostic domain
│   ├── oke-gva-deployer/
│   │   ├── SKILL.md                        # GVA node pool workflow
│   │   ├── USAGE.md                        # How to use the GVA skill and scripts
│   │   ├── implementation.md               # Skill implementation notes
│   │   └── references/
│   │       └── gva.md                      # Feature summary and constraints
│   └── oke-multihome-deployer/
│       ├── SKILL.md                        # Multus multi-home pod workflow after GVA node pool setup
│       ├── agents/
│       │   └── openai.yaml                 # Skill UI metadata
│       ├── references/
│       │   ├── oke-multihome-notes.md      # Known working pattern and failure handling
│       │   └── oke-dpdk-mlx5-notes.md      # DPDK, Multus, and Mellanox mlx5 diagnostics
│       └── scripts/
│           ├── discover-oke-multihome.py   # Cluster/node-pool/subnet discovery
│           └── generate-multihome-manifest.py # NAD and test pod manifest generator
├── shared/
│   └── oci-resource-map.md                 # K8s-to-OCI mapping helper commands
└── scripts/
    ├── preflight-check.sh                  # OCI CLI auth + tenancy + region + compartment discovery
    ├── validate-cidr.sh                    # CIDR overlap detection (VCN / Pod / Service CIDRs)
    ├── gva-menu.sh                         # Interactive GVA node-pool builder
    ├── gva-discover.sh                      # GVA discovery helper (cluster/VCN/subnet/NSG)
    ├── gva-cli-resolve.sh                   # Resolve preview GVA CLI workspace paths
    ├── oke-discover.sh                     # Troubleshooter cluster discovery helper
    ├── oke-addon-health.sh                 # OKE add-on health collector
    ├── oke-pod-network-check.sh            # OCI CNI/IPAM and Multus collector
    ├── oke-autoscaler-check.sh             # Autoscaler and node-pool scaling collector
    ├── oke-dns-check.sh                    # CoreDNS and service discovery collector
    ├── oke-ingress-check.sh                # OCI Native Ingress collector
    ├── oke-private-endpoint-check.sh       # Private API endpoint collector
    ├── oke-ocir-image-pull-check.sh        # OCIR image pull collector
    ├── oke-workload-identity-check.sh      # Workload Identity collector
    ├── oke-incident-timeline.sh            # Kubernetes/OCI timeline collector
    └── node-doctor-run.sh                  # Node doctor runner via kubectl debug + chroot
```

## Installation

### Claude Code

```bash
git clone https://github.com/chiphwang1/oke-agent-plugin.git
claude --plugin-dir ./oke-agent-plugin
```

### Codex

```bash
git clone https://github.com/chiphwang1/oke-agent-plugin.git
cd oke-agent-plugin
codex "Summarize the active repository instructions and available OKE skills."
```

The Codex plugin manifest is at `.codex-plugin/plugin.json`. For local skill installation without a plugin workflow, copy the skills and supporting assets into `~/.codex`, preserving the relative layout used by the skill files:

```bash
mkdir -p ~/.codex/skills ~/.codex/scripts ~/.codex/shared ~/.codex/agents

cp -R skills/oke-cluster-generator ~/.codex/skills/
cp -R skills/oke-troubleshooter ~/.codex/skills/
cp -R skills/oke-gva-deployer ~/.codex/skills/
cp -R skills/oke-multihome-deployer ~/.codex/skills/

cp scripts/*.sh ~/.codex/scripts/
chmod +x ~/.codex/scripts/*.sh

cp -R shared/. ~/.codex/shared/
cp -R agents/. ~/.codex/agents/
```

Then start Codex in the workspace you want to operate on:

```bash
codex login
codex -C /path/to/your/workspace
```

The skills auto-trigger from their `SKILL.md` descriptions. Example prompts:

```text
Build an OKE Terraform stack for us-ashburn-1
Troubleshoot why my OKE service has no load balancer IP
Configure OKE Generic VNIC Attachment for this cluster
```

If you update this repo later, reinstall the changed folders into `~/.codex` so Codex sees the latest skill definitions and helper scripts.
For local plugin-directory testing, add the repository as a local marketplace source or install it from the GitHub repository using your Codex plugin workflow.

## Error Handling

All scripts follow a consistent error contract:

| Exit code | Meaning |
|-----------|---------|
| `0` | Success |
| `1` | Expected error (e.g., OCI CLI not authenticated, CIDR overlap detected) |
| `2` | Unexpected error (e.g., CLI not installed, invalid argument) |

Error details are emitted as structured JSON to stderr:

```json
{
  "error_code": "OCI_CLI_NOT_AUTHENTICATED",
  "message": "The OCI CLI is installed but not authenticated.",
  "remediation": "Run: oci setup config",
  "docs_url": "https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm"
}
```

## Verification Scenarios

Manually validate the plugin with the following flows:
- **Broken image:** Deploy a pod with an invalid image, run `/oke-troubleshooter "pods in ImagePullBackOff"` and confirm the top hypothesis cites the FailedScheduling or ErrImagePull evidence with remediation to correct the image or credentials.
- **Load balancer pending:** Provision a Service of type `LoadBalancer` with a misconfigured subnet, run `/oke-troubleshooter "service frontend-lb pending ip"` and verify networking hypotheses reference OCI load balancer status and NSG checks.
- **Slow deployment:** Generate load against `deployment/nginx` until p99 latency spikes; run `/oke-troubleshooter "deployment nginx slow"` and confirm the Application Performance hypothesis cites replica shortfall or backend latency metrics with scale-out remediation.
- **PVC Pending:** Block storage quota reached; expect storage hypothesis citing CSI controller logs and OCI Block Volume availability.
- **Missing OCI CLI:** Temporarily hide the OCI CLI binary; ensure the report warns about limited coverage yet still surfaces Kubernetes-only insights.
- **Healthy cluster:** Provide a benign symptom (e.g., `check cluster health`); confirm low-confidence hypotheses with recommendations for continued monitoring.
- **GVA multihome validation:** Run `/oke-agent-plugin:oke-multihome-deployer` against a GVA-enabled node pool; confirm generated pods expose `eth0` and `net1`, and that peer pods can ping over their `net1` addresses.
- **OKE add-on failure:** Break or scale down CoreDNS, run `/oke-troubleshooter "DNS timeouts in prod"`, and confirm it collects CoreDNS/add-on evidence.
- **Autoscaler no-scale:** Create a Pending workload, run `/oke-troubleshooter "cluster autoscaler is not adding nodes"`, and confirm it surfaces FailedScheduling and autoscaler refusal signals.
- **Pod sandbox / CNI:** Trigger a CNI or Multus pod sandbox failure, run `/oke-troubleshooter "FailedCreatePodSandBox with OCI CNI"`, and confirm it checks OCI CNI, Multus, NADs, and pod events.
- **Private API endpoint:** Run `/oke-troubleshooter "private OKE API endpoint unreachable"` and confirm it checks kubeconfig, API readiness, OKE cluster metadata, and NSGs.
- **OCIR image pull:** Run `/oke-troubleshooter "OCIR ImagePullBackOff unauthorized"` and confirm it checks pod events, image pull secrets, service accounts, and OCIR repositories.
- **Workload Identity:** Run `/oke-troubleshooter "pod gets NotAuthorized from OCI API"` and confirm it checks service account, pod logs, dynamic groups, and IAM policies.
- **OCI Native Ingress:** Run `/oke-troubleshooter "OCI native ingress backend TLS errors"` and confirm it checks ingress class, Ingress object, controller logs, and backend/listener signals.
- **Incident timeline:** Run `/oke-troubleshooter "build incident timeline for prod web"` and confirm it merges Kubernetes events, rollout history, object descriptions, and OCI alarms.

## References

- [terraform-oci-oke](https://github.com/oracle-terraform-modules/terraform-oci-oke) — OKE Terraform module (variable authority)
- [oci-hpc-oke](https://github.com/oracle-quickstart/oci-hpc-oke) — HPC OKE quickstart reference
- [oke-terraform-stack-builder](https://github.com/chiphwang1/oke-terraform-stack-builder) — Skill 1 reference implementation
- [K8sGPT](https://github.com/k8sgpt-ai/k8sgpt) — Analyzer patterns for Kubernetes troubleshooting
- [HolmesGPT](https://github.com/robusta-dev/holmesgpt) — Symptom → evidence → hypothesis workflow inspiration
- [OKE Documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm) — OCI Kubernetes Engine docs
- [Claude Code Plugins Reference](https://docs.anthropic.com/en/docs/claude-code/plugins) — Plugin architecture
