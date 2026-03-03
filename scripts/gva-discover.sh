#!/usr/bin/env bash
set -euo pipefail

# Discover GVA-relevant data for an OKE cluster.
# Usage:
#   ./scripts/gva-discover.sh --cluster <name-or-ocid> [--region <region>] [--compartment-id <ocid>] [--profile <oci-profile>] [--timeout <seconds>]

cluster_ref=""
region_arg=""
compartment_arg=""
profile_arg=""
timeout_arg=""

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
    -h|--help)
      echo "usage: $0 --cluster <name-or-ocid> [--region <region>] [--compartment-id <ocid>] [--profile <oci-profile>] [--timeout <seconds>]" >&2
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

# If cluster ref is OCID, use it directly. Otherwise search by name.
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
  # If a compartment is provided, search only there.
  if [[ -n "$compartment_arg" ]]; then
    hit=$(oci_r ce cluster list --compartment-id "$compartment_arg" --query "data[?name=='$cluster_ref']|[0]" --output json 2>/dev/null || true)
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
      compartment_ocid="$compartment_arg"
    fi
  else
    if [[ -z "$config_tenancy" ]]; then
      echo "tenancy not found in config; cannot search by name" >&2
      exit 2
    fi
    echo "warning: no compartment provided; scanning all compartments" >&2
    compartments_json=$(oci_r iam compartment list --compartment-id "$config_tenancy" --all \
      --query 'data[?"lifecycle-state"==`ACTIVE`].{id:id,name:name}' --output json 2>/dev/null || true)
    if [[ -z "$compartments_json" || "$compartments_json" == "[]" ]]; then
      echo "no compartments found or access denied" >&2
      exit 1
    fi

    found=""
    while read -r cid; do
      if [[ -z "$cid" ]]; then
        continue
      fi
      hit=$(oci_r ce cluster list --compartment-id "$cid" --query "data[?name=='$cluster_ref']|[0]" --output json 2>/dev/null || true)
      if [[ -n "$hit" && "$hit" != "null" ]]; then
        found="$hit"
        compartment_ocid="$cid"
        break
      fi
    done < <(python3 - <<'PY'
import json,sys
try:
    data=json.loads(sys.stdin.read())
except Exception:
    data=[]
for c in data:
    print(c.get('id',''))
PY
    <<<"$compartments_json")

    if [[ -z "$found" ]]; then
      echo "cluster not found by name: $cluster_ref" >&2
      exit 1
    fi

    cluster_ocid=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('id',''))
PY
    <<<"$found")

    cluster_name=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('name',''))
PY
    <<<"$found")

    cluster_k8s=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('kubernetes-version',''))
PY
    <<<"$found")
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
