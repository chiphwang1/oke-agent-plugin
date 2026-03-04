# PRD — OKE Agent Plugin (Executive Brief)

## Summary
An executive-level overview of the OKE Agent Plugin for Claude Code. The plugin provides:
- OKE Terraform/ORM stack generation
- Incident troubleshooting that correlates OCI + Kubernetes evidence
- Limited Availability (LA) feature enablement for customers (initially Generic VNIC Attachment or GVA)

This PRD reflects the current implementation scope in this repository.

## Problem Statement
OKE operators lack a unified, guided AI workflow that covers both day-1 cluster creation and day-2 incident response. Existing tools (e.g., AKS MCP, Amazon Q) do not serve OKE, leaving teams to stitch together OCI CLI, kubectl, and docs manually.

## Goals
- Deliver a structured workflow for production-ready OKE Terraform and ORM generation.
- Enable end-to-end OKE incident troubleshooting that correlates Kubernetes symptoms with OCI signals.
- Provide a guided flow to deploy Limited Availability features, starting with GVA-enabled node pools.
- Maintain consistent validation and error handling across the plugin.

## Non-Goals
- Replace full OCI console workflows or all OKE management operations.
- Provide automatic remediation without user review.
- Act as a general Kubernetes chatbot beyond OKE-specific contexts.

## Target Users
- SREs and platform engineers operating OKE clusters.
- Cloud engineers provisioning OKE with Terraform and OCI Resource Manager.
- Developers responsible for OKE troubleshooting in production environments.

## User Scenarios
1. As an operator, I want to generate a Terraform + ORM stack for a new OKE cluster with correct networking, security, and add-ons.
2. As an on-call engineer, I want to quickly diagnose “pods stuck Pending” by correlating kubectl output with OCI limits and node pool status.
3. As a platform engineer, I want to deploy a GVA-enabled node pool with correct secondary VNIC profile and verify it with a test deployment.

## Scope
### In Scope
- Skill-driven workflows:
  - `/oke-agent-plugin:oke-cluster-generator`
  - `/oke-agent-plugin:oke-troubleshooter`
  - `/oke-agent-plugin:oke-gva-deployer`
- Structured, multi-phase dialogue and validation.
- Evidence collection and hypothesis ranking using subagents.
- CLI-based discovery and validation scripts.

### Out of Scope
- UI-based management beyond Claude Code.
- Automatic rollbacks or live OCI updates without explicit user commands.
- Support for non-OKE Kubernetes distributions.

## Product Requirements
### Functional Requirements
- Provide guided discovery for OKE cluster generation across networking, node pools, storage, security, and add-ons.
- Generate Terraform and ORM artifacts:
  - `main.tf`, `variables.tf`, `outputs.tf`, `provider.tf`, `terraform.tfvars.example`, `schema.yaml`
- Troubleshoot incidents using a symptom triage map that selects diagnostic domains.
- Collect evidence using curated `kubectl` and `oci` command recipes.
- Rank hypotheses with confidence scores and remediation commands.
- Generate GVA node-pool creation commands and validation manifests.

### Non-Functional Requirements
- Consistent error contract:
  - Exit code `0` for success, `1` for expected errors, `2` for unexpected errors
  - JSON error payload on stderr
- Must operate with authenticated OCI CLI and configured `kubectl` when OCI-layer evidence is needed.
- Clear prompts and summaries at each phase to avoid accidental configuration mistakes.

## User Experience (High-Level)
### Cluster Generator
1. Pre-flight: validate OCI CLI auth and discover tenancy/region/compartment.
2. Discovery: 7-domain questionnaire.
3. Architecture summary for confirmation.
4. Artifact generation.
5. Iteration loop to revise choices.

### Troubleshooter
1. Input & preflight: capture symptom, namespace, check CLI availability.
2. Symptom triage: map to diagnostic domains.
3. Evidence collection: run domain-specific commands.
4. Hypothesis ranking: score root causes with citations.
5. Report & next steps: remediation and prevention guidance.

### LA Feature Deployer (GVA)
1. Auto-discover cluster context.
2. Enumerate VCNs, subnets, and images.
3. Emit `oci ce node-pool create` command.
4. Provide validation deployment manifest.

## Dependencies and Integrations
- OCI CLI (`oci`) for OKE and infrastructure queries.
- `kubectl` for Kubernetes cluster evidence.
- Claude Code plugin system and subagent orchestration.

## Success Metrics
- Time-to-first-cluster-generation reduced vs manual setup.
- Troubleshooting session yields a ranked hypothesis and actionable remediation in a single run.
- Reduction in incident MTTR where OCI-layer signals are required.
- Successful GVA node pool creation and validation on first attempt.

## Competitive Landscape (Strategic)
- **Market framing:** Hyperscalers are embedding AI assistance inside their consoles and CLI surfaces, primarily focused on diagnostics and guidance rather than full-stack, opinionated workflows.
- **Gap on OKE:** OKE lacks a first-party, AI-assisted workflow that unifies day-1 provisioning and day-2 troubleshooting with OCI-specific evidence correlation.
- **Differentiation:** This plugin positions OKE with parity on AI troubleshooting while adding a unique, consolidated workflow that includes IaC generation and a repeatable path to enable Limited Availability features for customers (starting with GVA node-pool deployment).
- **Strategic value:** By standardizing cluster generation and incident response into repeatable, guided flows, the plugin reduces time-to-deploy and MTTR, and lowers reliance on tribal knowledge.

## Risks and Mitigations
- OCI CLI not authenticated or missing: surface explicit error with remediation instructions.
- Insufficient permissions: degrade gracefully with partial evidence and clear warnings.
- Incomplete symptom mapping: prompt for additional details and allow rerun by domain.
- Terraform module drift: keep reference mappings aligned with `terraform-oci-oke` variable catalog.

## Rollout and Verification
- Validate via manual scenarios:
  - ImagePullBackOff, LoadBalancer pending, PVC Pending, slow deployment, missing OCI CLI, healthy cluster.
- Verify generated Terraform and ORM schema output for completeness.
- Confirm GVA node pool creation command succeeds in a test environment.

## Timeline
- Prototype target: March 10, 2026.
- MVP target: March 23, 2026.

## Open Questions
- Should the plugin offer optional telemetry for anonymized troubleshooting outcomes?
- Do we need a formal compatibility matrix for OCI CLI versions and Kubernetes versions?
