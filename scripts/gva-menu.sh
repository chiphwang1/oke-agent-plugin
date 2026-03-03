#!/usr/bin/env bash
set -euo pipefail

say() { printf "%s\n" "$*"; }
ask() {
  local prompt="$1" var
  read -r -p "$prompt" var
  printf "%s" "$var"
}

say "GVA Node Pool Builder (OKE)"
say "Answer the prompts to generate an OCI CLI command."

cluster_ocid=$(ask "Cluster OCID: ")
region=$(ask "Region (e.g., us-ashburn-1): ")
compartment_ocid=$(ask "Compartment OCID: ")
ad=$(ask "Availability Domain (e.g., GrCh:US-ASHBURN-AD-1): ")
primary_subnet=$(ask "Primary subnet OCID (node placement subnet): ")

node_pool_name=$(ask "Node pool name: ")
k8s_version=$(ask "Kubernetes version (e.g., v1.34.1): ")
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
image_ocid=$(ask "Image OCID: ")

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
while true; do
  say ""
  say "Add a secondary VNIC profile (GVA tier)"
  app_res=$(ask "  applicationResource (label): ")
  subnet_id=$(ask "  subnetId OCID: ")
  ip_count=$(ask "  ipCount (max 16): ")
  nsg_ids=$(ask "  nsgIds (comma-separated OCIDs, optional): ")
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
say "Generated OCI CLI command:"
cat <<CMD
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

say ""
say "Next steps:"
say "1) Run the command above."
say "2) Verify resources on a node: kubectl describe node <node_name>"
say "3) Deploy a pod requesting one Application Resource and add the taint toleration."
