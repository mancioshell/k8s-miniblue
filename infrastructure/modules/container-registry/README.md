# container-registry

Creates the Azure Container Registry **object** in miniblue. Because miniblue's ACR data plane
is a stub (research R1), real image layers are not stored here — a local OCI registry serves the
effective bytes while this resource stays the declared Azure representation and the chart's
image path is ACR-shaped.

| Input | Type | Required | Notes |
|-------|------|----------|-------|
| `naming_suffix` | string | yes | `cr<Suffix>` (hyphens stripped). |
| `resource_group_name` | string | yes | From the resource-group module. |
| `location` | string | yes | Emulated region. |
| `sku` | string | no (`Standard`) | Validated: Basic/Standard/Premium. |

| Output | Notes |
|--------|-------|
| `id` | Registry ID. |
| `login_server` | Nominal image path (ACR-shaped). |
| `name` | Registry name. |
