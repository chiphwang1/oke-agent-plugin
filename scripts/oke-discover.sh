#!/usr/bin/env bash
set -euo pipefail

# Discover OKE cluster context for troubleshooting.
# Usage:
#   ./scripts/oke-discover.sh --cluster <name-or-ocid> [--region <region>] [--profile <oci-profile>] [--timeout <seconds>] [--kubeconfig <path>] [--deployment <name>]

cluster_ref=""
region_arg=""
profile_arg=""
timeout_arg=""
kubeconfig_arg=""
deployment_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      cluster_ref="$2"; shift 2 ;;
    --region)
      region_arg="$2"; shift 2 ;;
    --profile)
      profile_arg="$2"; shift 2 ;;
    --timeout)
      timeout_arg="$2"; shift 2 ;;
    --kubeconfig)
      kubeconfig_arg="$2"; shift 2 ;;
    --deployment)
      deployment_name="$2"; shift 2 ;;
    -h|--help)
      echo "usage: $0 --cluster <name-or-ocid> [--region <region>] [--profile <oci-profile>] [--timeout <seconds>] [--kubeconfig <path>] [--deployment <name>]" >&2
      exit 0 ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2 ;;
  esac
done

if [[ -z "$cluster_ref" ]]; then
  echo "missing required --cluster" >&2
  exit 2
fi

if ! command -v oci >/dev/null 2>&1; then
  echo "oci cli not found" >&2
  exit 2
fi

# Read defaults from OCI config if present
config_file="$HOME/.oci/config"
config_region=""
if [[ -f "$config_file" ]]; then
  config_region=$(awk -F= '/^region=/{print $2; exit}' "$config_file" | tr -d ' ')
fi

region="${region_arg:-$config_region}"
if [[ -z "$region" ]]; then
  echo "region not provided and not found in config" >&2
  exit 2
fi

have_timeout="no"
if command -v timeout >/dev/null 2>&1; then
  have_timeout="yes"
fi

use_py_timeout="no"
declare -a timeout_prefix=()
if [[ -n "$timeout_arg" ]]; then
  if [[ "$have_timeout" == "yes" ]]; then
    timeout_prefix=(timeout "$timeout_arg")
  else
    use_py_timeout="yes"
  fi
fi

declare -a profile_args=()
if [[ -n "$profile_arg" ]]; then
  profile_args=(--profile "$profile_arg")
elif [[ -n "${OCI_CLI_PROFILE:-}" ]]; then
  profile_args=(--profile "$OCI_CLI_PROFILE")
fi

oci_json() {
  local out err rc
  local -a cmd
  err="$(mktemp)"
  cmd=(oci --region "$region")
  if [[ ${#profile_args[@]} -gt 0 ]]; then
    cmd+=("${profile_args[@]}")
  fi
  cmd+=("$@")
  if [[ ${#timeout_prefix[@]} -gt 0 ]]; then
    cmd=("${timeout_prefix[@]}" "${cmd[@]}")
  fi
  if [[ "$use_py_timeout" == "yes" ]]; then
    out="$(python3 - "$timeout_arg" "$err" "${cmd[@]}" <<'PY'
import subprocess, sys
timeout = float(sys.argv[1])
err_path = sys.argv[2]
cmd = sys.argv[3:]
try:
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, text=True)
    if p.stderr:
        with open(err_path, "w") as f:
            f.write(p.stderr)
    sys.stdout.write(p.stdout or "")
    sys.exit(p.returncode)
except subprocess.TimeoutExpired:
    with open(err_path, "w") as f:
        f.write("Command timed out after %ss\n" % timeout)
    sys.exit(124)
PY
)"
    rc=$?
  else
    out="$("${cmd[@]}" 2>"$err")"
    rc=$?
  fi
  if [[ $rc -ne 0 ]]; then
    echo "error: oci $* failed (exit $rc)" >&2
    sed -e 's/^/oci stderr: /' "$err" >&2
    rm -f "$err"
    return "$rc"
  fi
  rm -f "$err"
  printf "%s" "$out"
}

cluster_ocid=""
cluster_name=""
cluster_k8s=""
compartment_ocid=""

if [[ "$cluster_ref" == ocid1.* ]]; then
  cluster_ocid="$cluster_ref"
else
  # Resolve from kubeconfig
  kubeconfig_path="${kubeconfig_arg:-$HOME/.kube/config}"
  if [[ -f "$kubeconfig_path" ]]; then
    cluster_ocid=$(python3 - "$kubeconfig_path" "$cluster_ref" <<'PY'
import sys, yaml
from pathlib import Path
path = Path(sys.argv[1])
name = sys.argv[2]
try:
    data = yaml.safe_load(path.read_text())
except Exception:
    print("")
    raise SystemExit(0)

contexts = data.get("contexts", []) or []
users = {u.get("name"): u.get("user", {}) for u in (data.get("users", []) or [])}

match_user = None
for c in contexts:
    cname = c.get("name", "")
    if name in cname:
        match_user = (c.get("context", {}) or {}).get("user")
        if match_user:
            break

if not match_user:
    print("")
    raise SystemExit(0)

exec_cfg = users.get(match_user, {}).get("exec", {})
args = exec_cfg.get("args", []) if isinstance(exec_cfg, dict) else []
try:
    idx = args.index("--cluster-id")
    print(args[idx + 1])
except Exception:
    print("")
PY
    )
  fi
fi

if [[ -z "$cluster_ocid" ]]; then
  echo "error: could not resolve cluster OCID from kubeconfig; provide cluster OCID" >&2
  exit 1
fi

# Fetch cluster details if possible
cluster_json=$(oci_json ce cluster get --cluster-id "$cluster_ocid" --query 'data.{name:"name",k8s:"kubernetes-version",compartment:"compartment-id"}' --output json || true)
if [[ -n "$cluster_json" && "$cluster_json" != "{}" ]]; then
  cluster_name=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('name',''))
PY
  <<<"$cluster_json")
  cluster_k8s=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('k8s',''))
PY
  <<<"$cluster_json")
  compartment_ocid=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('compartment',''))
PY
  <<<"$cluster_json")
else
  echo "warning: failed to fetch cluster details; returning partial context" >&2
  cluster_name="$cluster_ref"
fi

# Optional: try to resolve deployment namespace if kubectl is available
deployment_namespace=""
deployment_namespaces=""
if [[ -n "$deployment_name" ]]; then
  if command -v kubectl >/dev/null 2>&1; then
    deployment_namespaces=$(kubectl get deploy -A --no-headers 2>/dev/null | awk -v d="$deployment_name" '$2==d {print $1}' | paste -sd "," -)
    if [[ -n "$deployment_namespaces" ]]; then
      if [[ "$deployment_namespaces" == *,* ]]; then
        deployment_namespace=""
      else
        deployment_namespace="$deployment_namespaces"
      fi
    fi
  else
    echo "warning: kubectl not found; cannot resolve deployment namespace" >&2
  fi
fi

python3 - <<PY
import json
print(json.dumps({
  "cluster": {
    "name": "${cluster_name}",
    "id": "${cluster_ocid}",
    "kubernetes_version": "${cluster_k8s}",
    "compartment_id": "${compartment_ocid}",
    "region": "${region}"
  },
  "deployment": {
    "name": "${deployment_name}",
    "namespace": "${deployment_namespace}",
    "namespaces": "${deployment_namespaces}"
  }
}, indent=2))
PY
