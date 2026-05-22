# OKE GVA Deployer Transcript

This is a shortened successful run for creating a GVA-enabled node pool.

## Prompt

```text
/oke-agent-plugin:oke-gva-deployer
```

## Transcript

**Agent:** Which OKE cluster should I configure?

**User:** `demo-oke`, region `us-ashburn-1`.

**Agent:** I found the cluster OCID in kubeconfig and discovered VCN, subnet, and NSG
options. I will ask for one mutable node-pool value at a time.

**User choices:**

| Field | Value |
| --- | --- |
| Node pool name | `gva-workers` |
| Shape | `VM.Standard.E5.Flex` |
| OCPUs / memory | `2` / `16` |
| Node count | `3` |
| Primary subnet | `<primary_subnet_ocid>` |
| Application Resource | `frontend` |
| Secondary subnet | `<secondary_subnet_ocid>` |
| `ipCount` | `32` |

**Agent:** Generated a create command and a validation workload manifest. The command
is printed for review; it is not run unless you explicitly choose to run it.

## What This Produces

See [sample GVA command output](../outputs/oke-gva-deployer/node-pool-command.sh).
