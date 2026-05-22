# Contributing

This repository packages OKE-focused agent skills for Codex and Claude Code. Keep changes small, testable, and safe for offline CI.

## Development Rules

- Preserve both `.codex-plugin/plugin.json` and `.claude-plugin/plugin.json` compatibility.
- Keep `SKILL.md` files focused on orchestration, guardrails, and trigger behavior.
- Move long examples, detailed questionnaires, and troubleshooting reference material into adjacent reference files.
- Do not commit tenancy-specific OCIDs, kubeconfig data, auth tokens, private IP inventories, or customer-specific cluster names.
- Keep live OCI/OKE validation separate from offline tests.
- Require explicit user confirmation before documenting or adding workflows that mutate OKE or OCI resources.

## Local Validation

Run these before committing:

```bash
bash -n scripts/*.sh
bash tests/scripts-smoke.sh
git diff --check
```

If `shellcheck` is installed, also run:

```bash
shellcheck scripts/*.sh
```

The smoke suite is mocked and must not require live OCI, Kubernetes, or network access.

## Release Checklist

1. Confirm `git status --short` contains only intentional changes.
2. Run the local validation commands.
3. Confirm generated local artifacts are ignored, especially `.gva-cli/`, `gva-cli/`, and `node-doctor-results*/`.
4. Update `README.md` when user-facing skill behavior changes.
5. Commit with a message that names the affected skill or workflow.
