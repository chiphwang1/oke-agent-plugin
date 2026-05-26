# OKE Agent Plugin

Give your coding agent practical OCI Kubernetes Engine (OKE) operating knowledge.

This repo packages reusable agent skills for Claude Code and Codex. The skills give
an agent enough OKE context to generate Terraform, troubleshoot cluster incidents,
configure Generic VNIC Attachment (GVA), and validate Multus multi-home workloads
without starting from a blank prompt every time.

An agent skill is a packaged workflow: instructions, references, and helper scripts
that tell the agent how to handle a specific OKE task. Instead of explaining your
preferred OKE troubleshooting or Terraform-generation process every session, you can
ask the agent to use one of these skills.

The plugin is intentionally operator-centered:

- It uses your local `kubectl` and `oci` CLI configuration.
- Troubleshooting starts with read-only evidence collection.
- Any remediation or mutating command must be shown to you and explicitly approved
  before it runs.
- Offline smoke tests use mocks, so development does not require a live OKE cluster.

## Why Try It

OKE work often crosses several layers at once: Kubernetes objects, OKE add-ons, OCI
networking, IAM, node pools, load balancers, and storage. General-purpose
agents can miss those connections unless you give them a lot of context.

This plugin gives the agent that context up front:

| If you need to... | Use this skill |
| --- | --- |
| Create an OKE Terraform stack and OCI Resource Manager schema | `oke-cluster-generator` |
| Diagnose OKE pods, services, networking, add-ons, DNS, storage, image pulls, or IAM | `oke-troubleshooter` |
| Build an OKE node pool with GVA secondary VNIC profiles | `oke-gva-deployer` |
| Deploy and test Multus pods on a GVA-enabled node pool | `oke-multihome-deployer` |

The troubleshooting and multihome skills also include checks for DPDK/SR-IOV paths:
Multus attachments, SR-IOV device-plugin resources, Mellanox `mlx5`, `vfio-pci`,
RDMA/verbs devices, hugepages, and DPDK application configuration.

## Quick Start

Clone the repo:

```bash
git clone https://github.com/chiphwang1/oke-agent-plugin.git
cd oke-agent-plugin
```

Pick the path that matches your agent:

| I use... | Start here |
| --- | --- |
| Claude Code | Run `claude --plugin-dir .` from this repo |
| Codex and want to try the plugin from this repo | Run `codex "What OKE skills are available in this plugin?"` |
| Codex and want the skills available in other workspaces | Follow [Codex Local Skill Install](#codex-local-skill-install) |

If you are evaluating the plugin, start from this repo first. Install into
`~/.codex` only when you want the OKE skills available from other workspaces.

### Claude Code

```bash
claude --plugin-dir .
```

Then try:

```text
/oke-agent-plugin:oke-troubleshooter "pods stuck Pending in prod namespace"
```

### Codex

From inside the cloned repository, run:

```bash
codex "What OKE skills are available in this plugin?"
```

That command is a quick sanity check: Codex should read the local plugin context and
list the OKE skills in this repo.

Then try a natural-language prompt:

```text
Use OKE Agent Plugin to troubleshoot pods stuck Pending in my OKE cluster.
```

Live cluster workflows need your own OCI CLI session and kubeconfig. Offline smoke
tests do not need OCI or Kubernetes access.

## Good First Prompts

Start with the outcome you want:

```text
Generate an OKE Terraform stack fast path for us-ashburn-1 with private workers.
Troubleshoot why my OKE LoadBalancer service has no public IP.
Troubleshoot why my OKE LoadBalancer has an IP but no healthy endpoints.
Troubleshoot why a pod was evicted for node DiskPressure and ask before Node Doctor.
Create a GVA-enabled node pool for my current OKE cluster.
Deploy Multus multi-home test pods on my GVA node pool and validate net1.
Check an OKE workload that uses Multus, SR-IOV, hugepages, and DPDK.
```

The agent will ask follow-up questions when it needs cluster, region, compartment,
subnet, node-pool, or workload details.

## Skill Map

| Skill | Best for | Typical output |
| --- | --- | --- |
| `oke-cluster-generator` | New OKE clusters and Resource Manager stacks | Terraform files, ORM schema, design summary |
| `oke-troubleshooter` | Incidents and root-cause analysis | Evidence summary, ranked hypotheses, approved remediation commands |
| `oke-gva-deployer` | GVA secondary VNIC node pools | `oci ce node-pool create` command and validation checklist |
| `oke-multihome-deployer` | Multus pods on GVA-enabled nodes | NADs, pinned test pods, validation commands |

Use `oke-troubleshooter` for broad symptoms first. Use the GVA and Multus skills when
you already know you are deploying or validating those specific OKE networking paths.

## What You Get

### Generate OKE Terraform

`/oke-agent-plugin:oke-cluster-generator`

The agent walks through a structured OKE design conversation, summarizes the
architecture, then generates Terraform and an OCI Resource Manager schema.

Use it when you want:

- `main.tf`, `variables.tf`, `outputs.tf`, `provider.tf`, and `terraform.tfvars.example`
- `schema.yaml` for OCI Resource Manager
- Guided choices for cluster type, networking, node pools, storage, IAM, encryption,
  observability, GPU, RDMA/RoCE, and validation rules
- A fast-path mode for a private, production-friendly starter stack with minimal
  questions

Example prompts:

```text
/oke-agent-plugin:oke-cluster-generator
/oke-agent-plugin:oke-cluster-generator fast-path us-ashburn-1 demo-private-oke
/oke-agent-plugin:oke-cluster-generator ai/ml us-ashburn-1 prod-cluster
/oke-agent-plugin:oke-cluster-generator hpc us-frankfurt-1
```

Example: [successful transcript](examples/transcripts/oke-cluster-generator.md) and
[sample Terraform output](examples/outputs/oke-cluster-generator/main.tf).

### Troubleshoot OKE Incidents

`/oke-agent-plugin:oke-troubleshooter`

The agent turns a symptom into an evidence plan, collects Kubernetes and OCI signals,
ranks likely causes, and gives remediation steps.

By default, troubleshooting is read-only. The skill may run evidence commands such as
`kubectl get`, `kubectl describe`, and OCI list/get calls. It must ask before running
any remediation or mutating command, including `kubectl apply`, `patch`, `annotate`,
`delete`, restarts, scaling, drains, OCI create/update/delete operations, LB logging
enablement, or Node Doctor.

It covers:

- OKE add-ons: CoreDNS, OCI CNI, CSI, metrics, daemonsets, and deployments
- Pod networking: OCI CNI/IPAM, Multus, NADs, pod sandboxes, and secondary interfaces
- Load balancers, private endpoints, DNS, OCIR pulls, Workload Identity, and ingress
- Focused `LoadBalancer` Service evidence: Service events, endpoints, endpoint slices,
  OCI LB/NLB inventory, and NSG context
- Autoscaler and node-pool scale-up failures
- Storage, PVCs, CSI logs, and OCI limits
- OCI object correlation for Pod-to-Node-to-Instance, Service/Ingress-to-LB,
  PVC-to-volume, VNIC/subnet, and node-pool graph evidence
- Incident timelines across Kubernetes events, rollouts, object descriptions, and OCI
  alarms
- Optional Node Doctor collection for node-health incidents, using `kubectl debug`
  only after explicit approval

Example prompts:

```text
/oke-agent-plugin:oke-troubleshooter "pods stuck Pending in prod namespace"
/oke-agent-plugin:oke-troubleshooter "service payments-lb has no IP us-phoenix-1"
/oke-agent-plugin:oke-troubleshooter "service web has an external IP but no endpoints"
/oke-agent-plugin:oke-troubleshooter "pod trainer-0 was evicted on node-a for DiskPressure"
/oke-agent-plugin:oke-troubleshooter "OCIR ImagePullBackOff unauthorized"
/oke-agent-plugin:oke-troubleshooter "private OKE API endpoint unreachable"
```

Example: [successful transcript](examples/transcripts/oke-troubleshooter.md) and
[sample troubleshooting report](examples/outputs/oke-troubleshooter/final-report.md).

The troubleshooter runs `scripts/oke-object-correlator.sh` before domain-specific
collectors when a namespace and at least one selector are known. The correlator builds
a read-only graph that links Kubernetes resources to OCI resources, so hypothesis
ranking can use explicit paths like:

```text
pod/default/web-0 -> node/node-a -> instance/ocid1.instance...
service/default/web -> loadbalancer/ocid1.loadbalancer...
pvc/default/data -> pv/pvc-123 -> volume/ocid1.volume...
```

You can run the correlator directly when you want the graph without a full
troubleshooting session:

```bash
./scripts/oke-object-correlator.sh \
  --namespace default \
  --cluster-id <cluster_ocid> \
  --compartment-id <compartment_ocid> \
  --region <region> \
  --pod web-0 \
  --service web
```

The output includes `graph.kubernetes`, `graph.oci`, `graph.edges`, `findings`,
`anomalies`, and `fallback_used`.

For focused Service LoadBalancer evidence, you can also run:

```bash
./scripts/oke-service-lb-check.sh \
  --namespace <namespace> \
  --service <service> \
  --region <region> \
  --compartment-id <compartment_ocid>
```

This helper collects Service YAML, Service events, Endpoints, EndpointSlices, and
optional OCI LB/NLB/NSG inventory in a normalized JSON shape.

### Configure GVA Node Pools

`/oke-agent-plugin:oke-gva-deployer`

The agent helps create OKE node pools configured with Generic VNIC Attachment. It
discovers cluster context, walks through subnet and shape choices, generates an
`oci ce node-pool create` command, and gives a validation deployment.

Use it when you need:

- Secondary VNIC profiles on an OKE node pool
- Application Resource labels for scheduling
- IPv4-only subnet validation for secondary VNIC subnets
- A repeatable command instead of a hand-built CLI invocation

Example prompt:

```text
/oke-agent-plugin:oke-gva-deployer
```

Example: [successful transcript](examples/transcripts/oke-gva-deployer.md) and
[sample GVA command output](examples/outputs/oke-gva-deployer/node-pool-command.sh).

### Validate Multus Multi-Home Pods

`/oke-agent-plugin:oke-multihome-deployer`

The agent generates and validates Multus `NetworkAttachmentDefinition` resources and
pinned test pods for a GVA-enabled node pool.

It checks:

- `eth0` and `net1` pod interfaces
- Multus `network-status`
- Pod-to-pod connectivity over `net1`
- OCI CNI/IPAM state
- Common failures such as missing `ipvlan`, CRI-O short-name rejection, pod sandbox
  failures, and DPDK/SR-IOV Mellanox `mlx5` validation gaps

Example prompt:

```text
/oke-agent-plugin:oke-multihome-deployer
```

Example: [successful transcript](examples/transcripts/oke-multihome-deployer.md) and
[sample Multus manifest](examples/outputs/oke-multihome-deployer/gva-multihome-pods.yaml).

## Requirements

For live OKE workflows:

- OCI CLI installed and authenticated
- `kubectl` configured for the target OKE cluster
- Read access to the OCI resources you want the agent to inspect
- For remediation, permission to change the target Kubernetes or OCI resources after
  you explicitly approve the command

For security-token auth, use one of these explicitly:

```bash
export OCI_CLI_AUTH=security_token
# or pass --auth security_token to OCI CLI commands
```

For offline development and smoke tests:

- `bash`
- `python3`

## Codex Local Skill Install

If you want Codex to use the skills outside this repo, copy the skills and helper
assets into `~/.codex`:

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

If you update this repo later, reinstall the changed folders into `~/.codex`.

To confirm which copy Codex will use in another workspace:

```bash
test -f ~/.codex/skills/oke-troubleshooter/SKILL.md && \
  sed -n '1,12p' ~/.codex/skills/oke-troubleshooter/SKILL.md
```

## Safety Model

The skills are designed to be useful without hiding what they are doing:

- Live OCI and Kubernetes commands require your local credentials and kubeconfig.
- Offline tests use mocks and static inputs.
- Public examples use placeholders such as `<cluster_ocid>`, `<region>`, and
  `<node-name>`.
- Generated OKE examples use fully qualified container images, for example
  `docker.io/nicolaka/netshoot:v0.13`.
- The troubleshooting workflow separates facts from hypotheses so you can see which
  evidence supports each recommendation.
- Troubleshooting remediation is approval-gated. The agent should show the exact
  command and expected impact before running any mutating action.
- Node Doctor is treated as privileged diagnostics because it uses `kubectl debug`
  against a node. It is never run automatically.

## Repository Layout

```text
oke-agent-plugin/
|-- .codex-plugin/plugin.json        # Codex plugin manifest
|-- .claude-plugin/plugin.json       # Claude Code plugin manifest
|-- AGENTS.md                        # Codex repository instructions
|-- agents/                          # Optional Claude Code subagents
|-- examples/                        # Successful transcripts and sample outputs
|-- scripts/                         # Shared shell helpers
|-- shared/                          # Shared OKE reference material
|-- skills/
|   |-- oke-cluster-generator/       # Terraform and ORM generation
|   |-- oke-troubleshooter/          # OKE incident diagnosis
|   |-- oke-gva-deployer/            # GVA node-pool workflow
|   `-- oke-multihome-deployer/      # Multus multi-home validation
`-- tests/scripts-smoke.sh           # Offline smoke tests
```

## Development

Run the offline validation suite after edits:

```bash
bash tests/scripts-smoke.sh
git diff --check
```

The smoke tests intentionally avoid live OCI and Kubernetes access so they can run in
CI or a cloud coding environment.

Script errors follow a consistent contract:

| Exit code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | Expected error, such as missing OCI auth or a CIDR overlap |
| `2` | Unexpected error, such as a missing CLI or invalid argument |

Errors are emitted as structured JSON to stderr:

```json
{
  "error_code": "OCI_CLI_NOT_AUTHENTICATED",
  "message": "The OCI CLI is installed but not authenticated.",
  "remediation": "Run: oci setup config",
  "docs_url": "https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm"
}
```

## Manual Verification Ideas

Use these scenarios when testing against a real cluster:

- Broken image: run the troubleshooter against an `ImagePullBackOff`.
- Load balancer pending: diagnose a `LoadBalancer` service with no external IP.
- Load balancer with no backends: diagnose a Service with an external IP but empty
  Endpoints or EndpointSlices.
- Node pressure: diagnose an evicted pod and have the skill ask before Node Doctor.
- PVC pending: validate storage, CSI, volume attachment, and service-limit evidence.
- DNS outage: scale down or break CoreDNS, then check DNS timeout diagnosis.
- Autoscaler no-scale: create a Pending workload and inspect scale-up refusal signals.
- Multus validation: run the multihome skill on a GVA-enabled node pool and confirm
  pods expose `eth0` and `net1`.
- Workload Identity: diagnose a pod receiving `NotAuthorized` from OCI APIs.

## References

- [terraform-oci-oke](https://github.com/oracle-terraform-modules/terraform-oci-oke)
- [oci-hpc-oke](https://github.com/oracle-quickstart/oci-hpc-oke)
- [oke-terraform-stack-builder](https://github.com/chiphwang1/oke-terraform-stack-builder)
- [K8sGPT](https://github.com/k8sgpt-ai/k8sgpt)
- [HolmesGPT](https://github.com/robusta-dev/holmesgpt)
- [OKE Documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm)
- [Claude Code Plugins Reference](https://docs.anthropic.com/en/docs/claude-code/plugins)
