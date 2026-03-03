# OKE Agent Plugin

A Claude Code plugin for Oracle Kubernetes Engine (OKE) on Oracle Cloud Infrastructure (OCI).
Fills the gap in AI-assisted Kubernetes tooling: OKE currently has no equivalent of AKS-MCP or Amazon Q.

## Skills

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

## Project Structure

```
oke-agent-plugin/
├── .claude-plugin/
│   └── plugin.json                         # Plugin manifest
├── settings.json                           # Claude Code settings
├── skills/
│   └── oke-cluster-generator/
│       ├── SKILL.md                        # 4-phase orchestration (Pre-flight → Discovery → Summary → Generate)
│       ├── reference.md                    # terraform-oci-oke variable catalog (D1–D6 mapping)
│       └── output-templates/
│           ├── terraform.md                # provider.tf, main.tf, outputs.tf templates
│           └── schema.md                   # ORM schema.yaml structure + conditional visibility patterns
└── scripts/
    ├── preflight-check.sh                  # OCI CLI auth + tenancy + region + compartment discovery
    └── validate-cidr.sh                    # CIDR overlap detection (VCN / Pod / Service CIDRs)
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

## References

- [terraform-oci-oke](https://github.com/oracle-terraform-modules/terraform-oci-oke) — OKE Terraform module (variable authority)
- [oke-terraform-stack-builder](https://github.com/chiphwang1/oke-terraform-stack-builder) — Skill 1 reference implementation
- [OKE Documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm) — Oracle Kubernetes Engine docs
- [Claude Code Plugins Reference](https://docs.anthropic.com/en/docs/claude-code/plugins) — Plugin architecture
