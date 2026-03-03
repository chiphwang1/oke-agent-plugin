#!/usr/bin/env bash
set -euo pipefail

# Discover GVA-relevant data for an OKE cluster.
# Usage:
#   ./scripts/gva-discover.sh --cluster <name-or-ocid> [--region <region>] [--compartment-id <ocid>] [--profile <oci-profile>] [--timeout <seconds>] [--kubeconfig <path>]

cluster_ref=""
region_arg=""
compartment_arg=""
profile_arg=""
timeout_arg=""
kubeconfig_arg=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      cluster_ref="$2"; shift 2 ;;
    --region)
      region_arg="$2"; shift 2 ;;
    --compartment-id)
      compartment_arg="$2"; shift 2 ;;
    --profile)
      profile_arg="$2"; shift 2 ;;
    --timeout)
      timeout_arg="$2"; shift 2 ;;
    --kubeconfig)
      kubeconfig_arg="$2"; shift 2 ;;
    -h|--help)
      echo "usage: $0 --cluster <name-or-ocid> [--region <region>] [--compartment-id <ocid>] [--profile <oci-profile>] [--timeout <seconds>] [--kubeconfig <path>]" >&2
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

# Read tenancy and default region from OCI config if present
config_file="$HOME/.oci/config"
config_region=""
config_tenancy=""
if [[ -f "$config_file" ]]; then
  config_region=$(awk -F= '/^region=/{print $2; exit}' "$config_file" | tr -d ' ')
  config_tenancy=$(awk -F= '/^tenancy=/{print $2; exit}' "$config_file" | tr -d ' ')
fi

region="${region_arg:-$config_region}"
if [[ -z "$region" ]]; then
  echo "region not provided and not found in config" >&2
  exit 2
fi

# Helper to run oci with region/profile/timeout
have_timeout="no"
if command -v timeout >/dev/null 2>&1; then
  have_timeout="yes"
fi

timeout_prefix=()
if [[ -n "$timeout_arg" && "$have_timeout" == "yes" ]]; then
  timeout_prefix=(timeout "$timeout_arg")
fi

profile_args=()
if [[ -n "$profile_arg" ]]; then
  profile_args=(--profile "$profile_arg")
elif [[ -n "${OCI_CLI_PROFILE:-}" ]]; then
  profile_args=(--profile "$OCI_CLI_PROFILE")
fi

oci_r() {
  "${timeout_prefix[@]}" oci --region "$region" "${profile_args[@]}" "$@"
}

# If cluster ref is OCID, use it directly. Otherwise require compartment to search by name.
cluster_ocid=""
cluster_name=""
cluster_k8s=""
compartment_ocid=""

is_ocid="no"
if [[ "$cluster_ref" == ocid1.* ]]; then
  is_ocid="yes"
fi

if [[ "$is_ocid" == "yes" ]]; then
  cluster_ocid="$cluster_ref"
  cluster_json=$(oci_r ce cluster get --cluster-id "$cluster_ocid" --query 'data.{name:"name",k8s:"kubernetes-version",compartment:"compartment-id"}' --output json 2>/dev/null || true)
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
  fi
else
  # Try to resolve cluster OCID from kubeconfig if no compartment was provided.
  if [[ -z "$compartment_arg" ]]; then
    kubeconfig_path="${kubeconfig_arg:-$HOME/.kube/config}"
    if [[ -f "$kubeconfig_path" ]]; then
      kube_cluster_id=$(python3 - <<'PY'
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
      "$kubeconfig_path" "$cluster_ref")
      if [[ -n "$kube_cluster_id" ]]; then
        cluster_ocid="$kube_cluster_id"
        is_ocid="yes"
      fi
    fi
  fi

  if [[ "$is_ocid" == "yes" ]]; then
    cluster_json=$(oci_r ce cluster get --cluster-id "$cluster_ocid" --query 'data.{name:"name",k8s:"kubernetes-version",compartment:"compartment-id"}' --output json 2>/dev/null || true)
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
    fi
  fi

  # Require a compartment to search by name (avoid tenancy-wide scans).
  if [[ -z "$compartment_arg" && -z "$compartment_ocid" ]]; then
    echo "compartment-id is required when using a cluster name; provide --compartment-id, a cluster OCID, or a kubeconfig with cluster-id" >&2
    exit 2
  fi

  comp_to_search="${compartment_arg:-$compartment_ocid}"
  hit=$(oci_r ce cluster list --compartment-id "$comp_to_search" --query "data[?name=='$cluster_ref']|[0]" --output json 2>/dev/null || true)
  if [[ -n "$hit" && "$hit" != "null" ]]; then
    cluster_ocid=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('id',''))
PY
    <<<"$hit")
    cluster_name=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('name',''))
PY
    <<<"$hit")
    cluster_k8s=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('kubernetes-version',''))
PY
    <<<"$hit")
    compartment_ocid="$comp_to_search"
  fi
fi

if [[ -z "$compartment_ocid" && -n "$compartment_arg" ]]; then
  compartment_ocid="$compartment_arg"
fi

# Pull subnets and NSGs in the compartment
subnets_json="[]"
nsGs_json="[]"
if [[ -n "$compartment_ocid" ]]; then
  subnets_json=$(oci_r network subnet list --compartment-id "$compartment_ocid" --query 'data[*].{"name":"display-name","id":"id","cidr":"cidr-block"}' --output json 2>/dev/null || true)
  nsGs_json=$(oci_r network nsg list --compartment-id "$compartment_ocid" --query 'data[*].{"name":"display-name","id":"id"}' --output json 2>/dev/null || true)
fi

# Output consolidated JSON
python3 - <<PY
import json
out = {
  "cluster": {
    "name": "${cluster_name}",
    "id": "${cluster_ocid}",
    "kubernetes_version": "${cluster_k8s}",
    "compartment_id": "${compartment_ocid}",
    "region": "${region}"
  },
  "subnets": json.loads('''${subnets_json:-[]}''') if '''${subnets_json:-}'''.strip() else [],
  "nsgs": json.loads('''${nsGs_json:-[]}''') if '''${nsGs_json:-}'''.strip() else []
}
print(json.dumps(out, indent=2))
PY
