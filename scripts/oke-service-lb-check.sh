#!/usr/bin/env bash
set -euo pipefail

# Collect Kubernetes Service and OCI load balancer provisioning evidence.
#
# Usage:
#   bash scripts/oke-service-lb-check.sh --namespace <ns> --service <name> [--region <region>] [--compartment-id <ocid>]

namespace=""
service=""
region=""
compartment_id=""

emit_error() {
  local exit_code="$1"; local error_code="$2"; local message="$3"; local remediation="$4"
  printf '{"error_code":"%s","message":"%s","remediation":"%s","docs_url":""}\n' "$error_code" "$message" "$remediation" >&2
  exit "$exit_code"
}

require_value() {
  local flag="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
    emit_error 2 "INVALID_ARGUMENT" "Missing value for ${flag}." "Run with --help to view usage."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace|-n) require_value "$1" "${2:-}"; namespace="$2"; shift 2 ;;
    --service) require_value "$1" "${2:-}"; service="$2"; shift 2 ;;
    --region) require_value "$1" "${2:-}"; region="$2"; shift 2 ;;
    --compartment-id) require_value "$1" "${2:-}"; compartment_id="$2"; shift 2 ;;
    -h|--help)
      echo "usage: oke-service-lb-check.sh --namespace <ns> --service <name> [--region <region>] [--compartment-id <ocid>]"
      exit 0 ;;
    *) emit_error 2 "UNKNOWN_ARGUMENT" "Unknown argument: $1." "Run with --help to view usage." ;;
  esac
done

if [[ -z "$namespace" || -z "$service" ]]; then
  emit_error 2 "MISSING_REQUIRED_ARGUMENT" "Missing --namespace or --service." "Provide both --namespace and --service."
fi
command -v kubectl >/dev/null 2>&1 || emit_error 2 "KUBECTL_NOT_INSTALLED" "kubectl is not installed or not on PATH." "Install kubectl and retry."

tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
records="$tmp_dir/records.jsonl"; : > "$records"

record_check() {
  local name="$1"; local kind="$2"; local cmd="$3"; local rc="$4"; local out="$5"
  NAME="$name" KIND="$kind" CMD="$cmd" RC="$rc" OUT="$out" python3 - "$records" <<'PY'
import json, os, sys
with open(sys.argv[1], "a") as f:
    f.write(json.dumps({
        "name": os.environ["NAME"],
        "kind": os.environ["KIND"],
        "cmd": os.environ["CMD"],
        "rc": int(os.environ["RC"]),
        "output": os.environ["OUT"][-6000:],
    }) + "\n")
PY
}

run_check() {
  local name="$1"; local kind="$2"; shift 2
  local out rc
  set +e; out="$("$@" 2>&1)"; rc=$?; set -e
  record_check "$name" "$kind" "$*" "$rc" "$out"
}

run_check "service yaml" "k8s_service" kubectl -n "$namespace" get svc "$service" -o yaml
run_check "service describe" "k8s_service_describe" kubectl -n "$namespace" describe service "$service"
run_check "service endpoints" "k8s_endpoints" kubectl -n "$namespace" get endpoints "$service" -o yaml
run_check "service endpointslices" "k8s_endpointslices" kubectl -n "$namespace" get endpointslices -l "kubernetes.io/service-name=$service" -o yaml
run_check "service events" "k8s_events" kubectl -n "$namespace" get events --field-selector "involvedObject.kind=Service,involvedObject.name=$service" --sort-by=.lastTimestamp

oci_available="no"
if command -v oci >/dev/null 2>&1; then
  oci_available="yes"
fi

if [[ "$oci_available" == "yes" && -n "$region" && -n "$compartment_id" ]]; then
  run_check "load balancers" "oci_lbs" oci --region "$region" lb load-balancer list --compartment-id "$compartment_id" --all --output json
  run_check "network load balancers" "oci_nlbs" oci --region "$region" nlb network-load-balancer list --compartment-id "$compartment_id" --all --output json
  run_check "network security groups" "oci_nsgs" oci --region "$region" network nsg list --compartment-id "$compartment_id" --all --output json
fi

python3 - "$records" "$namespace" "$service" "$region" "$compartment_id" "$oci_available" <<'PY'
import json
import re
import sys
from pathlib import Path

records = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines() if line.strip()]
namespace, service, region, compartment_id, oci_available = sys.argv[2:7]

signal_pat = re.compile(
    r"(LoadBalancer|External-IP|EXTERNAL-IP|pending|SyncLoadBalancerFailed|EnsuringLoadBalancer|"
    r"CreatingLoadBalancer|Failed|Error|Warning|Unhealthy|backend|listener|subnet|NSG|security|"
    r"quota|limit|shape|certificate|annotation|ip-address|network load balancer)",
    re.I,
)
pending_pat = re.compile(r"(<pending>|pending|loadbalancer ingress:\s*$|ingress:\s*\[\])", re.I)
lb_type_pat = re.compile(r"^\s*type:\s*LoadBalancer\s*$", re.M)
lb_ip_pat = re.compile(r"\b(ip|hostname):\s*([^\s]+)")

findings, anomalies, snippets = [], [], []
service_is_lb = False
lb_targets = set()

for item in records:
    out = item["output"].strip()
    findings.append(f"{item['name']} {'collected' if item['rc'] == 0 else 'failed'}")
    if item["rc"] != 0:
        anomalies.append(f"{item['name']} failed with rc={item['rc']}")
    if not out:
        continue
    snippets.append(f"$ {item['cmd']}\n{out[-1000:]}")
    if item["kind"] == "k8s_service" and lb_type_pat.search(out):
        service_is_lb = True
    for match in lb_ip_pat.finditer(out):
        lb_targets.add(match.group(2).strip('"'))
    if pending_pat.search(out):
        anomalies.append(f"{item['name']}: Service load balancer appears pending or has no published ingress")
    for line in out.splitlines():
        if signal_pat.search(line):
            anomalies.append(f"{item['name']}: {line.strip()[:240]}")

if not service_is_lb:
    findings.append("service type is not confirmed as LoadBalancer")
if oci_available == "yes" and (not region or not compartment_id):
    findings.append("OCI load balancer inventory skipped because region or compartment_id was not provided")
elif oci_available != "yes":
    findings.append("OCI load balancer inventory skipped because OCI CLI is unavailable")

print(json.dumps({
    "domain": "Networking / CNI / Load Balancer",
    "namespace": namespace,
    "service": service,
    "region": region,
    "compartment_id": compartment_id,
    "service_is_load_balancer": service_is_lb,
    "load_balancer_targets": sorted(lb_targets),
    "findings": findings,
    "anomalies": anomalies,
    "raw_snippets": snippets[-12:],
    "fallback_used": any(item["rc"] != 0 for item in records) or not (oci_available == "yes" and region and compartment_id),
}, indent=2))
PY
