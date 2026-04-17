#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $msg (expected=$expected actual=$actual)" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: $msg (missing: $needle)" >&2
    exit 1
  fi
}

assert_json_expr() {
  local json="$1"
  local expr="$2"
  local msg="$3"
  if ! JSON_INPUT="$json" EXPR="$expr" python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["JSON_INPUT"])
expr = os.environ["EXPR"]
if not eval(expr, {"obj": obj}):
    raise SystemExit(1)
PY
  then
    echo "FAIL: $msg" >&2
    exit 1
  fi
}

make_mocks() {
  local dir="$1"
  mkdir -p "$dir"

  cat > "$dir/oci" <<'MOCK_OCI'
#!/usr/bin/env bash
set -euo pipefail

args=("$@")
trimmed=()
idx=0
while [[ $idx -lt ${#args[@]} ]]; do
  case "${args[$idx]}" in
    --region|--profile)
      idx=$((idx+2))
      ;;
    *)
      trimmed+=("${args[$idx]}")
      idx=$((idx+1))
      ;;
  esac
done

cmd="${trimmed[*]}"

if [[ "$cmd" == iam\ region-subscription\ list* ]]; then
  if [[ "${MOCK_OCI_AUTH_FAIL:-0}" == "1" ]]; then
    echo "Not authenticated" >&2
    exit 1
  fi
  cat <<'JSON'
{"data":[{"region-name":"us-ashburn-1","status":"READY","is-home-region":true,"tenancy-id":"ocid1.tenancy.oc1..tenancy"}]}
JSON
  exit 0
fi

if [[ "$cmd" == iam\ compartment\ list* ]]; then
  cat <<'JSON'
{"data":[{"name":"team-a","id":"ocid1.compartment.oc1..a","compartment-id":"ocid1.tenancy.oc1..tenancy"}]}
JSON
  exit 0
fi

if [[ "$cmd" == ce\ cluster\ get* ]]; then
  if [[ "${MOCK_OCI_CLUSTER_GET_FAIL:-0}" == "1" ]]; then
    echo "cluster get failed" >&2
    exit 2
  fi
  cluster_id=""
  for ((i=0; i<${#trimmed[@]}; i++)); do
    if [[ "${trimmed[$i]}" == "--cluster-id" && $((i+1)) -lt ${#trimmed[@]} ]]; then
      cluster_id="${trimmed[$((i+1))]}"
      break
    fi
  done
  name="cluster-from-get"
  if [[ -n "${MOCK_OCI_CLUSTER_GET_NAME:-}" ]]; then
    name="${MOCK_OCI_CLUSTER_GET_NAME}"
  fi
  cat <<JSON
{"name":"$name","k8s":"v1.31.1","compartment":"ocid1.compartment.oc1..a","data":{"name":"$name","kubernetes-version":"v1.31.1","compartment-id":"ocid1.compartment.oc1..a","id":"$cluster_id"}}
JSON
  exit 0
fi

if [[ "$cmd" == ce\ cluster\ list* ]]; then
  if [[ -n "${MOCK_OCI_CLUSTER_LIST_JSON:-}" ]]; then
    printf '%s\n' "$MOCK_OCI_CLUSTER_LIST_JSON"
  else
    cat <<'JSON'
{"data":[{"name":"default-cluster","id":"ocid1.cluster.oc1..default","kubernetes-version":"v1.30.1"}]}
JSON
  fi
  exit 0
fi

if [[ "$cmd" == network\ subnet\ list* ]]; then
  echo '{"data":[]}'
  exit 0
fi

if [[ "$cmd" == network\ nsg\ list* ]]; then
  echo '{"data":[]}'
  exit 0
fi

echo "unexpected oci args: $*" >&2
exit 9
MOCK_OCI

  cat > "$dir/kubectl" <<'MOCK_KUBECTL'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${MOCK_KUBECTL_LOG:-}" ]]; then
  printf '%s\n' "$*" >> "$MOCK_KUBECTL_LOG"
fi

if [[ "$*" == *" debug node/"* ]]; then
  echo "Creating debugging pod nd-123 with container debugger on node."
  echo "Running node doctor..."
  echo "PASS kernel"
  echo "0 Signal(s) generated"
  exit 0
fi

if [[ "$*" == *" delete pod "* ]]; then
  echo "pod \"nd-123\" deleted"
  exit 0
fi

echo "unexpected kubectl args: $*" >&2
exit 8
MOCK_KUBECTL

  chmod +x "$dir/oci" "$dir/kubectl"
}

with_temp_home() {
  local home_dir="$1"
  mkdir -p "$home_dir/.oci"
  cat > "$home_dir/.oci/config" <<'CFG'
[DEFAULT]
user=ocid1.user.oc1..u
fingerprint=00:11
key_file=/tmp/fake.pem
tenancy=ocid1.tenancy.oc1..tenancy
region=us-ashburn-1
CFG
}

run_test_preflight() {
  echo "- preflight-check JSON contract"
  local out err rc
  set +e
  out="$("$REPO_ROOT/scripts/preflight-check.sh" 2>"$TMPDIR_BASE/t1.err")"
  rc=$?
  set -e
  if [[ "$rc" != "0" ]]; then
    echo "preflight stderr:"
    cat "$TMPDIR_BASE/t1.err"
  fi
  assert_eq "0" "$rc" "preflight-check exits 0"
  err="$(cat "$TMPDIR_BASE/t1.err")"
  assert_eq "" "$err" "preflight-check stderr empty on success"
  assert_json_expr "$out" "obj['tenancy_ocid'].startswith('ocid1.tenancy')" "preflight has tenancy_ocid"
  assert_json_expr "$out" "len(obj['regions']) >= 1" "preflight has regions"
  assert_json_expr "$out" "obj['compartments'][0]['name'] == 'root (tenancy)'" "preflight prepends root compartment"
}

run_test_gva_discover_cluster_get_failure() {
  echo "- gva-discover handles cluster get failure without crashing"
  local out rc
  set +e
  out="$(MOCK_OCI_CLUSTER_GET_FAIL=1 "$REPO_ROOT/scripts/gva-discover.sh" --cluster ocid1.cluster.oc1..abc 2>"$TMPDIR_BASE/t2.err")"
  rc=$?
  set -e
  assert_eq "0" "$rc" "gva-discover still exits 0 on cluster-get failure path"
  assert_json_expr "$out" "obj['cluster']['id'] == 'ocid1.cluster.oc1..abc'" "gva-discover preserves cluster id"
  assert_json_expr "$out" "obj['cluster']['region'] == 'us-ashburn-1'" "gva-discover preserves region"
}

run_test_oke_discover_cluster_get_failure() {
  echo "- oke-discover returns partial context on cluster get failure"
  local out rc
  set +e
  out="$(MOCK_OCI_CLUSTER_GET_FAIL=1 "$REPO_ROOT/scripts/oke-discover.sh" --cluster ocid1.cluster.oc1..abc 2>"$TMPDIR_BASE/t3.err")"
  rc=$?
  set -e
  assert_eq "0" "$rc" "oke-discover exits 0 with partial context"
  assert_json_expr "$out" "obj['cluster']['id'] == 'ocid1.cluster.oc1..abc'" "oke-discover preserves cluster id"
  assert_json_expr "$out" "obj['cluster']['name'] == 'ocid1.cluster.oc1..abc'" "oke-discover uses ref name on failure"
}

run_test_node_doctor_namespace() {
  echo "- node-doctor uses namespace consistently and no -it"
  local log_file out rc
  log_file="$TMPDIR_BASE/kubectl.log"
  : > "$log_file"
  set +e
  out="$(MOCK_KUBECTL_LOG="$log_file" "$REPO_ROOT/scripts/node-doctor-run.sh" --node n1 --image img --namespace kube-system --cleanup true 2>"$TMPDIR_BASE/t4.err")"
  rc=$?
  set -e
  assert_eq "0" "$rc" "node-doctor exits 0"
  assert_json_expr "$out" "obj['node_doctor_namespace'] == 'kube-system'" "node-doctor JSON namespace"
  local logs
  logs="$(cat "$log_file")"
  assert_contains "$logs" "-n kube-system debug node/n1" "kubectl debug uses requested namespace"
  assert_contains "$logs" "-n kube-system delete pod nd-123" "cleanup uses same namespace"
  if [[ "$logs" == *" -it "* ]]; then
    echo "FAIL: kubectl debug should not include -it" >&2
    exit 1
  fi
}

run_test_gva_discover_quoted_cluster_name() {
  echo "- gva-discover resolves cluster names containing single quotes"
  local out rc cluster_list_json
  cluster_list_json='{"data":[{"name":"prod'\''cluster","id":"ocid1.cluster.oc1..quoted","kubernetes-version":"v1.31.1"}]}'
  set +e
  out="$(MOCK_OCI_CLUSTER_LIST_JSON="$cluster_list_json" "$REPO_ROOT/scripts/gva-discover.sh" --cluster "prod'cluster" --compartment-id ocid1.compartment.oc1..a --region us-ashburn-1 2>"$TMPDIR_BASE/t5.err")"
  rc=$?
  set -e
  assert_eq "0" "$rc" "gva-discover handles quoted cluster name"
  assert_json_expr "$out" "obj['cluster']['id'] == 'ocid1.cluster.oc1..quoted'" "quoted cluster resolved correctly"
}

run_test_gva_cli_resolve_uses_env_override() {
  echo "- gva-cli-resolve honors OKE_GVA_CLI_HOME"
  local custom_home out
  custom_home="$TMPDIR_BASE/custom-gva-cli"
  mkdir -p "$custom_home/bin"
  touch "$custom_home/bin/activate"
  touch "$custom_home/oci_cli-3.65.2+preview.1.1355-py2.py3-none-any.whl"
  out="$(OKE_GVA_CLI_HOME="$custom_home" "$REPO_ROOT/scripts/gva-cli-resolve.sh" --json)"
  assert_json_expr "$out" "obj['home'].endswith('/custom-gva-cli')" "gva-cli-resolve prefers env override"
  assert_json_expr "$out" "obj['has_activate'] is True" "gva-cli-resolve sees activate path"
  assert_json_expr "$out" "obj['has_wheel'] is True" "gva-cli-resolve sees wheel path"
}

run_test_gva_menu_rejects_invalid_ipcount() {
  echo "- gva-menu rejects ipCount values outside 1..256"
  local out rc
  set +e
  out="$(printf 'cluster-a\n\n\nocid1.cluster.oc1..abc\nGrCh:US-ASHBURN-AD-1\nocid1.subnet.oc1..primary\npool1\nVM.Standard.E5.Flex\n2\n16\n3\nocid1.image.oc1..img\n1\nfrontend\nocid1.subnet.oc1..secondary\n257\n256\n\nfrontend-vnic\n2\n\n2\n' | "$REPO_ROOT/scripts/gva-menu.sh" 2>"$TMPDIR_BASE/t6.err")"
  rc=$?
  set -e
  assert_eq "0" "$rc" "gva-menu still completes after retrying ipCount"
  assert_contains "$out" "ipCount must be an integer between 1 and 256." "gva-menu warns on invalid ipCount"
  assert_contains "$out" "Using cluster Kubernetes version: v1.31.1" "gva-menu still consumes discovery output"
  assert_contains "$out" "--secondary-vnics" "gva-menu still prints command after correction"
}

run_test_troubleshooter_skill_has_local_fallback() {
  echo "- troubleshooter skill documents local fallback when delegation is unavailable"
  local body
  body="$(cat "$REPO_ROOT/skills/oke-troubleshooter/SKILL.md")"
  assert_contains "$body" "Default to **local execution in the parent skill**." "troubleshooter skill declares local execution default"
  assert_contains "$body" 'If delegation is available, you may hand the payload to `oke-evidence-collector`.' "troubleshooter skill treats evidence agent as optional"
  assert_contains "$body" "Otherwise rank hypotheses locally using this rubric:" "troubleshooter skill includes local ranking rubric"
}

run_test_troubleshooter_control_plane_recipe_uses_readyz() {
  echo "- troubleshooter control-plane recipe uses readyz/livez instead of kubectl get cs"
  local body
  body="$(cat "$REPO_ROOT/skills/oke-troubleshooter/evidence-collectors.md")"
  assert_contains "$body" "kubectl get --raw='/readyz?verbose'" "control-plane recipe uses readyz"
  assert_contains "$body" "kubectl get --raw='/livez?verbose'" "control-plane recipe uses livez"
  if [[ "$body" == *"kubectl get cs"* ]]; then
    echo "FAIL: control-plane recipe should not use deprecated kubectl get cs" >&2
    exit 1
  fi
}

main() {
  TMPDIR_BASE="$(mktemp -d)"
  if [[ "${KEEP_TMPDIR:-0}" == "1" ]]; then
    echo "KEEP_TMPDIR at: $TMPDIR_BASE"
  else
    trap 'rm -rf "$TMPDIR_BASE"' EXIT
  fi

  make_mocks "$TMPDIR_BASE/mockbin"
  with_temp_home "$TMPDIR_BASE/home"

  export PATH="$TMPDIR_BASE/mockbin:$PATH"
  export HOME="$TMPDIR_BASE/home"

  run_test_preflight
  run_test_gva_discover_cluster_get_failure
  run_test_oke_discover_cluster_get_failure
  run_test_node_doctor_namespace
  run_test_gva_discover_quoted_cluster_name
  run_test_gva_cli_resolve_uses_env_override
  run_test_gva_menu_rejects_invalid_ipcount
  run_test_troubleshooter_skill_has_local_fallback
  run_test_troubleshooter_control_plane_recipe_uses_readyz

  echo "All smoke tests passed."
}

main "$@"
