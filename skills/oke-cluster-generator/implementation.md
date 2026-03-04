# Skill 1 Implementation Notes — `/oke-cluster-generator`

## Overview
`/oke-cluster-generator` walks operators through a structured, five-phase workflow to produce production-ready Terraform artifacts and an OCI Resource Manager (`schema.yaml`) bundle for Oracle Kubernetes Engine (OKE). The skill mirrors the legacy **OKE Terraform Stack Builder** flow but is adapted to the plugin architecture with live tenancy discovery, argument pre-fill, and error-contract alignment.

The skill definition lives in `skills/oke-cluster-generator/SKILL.md`, with supporting materials under the same directory. Shared scripts in `scripts/` (at repo root) provide tenancy discovery and CIDR validation.

## Architecture Summary

| Component | Purpose | Location |
|-----------|---------|----------|
| Skill spec | Conversational flow (Pre-flight → Domains → Summary → Generate) | `skills/oke-cluster-generator/SKILL.md` |
| Reference catalog | Static fallback lists + terraform-oci-oke variable map | `skills/oke-cluster-generator/reference.md` |
| Terraform templates | `main.tf`, `variables.tf`, `outputs.tf`, `provider.tf` scaffolding | `skills/oke-cluster-generator/output-templates/terraform.md` |
| ORM schema template | Base `schema.yaml` with conditional visibility rules | `skills/oke-cluster-generator/output-templates/schema.md` |
| Preflight script | Tenancy OCID, home region, compartment discovery | `scripts/preflight-check.sh` |
| CIDR validator | Detects overlap across VCN / Pod / Service CIDRs | `scripts/validate-cidr.sh` |

## Recent Updates
- Removed non-standard frontmatter fields to align with skill validation rules.
- Added brief TOCs to reference/template files for faster navigation.

## Execution Flow

1. **Pre-flight Discovery**
   - Parse invocation arguments for `WORKLOAD_TYPE`, `TARGET_REGION`, and `CLUSTER_NAME` (see `Arguments Pre-fill` section in the skill spec).
   - Run `scripts/preflight-check.sh` to confirm OCI CLI auth, capture tenancy metadata, and prompt for a target compartment.
   - Persist discovered values in session state for subsequent domains.

2. **Domain Interviews (D1–D7)**
   - Follow the sequence defined in the skill: Cluster Fundamentals, Networking, Node Pools, Storage, Security & Access, Add-ons & Observability, ORM Schema Preferences.
   - For each domain, prefer live tenancy data via OCI CLI before falling back to `reference.md` lists. Record fallback flags when static options are used.
   - Use `AskUserQuestion` with structured options (including descriptions) and enforce branching logic (e.g., prompt for VCN CIDRs only when creating a new VCN).

3. **Architecture Summary (Phase 2)**
   - Render a table of user selections per domain.
   - Highlight any CLI fallbacks detected earlier.
   - Allow the operator to accept the summary or re-open a domain for adjustments.

4. **Artifact Generation (Phase 3)**
   - Load templates from `output-templates/terraform.md` and `output-templates/schema.md`.
   - Map session variables to module inputs using the table in `reference.md` (no ad-hoc naming).
   - Populate the bundle with:
     - `main.tf` (module invocation, networking extras, add-ons)
     - `variables.tf`
     - `outputs.tf`
     - `provider.tf`
     - `schema.yaml`
   - Ensure CIDR consistency by re-running `scripts/validate-cidr.sh` if the operator changes networking answers late in the flow.

5. **Handoff & Iteration (Phase 4)**
   - Summarize generated files and next steps (Terraform `init`/`plan`, ORM import instructions).
   - Offer to revisit domains for adjustments; regenerate artifacts if the user iterates.

All phases follow the shared exit-code contract (`0` success, `1` expected issue, `2` unexpected failure) with structured JSON on stderr for errors.

## Usage Guidelines

### Prerequisites
- OCI CLI installed and authenticated (`oci setup config`).
- Operator permissions for IAM, Container Engine, Compute, Network, KMS, and Limits services.
- Access to compartment and VCN resources referenced during discovery.

### Invocation Examples
```bash
/oke-agent-plugin:oke-cluster-generator
/oke-agent-plugin:oke-cluster-generator ai/ml us-ashburn-1 prod-cluster
/oke-agent-plugin:oke-cluster-generator hpc us-frankfurt-1
```
Arguments pre-fill the workload type, region, and optional cluster name to accelerate Domain 1.

### Expected Output
- Terraform bundle with validated variables and module wiring targeting `terraform-oci-oke`.
- ORM `schema.yaml` synchronized with generated variables (grouped for Resource Manager UI).
- Supplemental notes calling out manual inputs when CLI fallbacks were used.

## Verification Checklist
- **Fresh tenancy, no pre-fill:** Run the skill without arguments; ensure Pre-flight discovers tenancy/compartment and domains present live options.
- **Pre-filled AI cluster:** Invoke with `ai/ml us-ashburn-1 prod-cluster`; verify GPU-friendly defaults (RDMA prompt, DCGM add-on availability) and correct mapping in generated Terraform.
- **Existing VCN path:** Choose "Use existing VCN" in Domain 2, supply an OCID, and confirm the generated `main.tf` disables VCN creation while wiring `vcn_id`.
- **CIDR validation:** Enter overlapping Pod/Service CIDRs to confirm `scripts/validate-cidr.sh` returns exit code `1` with structured remediation guidance.
- **Schema sync:** After any domain revisions, regenerate artifacts and inspect `schema.yaml` to ensure `variableGroups` align with the latest Terraform variables.

Document verification outcomes in the project journal or future automated tests to maintain regression coverage.
