# OCI Resource Mapping Cheatsheet

Use these command chains to relate Kubernetes objects to Oracle Cloud Infrastructure resources during troubleshooting.

## Pod → Node → Instance
1. Identify the node hosting the pod:
   ```bash
   kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.nodeName}'
   ```
2. Fetch node annotations for the instance OCID:
   ```bash
   kubectl get node <node> -o jsonpath='{.metadata.annotations."node\.oci\.oraclecloud\.com/instance-id"}'
   ```
3. Inspect the OCI instance:
   ```bash
   oci compute instance get --instance-id <instance-ocid>
   ```

## Service / Ingress → Load Balancer
1. Obtain OCI load balancer OCID from annotations:
   ```bash
   kubectl get svc <service> -n <ns> -o jsonpath='{.metadata.annotations."oci\.oraclecloud\.com/load-balancer-id"}'
   ```
2. Describe load balancer health:
   ```bash
   oci network load-balancer get --load-balancer-id <lb-ocid>
   ```
3. Review backend set health:
   ```bash
   oci network load-balancer backend-set-health get \
     --load-balancer-id <lb-ocid> \
     --backend-set-name <backend-set>
   ```

## PersistentVolumeClaim → Block Volume / File System
1. Retrieve PV name and volume handle:
   ```bash
   kubectl get pvc <claim> -n <ns> -o jsonpath='{.spec.volumeName} {.spec.volumeHandle}'
   ```
2. If Block Volume:
   ```bash
   oci bv volume get --volume-id <volume-ocid>
   ```
   For attachment details:
   ```bash
   oci compute volume-attachment list --compartment-id <compartment> --volume-id <volume-ocid>
   ```
3. If File Storage (FSS):
   ```bash
   oci fs file-system get --file-system-id <filesystem-ocid>
   ```

## Namespace / Service Account → IAM Policies
1. Determine dynamic group mapping:
   ```bash
   oci iam dynamic-group list --query "data[].{name:name, matchingRule:matchingRule}" --all
   ```
2. Locate relevant IAM policy statements:
   ```bash
   oci iam policy list --compartment-id <tenancy-ocid> --all \
     --query "data[].{name:name, statements:statements}"
   ```
3. Cross-check Kubernetes service account annotations (workload identity):
   ```bash
   kubectl get serviceaccount <sa> -n <ns> -o yaml
   ```

## Node Pool → Availability Domains
1. Identify node pool OCID:
   ```bash
   oci ce node-pool list --compartment-id <compartment> --cluster-id <cluster-ocid>
   ```
2. Fetch node pool details:
   ```bash
   oci ce node-pool get --node-pool-id <nodepool-ocid>
   ```
3. Map to AD and subnet IDs; confirm subnet health via:
   ```bash
   oci network subnet get --subnet-id <subnet-ocid>
   ```

Keep this document in sync with any future automation covering additional OCI resource types.
