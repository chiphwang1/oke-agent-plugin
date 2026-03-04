# PRD — OKE Agent Plugin (Detailed)

## 1. Overview
The OKE Agent Plugin is a Claude Code plugin that provides AI-guided workflows for Oracle Kubernetes Engine (OKE). It focuses on three core areas:
- Day‑1 provisioning via Terraform + OCI Resource Manager (ORM) schema generation.
- Day‑2 incident troubleshooting via evidence correlation across Kubernetes and OCI.
- Limited Availability (LA) feature enablement for customers, starting with Generic VNIC Attachment (GVA).

This document is a detailed PRD intended for product, engineering, and delivery teams.

## 2. Objectives
### Primary Objectives
- Reduce time-to-provision for OKE clusters by delivering an opinionated, guided IaC generation flow.
- Reduce incident MTTR by providing structured troubleshooting with evidence-backed hypotheses.
- Provide a repeatable and safe workflow for enabling LA features, beginning with GVA.

### Secondary Objectives
- Standardize OKE operational playbooks into deterministic, auditable workflows.
- Lower the learning curve for OKE operators and SREs.

## 3. Problem Statement
OKE lacks a unified AI workflow covering both provisioning and troubleshooting. Operators rely on manual CLI calls, documentation, and institutional knowledge. LA feature enablement introduces additional operational risk because it often requires careful sequencing and correct OCI configuration.

## 4. Target Users and Personas
- **SRE / On‑Call Engineer:** Needs fast incident triage with clear remediation.
- **Platform Engineer:** Needs consistent cluster provisioning and safe enablement of advanced features.
- **Cloud Engineer / Infrastructure Owner:** Needs validated Terraform + ORM assets to support scale and governance.

## 5. Scope
### In Scope
- `/oke-agent-plugin:oke-cluster-generator`
- `/oke-agent-plugin:oke-troubleshooter`
- `/oke-agent-plugin:oke-LA-feature-gva-deployer`
- OCI CLI and `kubectl` integration for discovery and evidence.
- Structured error handling and validation.

### Out of Scope
- Full UI tooling beyond Claude Code.
- Automatic remediation without explicit user action.
- Non‑OKE Kubernetes distributions.

## 6. Functional Requirements
### 6.1 Cluster Generator
- Guided discovery across 7 domains:
  - Cluster fundamentals, networking, node pools, storage, security & access, add‑ons & observability, ORM schema preferences.
- Pre‑flight validation:
  - OCI CLI authenticated; tenancy, region, compartment discovery.
- Generate artifacts:
  - `main.tf`, `variables.tf`, `outputs.tf`, `provider.tf`, `terraform.tfvars.example`, `schema.yaml`.
- Iterative refinement and regeneration without losing context.

### 6.2 Troubleshooter
- Accept free‑form symptom input.
- Triage symptoms to diagnostic domains (pod runtime, networking, storage, control plane, IAM, OCI limits, application performance).
- Collect evidence with curated `kubectl` and `oci` commands.
- Invoke subagents to normalize evidence and rank hypotheses with confidence scores.
- Output actionable remediation steps and prevention guidance.

### 6.3 LA Feature Deployer (GVA)
- Auto‑discover cluster context from kubeconfig and OCI config.
- Enumerate VCNs, subnets, and cluster‑compatible images.
- Generate an `oci ce node-pool create` command with:
  - Secondary VNIC profiles
  - Application Resource labels
  - Validation guidance
- Provide a test deployment manifest to validate GVA functionality.
 - Enforce safety checks before command generation:
   - Require VCN‑Native CNI
   - `ipCount` ≤ 16
   - One Application Resource per pod
   - Validate shape/VNIC attachment limits where possible
   - Provide max‑pods guidance when GVA is enabled

## 7. Non‑Functional Requirements
- **Error Contract:**
  - Exit `0` success, `1` expected errors, `2` unexpected errors.
  - Structured JSON errors on stderr.
- **Security:**
  - Read‑only evidence collection; no implicit destructive actions.
- **Reliability:**
  - Graceful degradation when OCI CLI or permissions are missing.
- **Usability:**
  - Clear prompts at each phase and summarized confirmations.
 - **Discovery & Fallback:**
   - If OCI CLI is unavailable, continue with manual prompts.
   - If OCI CLI is available but calls fail (auth/permission/timeout), collect partial context and prompt for missing fields.

## 8. User Flows
### 8.1 Cluster Generator Flow
1. Pre‑flight checks.
2. 7‑domain discovery Q&A.
3. Architecture summary and confirmation.
4. Artifact generation.
5. Iteration and regeneration as needed.

### 8.2 Troubleshooting Flow
1. Symptom input and environment pre‑flight.
2. Domain triage.
3. Evidence collection.
4. Hypothesis ranking.
5. Remediation guidance and next steps.

### 8.3 LA Feature Enablement Flow (GVA)
1. Auto‑discovery.
2. Resource selection (VCN, subnet, image).
3. Command generation.
4. Validation deployment.

## 9. Dependencies and Integrations
- OCI CLI (`oci`).
- `kubectl` configured for target clusters.
- Claude Code plugin framework and subagent orchestration.

## 10. Acceptance Criteria
### Cluster Generator
- Generates complete Terraform + ORM artifacts from a single guided session.
- Produces a valid ORM schema that passes OCI validation.

### Troubleshooter
- Produces at least one ranked hypothesis with evidence citations.
- Offers remediation commands that are context‑aware.

### LA Feature Deployer (GVA)
- Generates a syntactically valid `oci ce node-pool create` command.
- Validation manifest deploys successfully in test environment.
 - Success signals:
   - GVA extended resources appear on nodes.
   - Test pod schedules and runs with required toleration and Application Resource.

## 11. Success Metrics
- 50% reduction in time to produce initial Terraform/ORM assets.
- 30% reduction in average incident triage time for OKE issues.
- 80% first‑attempt success rate for GVA node pool creation in test environments.
 - Define baseline and measurement method for each metric before tracking.

## 12. Risks and Mitigations
- **CLI not authenticated:** fail fast with remediation instructions.
- **Insufficient permissions:** return partial evidence with explicit warnings.
- **Module drift:** update reference mappings when upstream Terraform module changes.
- **Feature gating:** LA features may change requirements; include versioned validation guidance.
 - **CLI timeouts:** Provide manual fallback and retry guidance.

## 13. Competitive Context (Detailed)
- **AWS EKS:** Amazon Q provides console‑embedded diagnostics but lacks integrated IaC generation workflows.
- **Azure AKS:** Agentic CLI and Copilot support troubleshooting, but no unified IaC + LA feature enablement flow.
- **Google GKE:** Gemini Cloud Assist supports investigations in console; CLI/plugin workflows are less consolidated.

## 14. Timeline
- Prototype target: March 10, 2026.
- MVP target: March 23, 2026.

## 15. Open Questions
- Should LA enablement workflows include a formal approval checkpoint?
- Do we need a compatibility matrix for OCI CLI and Kubernetes versions?
- What telemetry (if any) is acceptable for troubleshooting outcomes?
 - What is the baseline for time‑to‑provision and MTTR measurements?
