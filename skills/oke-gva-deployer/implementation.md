# Implementation Notes — OKE GVA Deployer

This document records how the `oke-gva-deployer` skill was derived, what has been added since the initial version, and how to extend it safely.

## Source Material
- `gva-documentation_1_14.docx` (Generic VNIC Attachment for OKE, Document Version 1.0, Last Updated December 2025)

## Scope
The skill focuses on:
- Explaining GVA functionality and constraints
- Gathering required inputs with minimal prompting
- Designing secondary VNIC profiles
- Producing OCI CLI guidance for node pool creation
- Providing pod scheduling manifests and verification steps

It does not include Terraform module mappings because the source document is CLI‑oriented and does not specify a canonical Terraform schema.

## Current Implementation
- **Skill spec**: `skills/oke-gva-deployer/SKILL.md`
- **Reference summary**: `skills/oke-gva-deployer/references/gva.md`
- **Usage guide**: `skills/oke-gva-deployer/USAGE.md`
- **Interactive menu**: `scripts/gva-menu.sh`
- **Discovery helper**: `scripts/gva-discover.sh`

### Discovery Flow
1. User enters an explicit **cluster name**. No default cluster is allowed.
2. Cluster OCID is resolved from `~/.kube/config` when possible.
3. User enters the region explicitly, and the workflow uses that exact reply.
4. `oci ce cluster get --cluster-id <ocid>` retrieves compartment and K8s version.
5. VCN list → subnet list → image list are fetched via OCI CLI.
6. Mutable node-pool values are prompted again for each new create flow.

### Menu Enhancements Added
- VCN selection **before** subnet selection.
- OKE image list filtered by cluster Kubernetes version.
- No default cluster name.
- Region is always asked explicitly and the user reply is used for OCI calls.
- Optional parameters section (only asks for values the user wants).
- End‑of‑flow action menu: **Run now / Print only / Exit**.
- `ipCount` validation enforces the documented range of `1..256`.
- Discovered secondary subnet choices are filtered to IPv4-only subnets with more than one IPv4 CIDR block.
- GVA node-pool create uses the regular OCI CLI. The workflow checks for `--secondary-vnics` and `--cni-type` before execution and no longer requires a preview OCI CLI.

## Assumptions
- GVA is supported only with VCN‑Native CNI (`OCI_VCN_IP_NATIVE`).
- `ipCount` per secondary VNIC is capped at 256.
- Pods must request exactly one Application Resource and one unit.
- Nodes receive a taint that requires pod tolerations.

## Known Gaps
- Terraform mapping and module-specific variables are not included.
- Minimum OCI CLI version for GA GVA flags is checked by help output, not by a pinned version string.
- Shape/image compatibility and VNIC attachment limits by shape are not programmatically validated; keep these as TODO/live validation checks unless OCI metadata proves them.

## Follow-up Enhancements
- Add a script to generate `--secondary-vnics` JSON from YAML/JSON input.
- Add a Terraform mapping reference once a module or resource structure is confirmed.
- Add a shape/VNIC limit validation step.
