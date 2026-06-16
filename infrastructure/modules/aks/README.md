# aks (real cluster via miniblue `AKS_BACKEND=k3s`)

Creates the Kubernetes cluster through `azurerm_kubernetes_cluster` against miniblue's **real
AKS backend**. miniblue launches a real `rancher/k3s` container and `listClusterAdminCredential`
returns a working admin kubeconfig — so this single resource is both the Azure-side object and
the actual workload runtime (research D2). The bootstrap layer consumes the admin kubeconfig.

| Input | Type | Required | Notes |
|-------|------|----------|-------|
| `naming_suffix` | string | yes | `aks-<suffix>`. |
| `resource_group_name` | string | yes | From the resource-group module. |
| `location` | string | yes | Emulated region. |
| `identity_id` | string | yes | User-Assigned MI ID (from managed-identity). |
| `kubernetes_version` | string | no (`null`) | Null = backend default. |
| `node_count` / `vm_size` | — | no | Single-node k3s defaults. |

| Output | Notes |
|--------|-------|
| `id` | Cluster ID. |
| `name` | Cluster name. |
| `kube_admin_config` | Admin kubeconfig block (host, certs) — sensitive. |
| `kube_admin_config_raw` | Raw kubeconfig YAML — sensitive. |
| `host` | API server host — sensitive. |

> k3s specifics: Flannel CNI, SQLite, Traefik disabled by miniblue → use port-forward for
> cluster access, not a Traefik ingress.
