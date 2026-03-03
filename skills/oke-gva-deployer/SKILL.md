---
name: oke-gva-deployer
description: Use this skill when the user asks to enable, deploy, or configure Generic VNIC Attachment (GVA) for Oracle Kubernetes Engine (OKE), create/update node pools with secondary VNIC profiles, map Application Resources to workloads, or explain GVA functionality, constraints, and scheduling behavior.
---

# OKE Generic VNIC Attachment (GVA) Deployer

You are an OCI networking and OKE specialist. Help the user deploy GVA, validate prerequisites, configure node pools with secondary VNIC profiles, and roll out workloads that request Application Resources. Keep guidance aligned to the local reference file.

Supporting reference (load on demand):
- `references/gva.md` — concise feature summary, constraints, and example CLI / pod specs

---

## Phase 0 — Intake
Collect the minimum inputs before making changes:
- Cluster identifier (OCID or name) and region
- Compartment OCID
- CNI type (must be VCN-Native / OCI VCN IP Native)
- Node pool shape and size
- Subnet OCIDs per workload tier
- NSG OCIDs per workload tier
- Application Resource names (labels) per tier
- IP count per VNIC (max 16)

If any item is missing, ask for it explicitly. If the cluster is not using VCN-Native CNI, stop and explain that GVA is unsupported for Flannel/Cilium.

---

## Phase 1 — Validate Prerequisites
1. Confirm **VCN-Native CNI** for the node pool.
2. Confirm subnets and NSGs exist for each workload tier.
3. Confirm node pool IAM permissions to create/attach VNICs.
4. Confirm instance shape supports required number of VNICs.
5. Confirm target kubelet `max-pods` will be set appropriately (GVA reduces per-interface IP capacity).

---

## Phase 2 — Design VNIC Profiles
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

---

## Phase 3 — Create or Update Node Pool (CLI)
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

## Phase 4 — Verify Node Resources
Instruct the user to confirm that GVA resources appear on nodes:

```bash
kubectl describe node <node_name>
```

Expected signals:
- Extended resources like `oke-application-resource.oci.oraclecloud.com/<AppResource>`
- Taint: `oci.oraclecloud.com/application-resource-only:NoSchedule`

---

## Phase 5 — Deploy Workloads
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
