# OKE Agent Plugin

A Claude Code plugin for Oracle Kubernetes Engine (OKE) on Oracle Cloud Infrastructure (OCI).
Fills the gap in AI-assisted Kubernetes tooling.

## Skills

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
2. **Symptom Triage** — map keywords to diagnostic domains (pod runtime, networking, storage, control plane, IAM, OCI limits).
3. **Evidence Collection** — run curated command batches via the Haiku subagent to gather structured findings.
4. **Hypothesis Ranking** — invoke the Sonnet analyst to score top root-cause hypotheses with cited evidence.
5. **Report & Next Steps** — present remediation commands, prevention guidance, and note any evidence gaps.

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
- Lists OKE images for the cluster’s Kubernetes version
- Generates a ready-to-run `oci ce node-pool create` command
- Provides a test Deployment manifest for GVA validation

**Prerequisites:**
- OCI CLI installed and configured
- `kubectl` configured for the target cluster

**Usage:**

```bash
/oke-agent-plugin:oke-gva-deployer
```

## Project Structure

```
oke-agent-plugin/
├── .claude-plugin/
│   └── plugin.json                         # Plugin manifest
├── agents/
│   ├── oke-evidence-collector.md           # Haiku subagent for command execution
│   ├── oke-hypothesis-analyst.md           # Sonnet subagent for hypothesis scoring
│   └── oke-lb-log-collector.md             # Haiku subagent for LB logging evidence
├── settings.json                           # Claude Code settings
├── skills/
│   ├── oke-cluster-generator/
│   │   ├── SKILL.md                        # 4-phase orchestration (Pre-flight → Discovery → Summary → Generate)
│   │   ├── reference.md                    # terraform-oci-oke variable catalog (D1–D6 mapping)
│   │   └── output-templates/
│   │       ├── terraform.md                # provider.tf, main.tf, outputs.tf templates
│   │       └── schema.md                   # ORM schema.yaml structure + conditional visibility patterns
│   └── oke-troubleshooter/
│       ├── SKILL.md                        # 5-phase troubleshooting workflow
│       ├── symptom-triage.md               # Symptom → domain decision table
│       └── evidence-collectors.md          # Command recipes per diagnostic domain
│   └── oke-gva-deployer/
│       ├── SKILL.md                        # GVA node pool workflow
│       ├── USAGE.md                        # How to use the GVA skill and scripts
│       ├── implementation.md               # Skill implementation notes
│       └── references/
│           └── gva.md                       # Feature summary and constraints
├── shared/
│   └── oci-resource-map.md                 # K8s-to-OCI mapping helper commands
└── scripts/
    ├── preflight-check.sh                  # OCI CLI auth + tenancy + region + compartment discovery
    └── validate-cidr.sh                    # CIDR overlap detection (VCN / Pod / Service CIDRs)
    ├── gva-menu.sh                          # Interactive GVA node-pool builder
    ├── gva-discover.sh                      # GVA discovery helper (cluster/VCN/subnet/NSG)
    └── oke-discover.sh                      # Troubleshooter cluster discovery helper
    └── node-doctor-run.sh                   # Node doctor runner via kubectl debug + chroot
```

## Installation

```bash
git clone https://github.com/chiphwang1/oke-agent-plugin.git
claude --plugin-dir ./oke-agent-plugin
```

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

## References

- [terraform-oci-oke](https://github.com/oracle-terraform-modules/terraform-oci-oke) — OKE Terraform module (variable authority)
- [oci-hpc-oke](https://github.com/oracle-quickstart/oci-hpc-oke) — HPC OKE quickstart reference
- [oke-terraform-stack-builder](https://github.com/chiphwang1/oke-terraform-stack-builder) — Skill 1 reference implementation
- [K8sGPT](https://github.com/k8sgpt-ai/k8sgpt) — Analyzer patterns for Kubernetes troubleshooting
- [HolmesGPT](https://github.com/robusta-dev/holmesgpt) — Symptom → evidence → hypothesis workflow inspiration
- [OKE Documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm) — Oracle Kubernetes Engine docs
- [Claude Code Plugins Reference](https://docs.anthropic.com/en/docs/claude-code/plugins) — Plugin architecture
