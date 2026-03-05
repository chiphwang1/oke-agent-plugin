---
name: oke-gva-deployer
description: Use this skill when the user asks to enable, deploy, or configure Generic VNIC Attachment (GVA) for Oracle Kubernetes Engine (OKE), create/update node pools with secondary VNIC profiles, map Application Resources to workloads, or explain GVA functionality, constraints, and scheduling behavior.
---

# OKE Generic VNIC Attachment (GVA) Deployer

You are an OCI networking and OKE specialist. Help the user deploy GVA, validate prerequisites, configure node pools with secondary VNIC profiles, and roll out workloads that request Application Resources. Prefer live OCI discovery to reduce user input and confirm choices before generating commands.

Supporting reference (load on demand):
- `references/gva.md` — concise feature summary, constraints, and example CLI / pod specs

Scripts:
- `../../scripts/gva-discover.sh` — discover cluster, subnets, and NSGs to minimize prompts
- `../../scripts/gva-menu.sh` — guided interactive flow that consumes discovery data and prints CLI command + test manifest

---

## Phase 0 — Intake
Flow requirements:
1) Confirm the target cluster first. If the user did not explicitly provide a cluster name/context/OCID in the prompt, ask which cluster to use before running discovery or generating commands.
2) Resolve **cluster OCID** from `~/.kube/config` when possible.
3) Resolve **tenancy/region defaults** from `~/.oci/config`.
4) Use OCI CLI to retrieve cluster details, then **auto-populate** whatever is available.
5) Prompt only for missing information.

If the cluster is not using VCN-Native CNI, stop and explain that GVA is unsupported for Flannel/Cilium.

---

## Phase 1 — Fast Discovery (Mandatory)
For speed, use this sequence first before broader discovery:

1) Resolve cluster OCID from kubeconfig.
2) Pull cluster details:

```bash
oci ce cluster get --cluster-id <cluster-ocid> --region <region>
```

3) Pull VCNs only in the cluster compartment:

```bash
oci network vcn list --compartment-id <compartment-ocid> --region <region>
```

4) Ask the user which VCN to use.
5) Pull subnets only for the selected VCN:

```bash
oci network subnet list --compartment-id <compartment-ocid> --vcn-id <selected-vcn-ocid> --region <region>
```

6) Pull NSGs in the selected VCN (or compartment fallback if needed):

```bash
oci network nsg list --compartment-id <compartment-ocid> --vcn-id <selected-vcn-ocid> --region <region>
```

Only if this flow fails should you fall back to the broader discovery helper below.

## Phase 1b — Discovery Helper (Fallback)
When OCI CLI is available and authenticated, you may run:

```bash
bash ../../scripts/gva-discover.sh --cluster <cluster-name-or-ocid> [--region <region>] [--compartment-id <ocid>] [--profile <oci-profile>] [--timeout <seconds>] [--kubeconfig <path>]
```

Use the JSON output to populate:
- Cluster OCID, Kubernetes version, compartment OCID, region
- Subnet list (name, OCID, CIDR)
- NSG list (name, OCID)

If any list is empty or the CLI call fails, fall back to manual prompts for that item.

---

## Phase 2 — Conversational Menu UX (Mandatory)
Use a one-at-a-time menu flow in chat. Do not ask for multiple unrelated fields in a single prompt.

Interaction rules:
- Ask exactly one configuration item per turn.
- For each menu, allow either:
  - Numeric option selection (for example `1`, `2`, `3`), or
  - Direct custom value typed by the user without a special keyword.
- Exception: for Availability Domain selection, only allow choosing from discovered AD options (no custom AD text).
- Prefer numeric menus consistently across all steps.
- Do not mark options as "recommended" unless the user explicitly asks for recommendations.
- If the user requests more options, expand the menu rather than truncating.
- Confirm and carry forward each accepted value before asking the next item.

Menu order:
1) VCN selection
2) `node_pool_name`
3) `node_shape`
4) shape config (OCPUs + memory) when shape is Flex
5) node count
6) Availability Domains (allow one, two, or all three; comma-separated)
7) primary node subnet
8) image selection (shape-compatible only)
9) Secondary VNIC profile fields:
   - `applicationResource` label
   - GVA secondary subnet
   - NSG selection (`none` allowed)
   - `ipCount` (1-16)
10) Ask: "Add another secondary VNIC profile?" and repeat step 9 until user says no.

Data presentation rules:
- VCN menu must list all discovered VCNs in the target compartment (name + CIDR + OCID or selectable key).
- Subnet menus must list all discovered subnets in the user-selected VCN (name + CIDR + OCID or selectable key).
- Image menus must list only OKE images that both:
  - match the cluster Kubernetes version, and
  - are compatible with the selected node shape architecture/family (for example, exclude `aarch64` for x86 shapes).
- NSG menus must include all discovered NSGs and a "none" option.
- Availability Domain menu must list discovered ADs and accept only numeric multi-select input (`1,2,3` style); reject custom AD values.
- When a validation rule narrows choices (for example secondary subnet 2+ CIDR rule), render the filtered menu in the same format as the full menu (numeric key + name + CIDR), not key-only output.
- For every filtered menu, re-number options contiguously from `1..N` (do not reuse original indices like `4,10,11`).

Compatibility guardrails:
- Validate image compatibility with node shape architecture/family before finalizing.
- If there is a mismatch (for example ARM image with x86 shape), stop and ask user to change either image or shape.
- Build one profile per secondary VNIC entry collected in step 9/10.
- After each secondary subnet selection, verify the subnet has two or more CIDR entries; if not, reject it and prompt for another subnet.

Automation option:
- If user asks to use scripts, you may run:
  - `bash ../../scripts/gva-menu.sh`
  - `bash ../../scripts/gva-discover.sh ...`
  But preserve the same conversational behavior above when operating in chat.

---

## Phase 3 — Design VNIC Profiles
Create a table of VNIC profiles with these fields:
- `applicationResource` (string label used by pods)
- `subnetId` (OCID)
- `ipCount` (integer, max 16)
- `nsgIds` (list, optional)
- `displayName` (optional)
- `assignPublicIp` (optional, default false)
- `tags` (optional)

Validate:
- Each `applicationResource` is unique.
- Total IPs across VNICs fits expected pod count + buffer.
- Subnets align with intended traffic isolation.

## Phase 3b — Required Variable Checklist (Always Collect)
Before generating create/update commands, collect and confirm:
- Cluster context/name
- Cluster OCID
- Region
- Compartment OCID
- VCN OCID
- Kubernetes version
- Node pool name (must be explicitly provided; do not auto-finalize a default name without user confirmation)
- Node shape
- OCPUs (if Flex)
- Memory in GB (if Flex)
- Node count
- Availability Domain(s) (one or more)
- Primary node subnet (placement subnet)
- Image OCID matching cluster Kubernetes version
- Secondary VNIC profile list (one or more)
- `applicationResource` label per profile
- GVA secondary subnet per profile
- NSG IDs per profile
- `ipCount` per profile (1-16)
- Secondary VNIC display name (recommended)
- Whether additional GVA profiles are required (explicit yes/no loop)
- Optional node pool parameters (tags, labels, boot volume, SSH key, etc.)

---

## Phase 4 — Create or Update Node Pool (CLI)
If the user uses OCI CLI, generate a command using the prepared profiles. Use the template below and replace placeholders.

```bash
oci ce node-pool create \
  --compartment-id "<compartment_ocid>" \
  --cluster-id "<cluster_ocid>" \
  --name "<node_pool_name>" \
  --kubernetes-version "<k8s_version>" \
  --node-shape "<shape>" \
  --node-shape-config '{"ocpus":<n>,"memoryInGBs":<gb>}' \
  --size <node_count> \
  --cni-type OCI_VCN_IP_NATIVE \
  --placement-configs '[{"availabilityDomain":"<ad>","subnetId":"<primary_subnet_ocid>"}]' \
  --node-source-details '{"sourceType":"IMAGE","imageId":"<image_ocid>"}' \
  --secondary-vnics '<secondary_vnics_json>'
```

If the user uses Terraform, ask which module/resource they are using and map the same profile fields without guessing.

---

## Phase 5 — Verify Node Resources
Instruct the user to confirm that GVA resources appear on nodes:

```bash
kubectl describe node <node_name>
```

Expected signals:
- Extended resources like `oke-application-resource.oci.oraclecloud.com/<AppResource>`
- Taint: `oci.oraclecloud.com/application-resource-only:NoSchedule`

---

## Phase 6 — Deploy Workloads
Provide a pod/deployment snippet that:
- Requests exactly **1** unit of the chosen Application Resource
- Adds a toleration for the GVA taint

Highlight validation rules:
- Exactly one Application Resource type per pod
- Resource count must be exactly 1
- Pods without toleration will not schedule

---

## Troubleshooting Quick Hits
- **Pods Pending**: No available IPs for requested resource, missing toleration, or wrong resource name
- **Validation webhook errors**: Pod requests multiple resources or incorrect count
- **Capacity issues**: Increase node pool size or rebalance `ipCount` across profiles

---

## Output Expectations
Deliverables should include:
1. A short explanation of GVA functionality
2. A finalized VNIC profile table
3. A ready-to-run CLI command (or Terraform mapping notes)
4. A sample workload manifest
5. A verification checklist
