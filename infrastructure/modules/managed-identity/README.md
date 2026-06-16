# managed-identity

Creates a **User-Assigned** managed identity. The Spring Boot pod uses it (via miniblue's IMDS
token endpoint) to authenticate to Key Vault through the Secrets Store CSI driver. User-Assigned
is preferred over System-Assigned for explicit, auditable identity (constitution / research D3).

| Input | Type | Required | Notes |
|-------|------|----------|-------|
| `naming_suffix` | string | yes | `uaid-<suffix>`. |
| `resource_group_name` | string | yes | From the resource-group module. |
| `location` | string | yes | Emulated region. |

| Output | Notes |
|--------|-------|
| `id` | Identity resource ID (consumed by the aks module `identity_id`). |
| `client_id` | For SecretProviderClass `userAssignedIdentityID`. |
| `principal_id` | Granted Key Vault read access. |
