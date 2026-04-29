# OKE Agent Plugin - Codex Instructions

## Repository Purpose

This repository is a dual-surface agent plugin for Oracle Kubernetes Engine (OKE). It supports Claude Code through `.claude-plugin/plugin.json` and Codex through `.codex-plugin/plugin.json`.

The plugin packages reusable skills for:

- Generating OKE Terraform and OCI Resource Manager assets.
- Troubleshooting OKE incidents with Kubernetes and OCI evidence.
- Creating GVA-enabled OKE node pools.
- Deploying and validating Multus multi-home pods on GVA-enabled node pools.

## Repo Map

- `.codex-plugin/plugin.json` - Codex plugin manifest. Keep it aligned with `.claude-plugin/plugin.json`.
- `.claude-plugin/plugin.json` - Claude Code plugin manifest.
- `skills/*/SKILL.md` - Skill entrypoints and trigger descriptions.
- `skills/*/references/` - Longer skill reference material loaded only when needed.
- `skills/*/scripts/` - Deterministic helpers used by skills.
- `scripts/` - Shared shell helpers and smoke-test targets.
- `tests/scripts-smoke.sh` - Offline smoke tests; this must not require live OCI or Kubernetes access.
- `README.md`, `PLAN.md`, `PRD.md`, `PRD-detailed.md` - User-facing and planning documentation.

## Working Rules

- Preserve both Codex and Claude compatibility when adding or changing skills.
- Keep skill frontmatter concise and trigger-oriented. The `description` should say when the skill should be used.
- Do not commit tenancy-specific OCIDs, private IPs, kubeconfig contents, auth tokens, or customer-specific cluster names into public examples.
- Prefer placeholder values in public docs, for example `<cluster_ocid>`, `<region>`, and `<node-name>`.
- Keep live OCI/OKE operations separate from offline repo tests. Smoke tests must use mocks or static inputs.
- Use fully qualified container images in OKE examples, for example `docker.io/nicolaka/netshoot:v0.13`.
- For OCI security-token workflows, show `OCI_CLI_AUTH=security_token` or `--auth security_token` explicitly.
- If changing a skill workflow, update README and any matching PRD/PLAN sections when the user-facing behavior changes.

## Validation

Run these checks after edits:

```bash
bash tests/scripts-smoke.sh
git diff --check
```

For Python helper changes, the smoke suite should compile relevant scripts with `python3 -m py_compile`.

## Live OKE Work

Live cluster validation requires a user-provided OCI session and kubeconfig. Do not assume these are available in Codex cloud or CI. If live validation is requested and auth fails, stop and ask the user to renew OCI auth rather than debugging unrelated cluster behavior.
