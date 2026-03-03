# Generic VNIC Attachment (GVA) — Reference Summary

Source: `gva-documentation_1_14.docx` (Document Version 1.0, Last Updated December 2025).

## What GVA Does
- Provides per-secondary-VNIC configuration for OKE pods.
- Each secondary VNIC can have its own subnet, NSGs, tags, and IP allocation.
- Pods request a specific Application Resource label to select the VNIC type.

## Why It Matters
- Enables workload isolation by network tier.
- Avoids identical secondary VNICs in standard VCN-Native CNI.
- Supports compliance and multi-tenant segmentation.

## Key Concepts
- Primary VNIC: node management and control plane traffic.
- Secondary VNICs: pod networking.
- Application Resource: label that maps pod requests to a VNIC profile.
- Scheduler only places pods on nodes that have matching resources.

## Prerequisites
- OKE cluster with **VCN-Native CNI** (GVA not supported on Flannel).
- Subnets and NSGs per workload tier.
- Node pool permissions to create/manage VNICs.

## Constraints and Limits
- `ipCount` per VNIC is capped at **16**.
- Pods can request **only one** Application Resource type.
- Pods must request **exactly 1** unit of that resource.
- Multi-homed pods are not supported.
- VNIC attachment limits depend on instance shape.

## Node Behavior
- Nodes expose extended resources:
  `oke-application-resource.oci.oraclecloud.com/<ResourceName>`
- Nodes are tainted:
  `oci.oraclecloud.com/application-resource-only:NoSchedule`

## CLI Version Note
- The doc specifies a preview OCI CLI version: `oci-cli==3.65.2+preview.1.1355`.
  Confirm availability in the user's environment before relying on it.

## Example Secondary VNIC JSON (template)
Use as `--secondary-vnics '<json>'` in CLI.

```json
[
  {
    "createVnicDetails": {
      "ipCount": 16,
      "applicationResources": ["Frontend"],
      "assignPublicIp": false,
      "displayName": "vnic-frontend",
      "nsgIds": ["ocid1.nsg..."],
      "subnetId": "ocid1.subnet...",
      "skipSourceDestCheck": false
    },
    "displayName": "vnicattachment-frontend"
  }
]
```

## Example Pod Snippet (template)

```yaml
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
          oke-application-resource.oci.oraclecloud.com/Frontend: "1"
        limits:
          oke-application-resource.oci.oraclecloud.com/Frontend: "1"
```

## max-pods Guidance
- GVA reduces per-interface pod capacity (16 IPs per VNIC).
- Set kubelet `max-pods` via cloud-init accordingly.
- HostNetwork pods still count toward max-pods.
