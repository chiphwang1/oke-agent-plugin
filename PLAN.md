# OKE Agent Plugin — Implementation Plan

## Context

OKE customers face friction in deploying production-grade clusters, troubleshooting cross-layer issues (Kubernetes ↔ OCI), and safely enabling Limited Availability features. Competing platforms already have AI-assisted tooling: AKS has an official MCP server + CLI Agent (HolmesGPT-based), GKE has an official MCP server (preview), and EKS has Amazon Q (console, read-only). OKE has none of these — this plugin fills that gap as a native Claude Code plugin.

**Feasibility: HIGH.** Proven patterns exist (AKS-MCP, K8sGPT, HolmesGPT). The plugin wraps already-installed `oci` CLI and `kubectl` — no MCP server binary needed for v1. Skills are pure Claude Code markdown + bash scripts.

---

## Competitive Landscape Summary

| Capability | AWS EKS | Azure AKS | GKE | OKE (current) |
|---|---|---|---|---|
| AI Chat / Agentic | Amazon Q (read-only) | CLI Agent (HolmesGPT) | Gemini (preview) | **None** |
| MCP Server | None | Official (open-source) | Official (preview) | **None** |
| Terraform scaffolding | EKS Blueprints (CDK) | Limited | Limited | Terraform modules exist |
| Diagnostic tools | Q console | Rich (detectors, advisor) | Limited | Basic observability |

OKE has a **blank slate** — this plugin is a first-mover opportunity.

---

## Recommended Architecture

**Pure Claude Code plugin** (Skills + Subagents + Hooks). No MCP server for v1.

Rationale: `oci` CLI and `kubectl` are already on the user's PATH. Claude's Bash tool orchestrates them directly, following AKS-MCP's `call_kubectl`/`call_az` pattern but expressed as skill markdown rather than a Go process. An MCP server can be added later under `servers/` if persistent state or streaming is needed.

---

## Project Structure

```
oke-agent-plugin/
├── AGENTS.md                         # Codex repository instructions
├── .claude-plugin/
│   └── plugin.json                    # Plugin manifest (name, version, skills/agents/hooks dirs)
├── .codex-plugin/
│   └── plugin.json                    # Codex plugin manifest
├── skills/
│   ├── AGENTS.md                      # Codex skill-editing rules
│   ├── oke-cluster-generator/         # Skill 1: Terraform Cluster Generator
│   │   ├── SKILL.md                   # Main entrypoint — adapted from oke-terraform-stack-builder
│   │   ├── reference.md               # terraform-oci-oke variable catalog (D1–D6 mapping)
│   │   ├── output-templates/          # main.tf, variables.tf, outputs.tf, versions.tf, provider.tf, schema.yaml
│   │   └── scripts/
│   │       ├── preflight-check.sh     # OCI auth + region + compartment + K8s version validation
│   │       └── validate-cidr.sh       # CIDR overlap detection
│   ├── oke-troubleshooter/            # Skill 2: End-to-End Troubleshooter
│   │   ├── SKILL.md                   # Symptom → evidence → hypothesis → report
│   │   ├── symptom-triage.md          # Decision table: symptom → domain sets
│   │   ├── evidence-collectors.md     # Per-domain kubectl + OCI CLI recipes
│   │   ├── hypothesis-ranker.md       # Scoring logic (0–10 per hypothesis)
│   │   ├── report-template.md         # Structured output template
│   │   └── scripts/
│   │       ├── collect-k8s-state.sh   # Batch kubectl evidence (--namespace, --domain)
│   │       ├── collect-oci-state.sh   # Batch OCI CLI evidence (--compartment-id, --domain)
│   │       └── check-connectivity.sh  # Node/endpoint reachability
│   ├── oke-gva-deployer/              # Skill 3: GVA Node Pool Deployer
│   │   ├── SKILL.md                   # Guided GVA workflow and guardrails
│   │   ├── USAGE.md                   # Operator usage guide
│   │   ├── implementation.md          # Skill implementation notes
│   │   └── references/
│   │       └── gva.md                 # Feature constraints + examples
│   └── oke-multihome-deployer/        # Skill 4: Multus Multi-Home Workload Deployer
│       ├── SKILL.md                   # Post-GVA multihome pod workflow
│       ├── agents/
│       │   └── openai.yaml            # Skill UI metadata
│       ├── references/
│       │   └── oke-multihome-notes.md # Known working pattern and failures
│       └── scripts/
│           ├── discover-oke-multihome.py
│           └── generate-multihome-manifest.py
├── agents/
│   ├── oke-evidence-collector.md      # Haiku subagent: parallel evidence collection
│   ├── oke-hypothesis-analyst.md      # Sonnet subagent: RCA and hypothesis ranking
│   └── oke-plan-validator.md          # Preflight + plan validation subagent
├── hooks/
│   └── hooks.json                     # SessionStart: dep check; PostToolUse(Bash): audit log
├── shared/
│   ├── config-schema.md               # ~/.oke-agent/config.json schema + docs
│   ├── auth-guide.md                  # IAM patterns per skill (user, instance principal, workload identity)
│   ├── error-handling.md              # Error JSON contract (exit codes 0/1/2, structured stderr)
│   └── oci-resource-map.md            # k8s resource ↔ OCI resource ↔ CLI command lookup table
├── scripts/
│   ├── audit-logger.sh                # PostToolUse hook: append JSONL, strip credentials
│   ├── check-dependencies.sh          # oci, kubectl, helm availability check
│   └── session-init.sh                # Load ~/.oke-agent/config.json at session start
├── tests/
│   ├── scripts/                       # bats unit tests for all shell scripts
│   └── integration/                   # Dry-run mode skill integration tests
├── settings.json
├── CHANGELOG.md
└── README.md
```

---

## Skill Designs

### Skill 1 — Terraform Cluster Generator (`/oke-agent-plugin:oke-cluster-generator`)

**Basis:** [oke-terraform-stack-builder](https://github.com/chiphwang1/oke-terraform-stack-builder) — the existing skill provides the full discovery→generate→iterate workflow and is adopted as-is, integrated into the plugin structure with minor path adjustments.

**Flow:** Preflight (tenancy discovery) → Guided interview (7 domains) → Architecture summary → Code generation → Iteration

**Phases (from reference implementation):**

**Pre-flight — Tenancy Discovery** (executes before questionnaire):
1. CLI Verification: confirm OCI CLI installation and authentication
2. Tenancy Detection: extract `TENANCY_OCID` and `HOME_REGION` via `oci iam tenancy get`
3. Region Selection: present subscribed regions; user picks `TARGET_REGION`
4. Compartment Selection: list active compartments; user selects `COMPARTMENT_OCID`

**Phase 1 — Discovery (7 Domains, batched choice prompts):**
- **D1 Cluster Fundamentals:** workload type, K8s version (live from `oci ce cluster-options get`), API endpoint visibility, cluster type (Enhanced/Basic)
- **D2 Networking:** VCN source (new/existing), CNI (VCN-Native/Flannel), access infra (Bastion/Operator), gateways, extra NICs (RDMA/RoCE for AI-ML/HPC)
- **D3 Node Pools:** pool count + per-pool loop (name, shape family, scaling strategy, shape/sizing, boot volume, OS image, cloud-init)
- **D4 Storage:** persistent backends (Block Volume CSI, FSS, Object Storage), local NVMe
- **D5 Security & Access:** KMS encryption, NSGs, Pod Security Policy, Workload Identity, network policies (Calico)
- **D6 Add-ons & Observability:** monitoring, logging, ingress, GPU support, service mesh, container runtime
- **D7 ORM Schema Preferences:** marketplace visibility, variable grouping

**Phase 2 — Architecture Summary:** domain-organized confirmation table; user confirms or revises per-domain.

**Phase 3 — Code Generation (generated files):**
- `main.tf` — cluster resource, node pool(s), networking modules using `terraform-oci-oke`
- `variables.tf` — all inputs as typed variables with descriptions and defaults
- `outputs.tf` — cluster endpoint, kubeconfig, node pool details
- `versions.tf` — Terraform + OCI provider version constraints
- `provider.tf` — OCI provider with region interpolation
- `schema.yaml` — ORM schema with UI type hints, grouping, conditional visibility

**Phase 4 — Iteration:** re-run specified domain, cascade to dependent domains, regenerate summary.

**Key files:**
- `skills/oke-cluster-generator/SKILL.md` — copied and adapted from reference implementation; 4-phase orchestration with Pre-flight
- `skills/oke-cluster-generator/reference.md` — terraform-oci-oke variable catalog (D1–D6 variable mapping)
- `skills/oke-cluster-generator/output-templates/` — `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `provider.tf`, `schema.yaml` templates
- `scripts/preflight-check.sh` — OCI auth + region + compartment + K8s version validation

**Session state variables:** `WORKLOAD_TYPE`, `KUBERNETES_VERSION`, `CLUSTER_TYPE`, `TARGET_REGION`, `TENANCY_OCID`, `COMPARTMENT_OCID`, `HOME_REGION`, `VCN_SOURCE`, `EXISTING_VCN_OCID`, `CNI_TYPE`, `RDMA_ROCE_SELECTED`, `POOL_SHAPE_i`, `KMS_KEY_ID`, `WORKLOAD_IDENTITY_ENABLED`, plus CLI fallback flags.

**Behavioral rules (from reference):** explain "why" before each decision; flag cost and service-limit implications; default to production-grade (HA, private nodes, encryption); never generate incomplete Terraform; batch up to 4 independent fixed-choice questions when the runtime supports it; run CLI calls before presenting options.

**CLI fallback:** if any CLI call fails, display *"Could not retrieve live [data type]. Using static list."*, set a session flag, and continue. Phase 2 notes all fallbacks used.

**Argument pre-fill:** if invoked with args (e.g., `/oke-agent-plugin:oke-cluster-generator ai/ml us-ashburn-1 prod-cluster`), parse fast-path mode, workload type, region, and cluster name; skip corresponding Pre-flight/Phase 1 questions.

**Fast path:** if invoked with "fast path", "quick start", or "starter stack", collect only required tenancy/compartment/region/name inputs and apply production-friendly defaults: Enhanced private cluster, VCN-native pod networking, new VCN, NAT + service gateway, one Flex node pool, Block Volume CSI, Workload Identity, and managed CoreDNS/kube-proxy.

**Outputs:** Terraform bundle (`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `provider.tf`) + `schema.yaml` for ORM + preflight pass/fail report + required IAM policies.

**Reference:** [terraform-oci-oke](https://github.com/oracle-terraform-modules/terraform-oci-oke) module; [oke-terraform-stack-builder](https://github.com/chiphwang1/oke-terraform-stack-builder) source implementation.

---

### Skill 2 — End-to-End Troubleshooter (`/oke-agent-plugin:oke-troubleshooter`)

**Flow:** Symptom triage → Parallel evidence collection (k8s + OCI layers) → Hypothesis ranking → Structured report

**Key files:**
- `skills/oke-troubleshooter/SKILL.md` — 4-step orchestration with `context: fork`
- `skills/oke-troubleshooter/symptom-triage.md` — decision table (e.g., "pods pending" → Scheduling + Node Health + Storage)
- `skills/oke-troubleshooter/evidence-collectors.md` — domain recipes for Pod, Node, OKE add-ons, OCI CNI/IPAM, autoscaler, DNS, CNI, LB, Storage, IAM, Control Plane
- `skills/oke-troubleshooter/final-report-template.md` — standard report shape for hypotheses, evidence, actions, prevention, and gaps
- `agents/oke-evidence-collector.md` — Haiku subagent for parallel evidence (k8s layer + OCI layer simultaneously)
- `agents/oke-hypothesis-analyst.md` — Sonnet subagent for scoring hypotheses 0–10 with evidence quotes
- `shared/oci-resource-map.md` — Node→Instance, LoadBalancer Service→OCI LB, PV→Block Volume mappings
- `scripts/oke-addon-health.sh` — kube-system add-on readiness and warning collector
- `scripts/oke-pod-network-check.sh` — pod sandbox, OCI CNI/IPAM, Multus, and NAD collector
- `scripts/oke-autoscaler-check.sh` — Pending pod, cluster-autoscaler, and OKE node-pool collector
- `scripts/oke-dns-check.sh` — CoreDNS, Service, EndpointSlice, and pod lookup collector
- `scripts/oke-ingress-check.sh` — OCI Native Ingress and controller collector
- `scripts/oke-private-endpoint-check.sh` — private API endpoint and kubeconfig reachability collector
- `scripts/oke-ocir-image-pull-check.sh` — OCIR image pull, secret, and repository collector
- `scripts/oke-workload-identity-check.sh` — service account, dynamic group, and IAM policy collector
- `scripts/oke-incident-timeline.sh` — Kubernetes event, rollout, object, and OCI alarm timeline collector

**Hypothesis domains:** Pod scheduling, Pod runtime, OKE add-ons, Pod Networking / OCI CNI / IPAM, Cluster Autoscaler / Node Pool Scaling, DNS / Service Discovery, Networking (CNI/LB/NSG), Ingress / OCI Native Ingress, Storage (CSI), Node health, OCI infra, Control plane, Private Cluster / API Endpoint Connectivity, OCIR / Image Pull, Workload Identity / OCI API From Pods, IAM/RBAC.

**Output:** Ranked top-3 hypotheses with evidence quotes + remediation commands + prevention recommendations.

**Reference patterns:** K8sGPT analyzers (per-domain evidence), HolmesGPT (agentic RCA loop).

---

### Skill 3 — GVA Node Pool Deployer (`/oke-agent-plugin:oke-gva-deployer`)

**Flow:** Intake → discovery → profile design → command generation → verification guidance.

**Key files:**
- `skills/oke-gva-deployer/SKILL.md` — phase-driven GVA workflow
- `skills/oke-gva-deployer/USAGE.md` — quick-start and manual fallback
- `skills/oke-gva-deployer/references/gva.md` — constraints and request/limit rules
- `skills/oke-gva-deployer/validation-report-template.md` — standard node-pool validation report structure
- `scripts/gva-discover.sh` and `scripts/gva-menu.sh` — helper automation

**Reference:** OKE GVA documentation and OCI CLI node-pool operations.

---

### Skill 4 — Multus Multi-Home Workload Deployer (`/oke-agent-plugin:oke-multihome-deployer`)

**Flow:** Confirm existing GVA node pool → discover cluster/node-pool/subnet data → verify Multus and CNI prerequisites → generate NAD and test pod manifests → validate pod interfaces and connectivity.

**Key files:**
- `skills/oke-multihome-deployer/SKILL.md` — post-GVA multihome workflow
- `skills/oke-multihome-deployer/validation-report-template.md` — standard validation report structure
- `skills/oke-multihome-deployer/scripts/discover-oke-multihome.py` — OCI/Kubernetes discovery helper
- `skills/oke-multihome-deployer/scripts/generate-multihome-manifest.py` — NAD and pinned test pod manifest generator
- `skills/oke-multihome-deployer/references/oke-multihome-notes.md` — known working pattern and troubleshooting notes

**Output:** Multus `NetworkAttachmentDefinition` resources, pinned test pods, verification commands, and targeted remediation for `ipvlan`, CRI-O image-name, OCI IPAM, and Multus sandbox failures.

**Reference:** OKE GVA node pools, Multus thick plugin, OCI CNI/IPAM, and NetworkAttachmentDefinition behavior.

---

## Cross-Cutting Infrastructure

### Shared Config (`~/.oke-agent/config.json`)
Loaded at `SessionStart` by `session-init.sh`. Keys: `default_compartment_ocid`, `default_region`, `default_tags`, `naming_prefix`, `audit_log_path`. Unknown keys ignored (forward compat).

### Audit Logging
`audit-logger.sh` (PostToolUse hook on Bash): strips credential patterns (`--password`, `--token`, auth headers), appends JSONL to `~/.claude/oke-agent-audit.log`. Fields: `ts`, `session`, `skill`, `tool`, `command`, `exit_code`.

### Error Contract
All scripts: exit 0 (success), exit 1 (expected error), exit 2 (unexpected). Emit structured JSON to stderr: `{error_code, message, remediation, docs_url}`. Skills parse and format as user-facing error blocks.

### Examples and Golden Outputs
The `examples/` directory contains one successful transcript per skill plus sample
outputs linked from the README. The smoke suite includes golden-output checks for
the cluster-generator Terraform sample, GVA node-pool command sample, and generated
Multus manifest.

### Security
- No secrets printed or logged; credential fields redacted in audit log
- Read-only by default; all writes/changes require explicit user confirmation
- `shared/auth-guide.md` documents required IAM per skill (least privilege)

---

## Extensibility Design

**Adding a new skill:** Create `skills/<new-skill-name>/SKILL.md` + supporting files. Skills are auto-discovered from `skills/` directory. Bump minor version in `plugin.json`. No manifest changes needed.

**Codex compatibility:** Keep root `AGENTS.md`, nested `skills/AGENTS.md`, and `.codex-plugin/plugin.json` current with every skill capability change. Keep `.codex-plugin/plugin.json` and `.claude-plugin/plugin.json` versions aligned.

**Future MCP server:** Add `servers/oke-watch-server/` (Go, stdio transport) + entry in `.mcp.json`. Existing skills unaffected.

**Versioning:** semver. MAJOR = breaking skill name or script contract changes. MINOR = new skill added. PATCH = content/script bug fixes.

---

## Implementation Sequence

| Phase | Deliverable | Duration |
|---|---|---|
| 0: Scaffolding | Plugin loads, hooks fire, dep check runs at session start | Day 1 |
| 1: Skill 1 | `/oke-agent-plugin:oke-cluster-generator` produces validated Terraform bundle | Week 1 |
| 2: Skill 2 | `/oke-agent-plugin:oke-troubleshooter` produces ranked hypothesis report | Week 2 |
| 3: Skill 3 | `/oke-agent-plugin:oke-gva-deployer` produces validated node-pool create command and test manifest | Week 3 |
| 4: Skill 4 | `/oke-agent-plugin:oke-multihome-deployer` produces Multus NADs, test pods, and connectivity checks | Week 4 |
| 5: Integration | All skills tested, audit log verified, README complete, release tagged | Week 5 |

---

## Verification

- **Plugin load:** `claude --plugin-dir . --debug 2>&1 | grep -E "(plugin|skill|hook)"` — all skills appear
- **Codex instructions:** Run `codex "Summarize the active repository instructions and available OKE skills."` from the repo root and confirm it uses `AGENTS.md`.
- **Skill 1:** Run `/oke-agent-plugin:oke-cluster-generator "private cluster, 3 node pools"` → verify Terraform files and preflight report
- **Skill 2:** Deliberately break a pod (wrong image) → run `/oke-agent-plugin:oke-troubleshooter "pods in ImagePullBackOff"` → verify ImagePullBackOff is top hypothesis with evidence quote
- **Skill 2 OKE-specific:** Run `/oke-agent-plugin:oke-troubleshooter "cluster autoscaler is not adding nodes"` and `/oke-agent-plugin:oke-troubleshooter "DNS timeouts"` → verify helper scripts return structured evidence
- **Skill 3:** Run `/oke-agent-plugin:oke-gva-deployer` → verify cluster/subnet/NSG discovery and generated node-pool command
- **Skill 4:** Run `/oke-agent-plugin:oke-multihome-deployer` → verify generated pods expose `eth0` and `net1`, then ping peer pods over `net1`
- **Audit log:** After each skill run, inspect `~/.claude/oke-agent-audit.log` — confirm no credentials appear
- **Script unit tests:** `bats tests/scripts/` — all pass

---

## Key Open-Source References

- [oke-terraform-stack-builder](https://github.com/chiphwang1/oke-terraform-stack-builder) — **Skill 1 source implementation**: SKILL.md, reference.md, 4-phase workflow, 7-domain interview, ORM schema generation
- [AKS-MCP](https://github.com/Azure/aks-mcp) — unified CLI wrapper pattern, diagnostic categories
- [terraform-oci-oke](https://github.com/oracle-terraform-modules/terraform-oci-oke) — OKE Terraform module variables (Skill 1)
- [oci-kubernetes-monitoring](https://github.com/oracle-quickstart/oci-kubernetes-monitoring) — LA helm chart + IAM templates (Skill 3)
- [K8sGPT](https://github.com/k8sgpt-ai/k8sgpt) — per-domain analyzer pattern with hypothesis scoring (Skill 2)
- [HolmesGPT](https://github.com/robusta-dev/holmesgpt) — symptom → evidence → RCA workflow (Skill 2)
- [Claude Code plugins reference](https://code.claude.com/docs/en/plugins-reference) — skill/agent/hook architecture
