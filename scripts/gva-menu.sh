#!/usr/bin/env bash
set -euo pipefail

say() { printf "%s\n" "$*"; }
ask() {
  local prompt="$1" var
  read -r -p "$prompt" var
  printf "%s" "$var"
}

select_from_list() {
  local prompt="$1"; shift
  local items=("$@")
  local choice=""
  say "$prompt"
  select choice in "${items[@]}" "Manual entry"; do
    if [[ "$choice" == "Manual entry" ]]; then
      choice=""
      break
    elif [[ -n "$choice" ]]; then
      break
    fi
  done
  printf "%s" "$choice"
}

normalize_none() {
  local v="$1"
  case "${v,,}" in
    ""|"0"|"none"|"no"|"n"|"skip") echo "" ;;
    *) echo "$v" ;;
  esac
}

oci_available="yes"
if ! command -v oci >/dev/null 2>&1; then
  oci_available="no"
fi

say "GVA Node Pool Builder (OKE)"
say "Answer the prompts to generate an OCI CLI command."

cluster_name=$(ask "Cluster name (default: cluster3): ")
if [[ -z "$cluster_name" ]]; then
  cluster_name="cluster3"
fi

# Pull defaults from OCI config
config_file="$HOME/.oci/config"
config_region=""
config_tenancy=""
if [[ -f "$config_file" ]]; then
  config_region=$(awk -F= '/^region=/{print $2; exit}' "$config_file" | tr -d ' ')
  config_tenancy=$(awk -F= '/^tenancy=/{print $2; exit}' "$config_file" | tr -d ' ')
fi

region=$(ask "Region (default: ${config_region:-none}): ")
if [[ -z "$region" && -n "$config_region" ]]; then
  region="$config_region"
fi

profile_name=$(ask "OCI CLI profile (optional): ")

# Try to resolve cluster OCID from kubeconfig
kubeconfig_path="$HOME/.kube/config"
cluster_ocid=""
if [[ -f "$kubeconfig_path" ]]; then
  cluster_ocid=$(python3 - "$kubeconfig_path" "$cluster_name" <<'PY'
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

if [[ -z "$cluster_ocid" ]]; then
  cluster_ocid=$(ask "Cluster OCID (not found in kubeconfig): ")
else
  say "Detected cluster OCID from kubeconfig."
fi

compartment_ocid=""
discovery_json=""
if [[ "$oci_available" == "yes" ]]; then
  discover_cmd=(./scripts/gva-discover.sh --cluster "$cluster_ocid" --timeout 10)
  if [[ -n "$region" ]]; then
    discover_cmd+=(--region "$region")
  fi
  if [[ -n "$profile_name" ]]; then
    discover_cmd+=(--profile "$profile_name")
  fi
  discovery_json=$("${discover_cmd[@]}" 2>/dev/null || true)
fi

cluster_k8s=""
subnet_lines=()
nsg_lines=()

if [[ -n "$discovery_json" ]]; then
  cluster_k8s=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('cluster',{}).get('kubernetes_version',''))
PY
  <<<"$discovery_json")

  comp_from_discovery=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('cluster',{}).get('compartment_id',''))
PY
  <<<"$discovery_json")

  region_from_discovery=$(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
print(d.get('cluster',{}).get('region',''))
PY
  <<<"$discovery_json")

  if [[ -z "$compartment_ocid" && -n "$comp_from_discovery" ]]; then
    compartment_ocid="$comp_from_discovery"
  fi
  if [[ -z "$region" && -n "$region_from_discovery" ]]; then
    region="$region_from_discovery"
  fi

  mapfile -t subnet_lines < <(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
for s in d.get('subnets',[]):
    name=s.get('name') or ''
    sid=s.get('id') or ''
    cidr=s.get('cidr') or ''
    if name and sid:
        print(f"{name} | {cidr} | {sid}")
PY
  <<<"$discovery_json")

  mapfile -t nsg_lines < <(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
for n in d.get('nsgs',[]):
    name=n.get('name') or ''
    nid=n.get('id') or ''
    if name and nid:
        print(f"{name} | {nid}")
PY
  <<<"$discovery_json")
fi

if [[ -z "$region" ]]; then
  region=$(ask "Region (e.g., us-ashburn-1): ")
fi

if [[ -z "$compartment_ocid" ]]; then
  compartment_ocid=$(ask "Compartment OCID: ")
fi

ad=$(ask "Availability Domain (e.g., GrCh:US-ASHBURN-AD-1): ")

vcn_id=""
if [[ "$oci_available" == "yes" && -n "$compartment_ocid" ]]; then
  vcn_json=$(oci network vcn list --compartment-id "$compartment_ocid" --region "$region" --query 'data[*].{name:"display-name",id:id,cidr:"cidr-block"}' --output json 2>/dev/null || true)
  if [[ -n "$vcn_json" && "$vcn_json" != "[]" ]]; then
    mapfile -t vcn_lines < <(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
for v in d if isinstance(d, list) else []:
    name=v.get('name') or ''
    vid=v.get('id') or ''
    cidr=v.get('cidr') or ''
    if name and vid:
        print(f"{name} | {cidr} | {vid}")
PY
    <<<"$vcn_json")
  fi
fi

if [[ ${#vcn_lines[@]} -eq 1 ]]; then
  vcn_id=$(printf "%s" "${vcn_lines[0]}" | cut -d'|' -f3 | xargs)
  say "Auto-selected VCN: ${vcn_lines[0]}"
elif [[ ${#vcn_lines[@]} -gt 0 ]]; then
  selection=$(select_from_list "Select VCN:" "${vcn_lines[@]}")
  if [[ -n "$selection" ]]; then
    vcn_id=$(printf "%s" "$selection" | cut -d'|' -f3 | xargs)
  fi
fi

if [[ -n "$vcn_id" ]]; then
  subnet_lines=()
  subnet_json=$(oci network subnet list --compartment-id "$compartment_ocid" --vcn-id "$vcn_id" --region "$region" --query 'data[*].{"name":"display-name","id":"id","cidr":"cidr-block"}' --output json 2>/dev/null || true)
  if [[ -n "$subnet_json" && "$subnet_json" != "[]" ]]; then
    mapfile -t subnet_lines < <(python3 - <<'PY'
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d={}
for s in d.get('data', d) if isinstance(d, dict) else d:
    name=s.get('name') or s.get('display-name') or ''
    sid=s.get('id') or ''
    cidr=s.get('cidr') or s.get('cidr-block') or ''
    if name and sid:
        print(f"{name} | {cidr} | {sid}")
PY
    <<<"$subnet_json")
  fi
fi

primary_subnet=""
if [[ ${#subnet_lines[@]} -gt 0 ]]; then
  selection=$(select_from_list "Select primary subnet (node placement):" "${subnet_lines[@]}")
  if [[ -n "$selection" ]]; then
    primary_subnet=$(printf "%s" "$selection" | cut -d'|' -f3 | xargs)
  fi
fi
if [[ -z "$primary_subnet" ]]; then
  primary_subnet=$(ask "Primary subnet OCID (node placement subnet): ")
fi

node_pool_name=$(ask "Node pool name: ")

k8s_version=""
if [[ -n "$cluster_k8s" ]]; then
  k8s_version=$cluster_k8s
  say "Using cluster Kubernetes version: $k8s_version"
fi
if [[ -z "$k8s_version" ]]; then
  k8s_version=$(ask "Kubernetes version (e.g., v1.34.1): ")
fi

shape=$(ask "Node shape (e.g., VM.Standard.E5.Flex): ")

type_is_flex="no"
case "$shape" in
  *.Flex) type_is_flex="yes" ;;
  *) type_is_flex="no" ;;
 esac

ocpus=""
mem_gb=""
if [[ "$type_is_flex" == "yes" ]]; then
  ocpus=$(ask "OCPUs per node: ")
  mem_gb=$(ask "Memory GB per node: ")
fi

node_count=$(ask "Node count: ")

# Image selection: list images for k8s version and prompt
image_ocid=""
if [[ "$oci_available" == "yes" && -n "$k8s_version" ]]; then
  img_json=$(oci ce node-pool-options get --node-pool-option-id all --region "$region" --query 'data.sources[*].{"image":"image-id","name":"source-name"}' --output json 2>/dev/null || true)
  if [[ -n "$img_json" && "$img_json" != "[]" ]]; then
    mapfile -t img_lines < <(python3 - <<'PY'
import json,sys,re
try:
    d=json.loads(sys.stdin.read())
except Exception:
    d=[]
pattern=re.compile(rf'OKE-{re.escape(sys.argv[1])}')
items=[x for x in d if pattern.search(x.get('name',''))]
for x in items:
    print(f"{x.get('name')} | {x.get('image')}")
PY
    <<<"$img_json" "$k8s_version")
    if [[ ${#img_lines[@]} -gt 0 ]]; then
      selection=$(select_from_list "Select OKE image for $k8s_version:" "${img_lines[@]}")
      if [[ -n "$selection" ]]; then
        image_ocid=$(printf "%s" "$selection" | cut -d'|' -f2 | xargs)
      fi
    fi
  fi
fi

if [[ -z "$image_ocid" ]]; then
  image_ocid=$(ask "Image OCID: ")
fi

say ""
say "CNI must be OCI_VCN_IP_NATIVE for GVA."
select cni_ok in "Yes" "No"; do
  case "$cni_ok" in
    Yes) break ;;
    No)
      say "GVA is unsupported without OCI_VCN_IP_NATIVE. Exiting."
      exit 1
      ;;
  esac
 done

# Collect VNIC profiles
profiles=()
profile_summaries=()
while true; do
  say ""
  say "Add a secondary VNIC profile (GVA tier)"
  app_res=$(ask "  applicationResource (label): ")

  subnet_id=""
  if [[ ${#subnet_lines[@]} -gt 0 ]]; then
    selection=$(select_from_list "  Select subnet for this profile:" "${subnet_lines[@]}")
    if [[ -n "$selection" ]]; then
      subnet_id=$(printf "%s" "$selection" | cut -d'|' -f3 | xargs)
    fi
  fi
  if [[ -z "$subnet_id" ]]; then
    subnet_id=$(ask "  subnetId OCID: ")
  fi

  ip_count=$(ask "  ipCount (max 16): ")

  nsg_ids=""
  if [[ ${#nsg_lines[@]} -gt 0 ]]; then
    selection=$(select_from_list "  Select NSG (or type none):" "${nsg_lines[@]}")
    nsg_ids=$(normalize_none "$selection")
  else
    nsg_ids=$(normalize_none "$(ask "  nsgIds (comma-separated OCIDs, optional): ")")
  fi

  display_name=$(ask "  displayName (optional): ")

  # Build JSON object
  nsg_json="null"
  if [[ -n "$nsg_ids" ]]; then
    IFS=',' read -r -a nsg_arr <<< "$nsg_ids"
    nsg_json="["
    for i in "${!nsg_arr[@]}"; do
      nsg_arr[$i]="${nsg_arr[$i]// /}"
      nsg_json+="\"${nsg_arr[$i]}\""
      if [[ $i -lt $((${#nsg_arr[@]}-1)) ]]; then
        nsg_json+=",";
      fi
    done
    nsg_json+="]"
  fi

  display_field="null"
  if [[ -n "$display_name" ]]; then
    display_field="\"$display_name\""
  fi

  profiles+=("{\"createVnicDetails\":{\"ipCount\":$ip_count,\"applicationResources\":[\"$app_res\"],\"assignPublicIp\":false,\"displayName\":$display_field,\"nsgIds\":$nsg_json,\"subnetId\":\"$subnet_id\",\"skipSourceDestCheck\":false},\"displayName\":$display_field}")
  profile_summaries+=("$app_res | ipCount=$ip_count | subnet=$subnet_id")

  say ""
  select more in "Add another profile" "Finish"; do
    case "$more" in
      "Add another profile") break ;;
      "Finish") more=""; break 2 ;;
    esac
  done
 done

secondary_vnics_json="["
for i in "${!profiles[@]}"; do
  secondary_vnics_json+="${profiles[$i]}"
  if [[ $i -lt $((${#profiles[@]}-1)) ]]; then
    secondary_vnics_json+=",";
  fi
 done
secondary_vnics_json+="]"

# Build node shape config
shape_config="{}"
if [[ "$type_is_flex" == "yes" ]]; then
  shape_config="{\"ocpus\":$ocpus,\"memoryInGBs\":$mem_gb}"
fi

say ""
say "Summary:"
say "- Cluster: $cluster_name"
say "- Cluster OCID: $cluster_ocid"
say "- Region: $region"
say "- Compartment: $compartment_ocid"
say "- AD: $ad"
say "- Node pool: $node_pool_name"
say "- Shape: $shape"
say "- Node count: $node_count"
say "- K8s version: $k8s_version"
say "- Primary subnet: $primary_subnet"
for p in "${profile_summaries[@]}"; do
  say "- VNIC: $p"
 done

say ""
say "Choose next action:"
say "1) Run command now"
say "2) Print command only"
say "3) Exit without output"
choice=$(ask "Select (1/2/3): ")

if [[ "$choice" == "1" ]]; then
  run_now="yes"
elif [[ "$choice" == "2" ]]; then
  run_now="no"
elif [[ "$choice" == "3" ]]; then
  say "Aborted."
  exit 0
else
  say "Unknown choice; printing command only."
  run_now="no"
fi

say ""
say "Generated OCI CLI command:"
cmd_text=$(cat <<CMD
oci ce node-pool create \
  --compartment-id "$compartment_ocid" \
  --cluster-id "$cluster_ocid" \
  --name "$node_pool_name" \
  --kubernetes-version "$k8s_version" \
  --node-shape "$shape" \
  --node-shape-config '$shape_config' \
  --size $node_count \
  --cni-type OCI_VCN_IP_NATIVE \
  --placement-configs '[{"availabilityDomain":"$ad","subnetId":"$primary_subnet"}]' \
  --node-source-details '{"sourceType":"IMAGE","imageId":"$image_ocid"}' \
  --secondary-vnics '$secondary_vnics_json'
CMD
)

echo "$cmd_text"

if [[ "$run_now" == "yes" ]]; then
  say ""
  say "Running command..."
  eval "$cmd_text"
fi

say ""
say "Sample test Deployment (replace ResourceName/image):"
cat <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gva-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gva-test
  template:
    metadata:
      labels:
        app: gva-test
    spec:
      tolerations:
        - key: "oci.oraclecloud.com/application-resource-only"
          operator: "Exists"
          effect: "NoSchedule"
      containers:
        - name: app
          image: <image>
          resources:
            requests:
              oke-application-resource.oci.oraclecloud.com/ResourceName: "1"
            limits:
              oke-application-resource.oci.oraclecloud.com/ResourceName: "1"
YAML

say ""
say "Next steps:"
say "1) Verify resources on a node: kubectl describe node <node_name>"
say "2) Apply the test Deployment (with your chosen ResourceName)."
