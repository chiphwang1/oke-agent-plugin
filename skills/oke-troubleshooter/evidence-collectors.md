# `/oke-troubleshooter` — Evidence Collection Recipes

For each diagnostic domain, gather the following evidence. Prefer JSON output (`-o json`) when available. Summaries returned to the parent skill should follow the structure:

```json
{
  "domain": "<domain>",
  "findings": ["Short bullet summary"],
  "raw_snippets": ["Trimmed command output"],
  "anomalies": ["Detected warnings/errors"],
  "fallback_used": false
}
```

When a command fails, set `fallback_used` to `true`, capture stderr (sanitized), and continue with other evidence.

## Pod Scheduling
- **Kubernetes**
  - `kubectl get pods -n <ns> <selector> -o wide`
  - `kubectl describe pod <pod> -n <ns>`
  - `kubectl get events -n <ns> --field-selector involvedObject.name=<pod> --sort-by=.lastTimestamp`
- **OCI**
  - `oci ce node-pool list --compartment-id <compartment>` (ensure node pool capacity)
  - `oci limits resource-availability get --service-name compute --limit-name standard3-count --availability-domain <ad>`
- **Normalization tips**: Highlight scheduling failure reasons (`0/3 nodes available`, taints), summarize resource requests vs. node capacity, include current node pool size.

## Pod Runtime
- **Kubernetes**
  - `kubectl describe pod <pod> -n <ns>`
  - `kubectl logs <pod> -n <ns> --previous` (when restart count > 0)
  - `kubectl get events -n <ns> --field-selector type=Warning`
- **OCI**
  - `oci logging search --time-start <iso> --time-end <iso> --search-query "search <log-group> where podName = '<pod>'"`
- **Normalization tips**: Capture container state (`Waiting`, `CrashLoopBackOff`), include last log lines causing failure, flag missing secrets or configmaps.

## Node Health
- **Kubernetes**
  - `kubectl get nodes -o wide`
  - `kubectl describe node <node>`
  - `kubectl top node <node>` (requires metrics server)
- **OCI**
  - `oci ce node-pool get --node-pool-id <ocid>`
  - `oci compute instance get --instance-id <ocid>`
  - `oci health-check probe-result get --probe-configuration-id <ocid>` (if using health checks)
- **Normalization tips**: Surface conditions not `True`, kubelet versions, OCI lifecycle state, recent maintenance events.

## Networking / CNI / Load Balancer
- **Kubernetes**
  - `kubectl get svc -n <ns> <service> -o yaml`
  - `kubectl get svc -n <ns> <service> -o jsonpath='{.status.loadBalancer.ingress[0].ip}'` (capture LB public IP when type is `LoadBalancer`)
  - `kubectl get ingress -n <ns> <ingress> -o yaml`
  - `kubectl describe networkpolicy -n <ns>`
  - `kubectl get pods -n kube-system -l k8s-app=cilium-agent` (or corresponding CNI)
- **OCI**
  - `oci lb load-balancer list --compartment-id <compartment> --region <region> --all --output json | jq -r '.data[] | select((."ip-addresses" // []) | any(."ip-address"=="<lb-ip>")) | .id'` (resolve LB OCID from service external IP)
  - `oci lb load-balancer get --load-balancer-id <ocid> --region <region>`
  - `oci lb load-balancer get --load-balancer-id <ocid> --region <region> --query 'data."access-log"' --output json` (check whether LB access logging is enabled)
  - `oci logging search search-logs --region <region> --search-query "search \"<log_group_ocid>/<log_ocid>\" | where data.loadBalancerId = '<lb_ocid>' | sort by datetime desc" --time-start <iso-start> --time-end <iso-end>` (when LB logs are enabled)
  - `oci nlb network-load-balancer list --compartment-id <compartment> --region <region> --all --output json | jq -r '.data[] | select((."ip-addresses" // []) | any(."ip-address"=="<lb-ip>")) | .id'` (fallback if classic LB lookup is empty)
  - `oci network nsg list --compartment-id <compartment>`
  - `oci network subnet get --subnet-id <ocid>`
- **Normalization tips**: Note load balancer lifecycle (`PROVISIONING`, `FAILED`), security list/NSG rules, CNI pod status, service annotations impacting provisioning. Explicitly record LB logging status as `enabled`, `disabled`, or `unknown`.
- **If LB logs are disabled or unknown**: recommend enabling access logs before closing the incident so future RCA has request-level evidence.
  - Offer operator action:
    - `No (report only)`
    - `Yes (print enable command)`
    - `Yes (execute enable command now)`
  - Enable command template:
    ```bash
    oci lb load-balancer update \
      --load-balancer-id <lb_ocid> \
      --region <region> \
      --access-log '{"isEnabled":true,"logGroupId":"<log_group_id>","logId":"<log_id>"}'
    ```
  - Post-check:
    ```bash
    oci lb load-balancer get \
      --load-balancer-id <lb_ocid> \
      --region <region> \
      --query 'data."access-log"' \
      --output json
    ```
- **If LB logs are enabled**: summarize concrete issue signals from log lines:
  - 5xx rate and top failing paths/backends
  - timeout/reset/error signatures
  - highest observed latency fields in the selected window

## Application Performance
- **Kubernetes**
  - `kubectl get deployment <deployment> -n <ns> -o yaml`
  - `kubectl describe deployment <deployment> -n <ns>`
  - `kubectl rollout history deployment/<deployment> -n <ns>`
  - `kubectl top pods -n <ns> -l app=<label>` (adjust selector to match deployment)
  - `kubectl get hpa -n <ns> --selector app=<label>` (if autoscaling enabled)
  - `kubectl logs -n <ns> deployment/<deployment> --tail=200` (if structured logging enabled)
- **OCI**
  - `oci monitoring metric-data summarize-metrics-data --namespace oci_computeagent --query-text "CpuUtilization[1m]{resourceId = '<instance-ocid>'}.mean()" --resolution 1m --start-time <iso-start> --end-time <iso-end>`
  - `oci monitoring metric-data summarize-metrics-data --namespace oci_lb --query-text "BackendLatency[1m]{resourceId = '<lb-ocid>'}.p99()" --resolution 1m --start-time <iso-start> --end-time <iso-end>`
  - `oci monitoring alarm-status-summary list --compartment-id <compartment>` (identify triggered performance alarms)
- **Normalization tips**: Compare current replica count vs. desired, highlight recent rollouts, surface CPU/memory saturation, p95/p99 latency spikes, and note absent autoscaling policies.

## Storage / CSI
- **Kubernetes**
  - `kubectl get pvc -n <ns> <claim> -o yaml`
  - `kubectl describe pvc <claim> -n <ns>`
  - `kubectl logs -n kube-system -l app=oci-csi-controller --tail=200`
- **OCI**
  - `oci bv volume get --volume-id <ocid>`
  - `oci fs filesystem get --file-system-id <ocid>` (FSS)
  - `oci limits resource-availability get --service-name block-storage --limit-name block-storage-volumes`
- **Normalization tips**: Extract CSI error codes, quota/limit responses, volume attachment status, and AD placement mismatches.

## Control Plane
- **Kubernetes**
  - `kubectl cluster-info`
  - `kubectl get cs` (API server / scheduler / controller-manager status)
- **OCI**
  - `oci ce cluster get --cluster-id <ocid>`
  - `oci ce cluster-options get --cluster-id <ocid>`
  - `oci logging search` targeting OKE control plane log groups
- **Normalization tips**: Flag `FAILED` or degraded states, endpoint visibility changes, upgrade operations in progress.

## IAM / RBAC
- **Kubernetes**
  - `kubectl auth can-i <verb> <resource> --as <subject> -n <ns>`
  - `kubectl get clusterrolebinding <name> -o yaml`
  - `kubectl describe serviceaccount <name> -n <ns>`
- **OCI**
  - `oci iam policy list --compartment-id <tenancy> --query "data[?contains(statements, 'allow service oke')]" --all`
  - `oci iam dynamic-group list --compartment-id <tenancy>`
- **Normalization tips**: Summarize denied verbs, missing role bindings, IAM policy gaps affecting OCI API access.

## OCI Infrastructure / Quotas
- **OCI**
  - `oci limits resource-availability list --compartment-id <compartment> --service-name <service>`
  - `oci limits quota get --compartment-id <compartment> --quota-id <ocid>`
  - `oci monitoring alarm-status-summary list --compartment-id <compartment>`
- **Normalization tips**: Present remaining vs. used quota, active alarms, recent throttling metrics.

---

When evidence volume is large, trim to the most recent entries and provide links or commands the operator can rerun locally.
