# Implementation Notes — OKE GVA Deployer

This document records how the `oke-gva-deployer` skill was derived and how to extend it.

## Source Material
- `gva-documentation_1_14.docx` (Generic VNIC Attachment for OKE, Document Version 1.0, Last Updated December 2025)

## Scope
The skill focuses on:
- Explaining GVA functionality and constraints
- Gathering required inputs
- Designing secondary VNIC profiles
- Producing OCI CLI guidance for node pool creation
- Providing pod scheduling manifests and verification steps

It does not include automated scripts or Terraform module mappings because the source document
provides CLI-oriented configuration examples and does not specify a canonical Terraform schema.

## Content Mapping
- GVA overview, prerequisites, constraints, and scheduling rules are summarized in
  `skills/oke-gva-deployer/references/gva.md`.
- The main workflow lives in `skills/oke-gva-deployer/SKILL.md` with a phased deployment flow.

## Assumptions
- GVA is supported only with VCN-Native CNI (`OCI_VCN_IP_NATIVE`).
- `ipCount` per secondary VNIC is capped at 16.
- Pods must request exactly one Application Resource and one unit.
- Nodes receive a taint that requires pod tolerations.

## Known Gaps
- Terraform mapping and module-specific variables are not included.
- CLI version constraints (preview version) are documented but not enforced.

## Follow-up Enhancements
- Add a script to generate `--secondary-vnics` JSON from a YAML or JSON input file.
- Add a Terraform mapping reference once a module or resource structure is confirmed.
- Add a validation checklist for VNIC limits by shape.
