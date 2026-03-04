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
1. User enters **cluster name** (default `cluster3`).
2. Cluster OCID is resolved from `~/.kube/config` when possible.
3. Region defaults are pulled from `/Users/chipinghwang/.oci/config`.
4. `oci ce cluster get --cluster-id <ocid>` retrieves compartment and K8s version.
5. VCN list → subnet list → image list are fetched via OCI CLI.
6. Prompt only for missing values.

### Menu Enhancements Added
- VCN selection **before** subnet selection.
- OKE image list filtered by cluster Kubernetes version.
- Optional parameters section (only asks for values the user wants).
- End‑of‑flow action menu: **Run now / Print only / Exit**.

## Assumptions
- GVA is supported only with VCN‑Native CNI (`OCI_VCN_IP_NATIVE`).
- `ipCount` per secondary VNIC is capped at 16.
- Pods must request exactly one Application Resource and one unit.
- Nodes receive a taint that requires pod tolerations.

## Known Gaps
- Terraform mapping and module-specific variables are not included.
- CLI version constraints (preview version) are documented but not enforced.
- VNIC attachment limits by shape are not programmatically validated.

## Follow-up Enhancements
- Add a script to generate `--secondary-vnics` JSON from YAML/JSON input.
- Add a Terraform mapping reference once a module or resource structure is confirmed.
- Add a shape/VNIC limit validation step.
