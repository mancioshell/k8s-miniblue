# key-vault

Emulator stub for a **secrets-only** Key Vault (miniblue supports the secrets data plane, not the
ARM control plane). Exposes the vault name/URI as constants, **generates random secret values**
(`random_password`), and **seeds them into the miniblue KV data plane** via a `local-exec` PUT.
Values live only in the data plane and Terraform state, never in the image/chart/Git (SC-003).

| Input | Type | Required | Notes |
|-------|------|----------|-------|
| `naming_suffix` | string | yes | `kv-<suffix>` (<= 24 chars). |
| `resource_group_name` | string | yes | From the resource-group module. |
| `location` | string | yes | Emulated region. |
| `managed_identity_principal_id` | string | yes | UAMI principal (data plane does not enforce it). |
| `sku_name` | string | no (`standard`) | Validated: standard/premium. |
| `random_secret_names` | list(string) | no (`["app-greeting-secret"]`) | Secrets to generate + seed; referenced by the chart's SecretProviderClass. |
| `secret_length` | number | no (`32`) | Length of each generated value. |
| `keyvault_dataplane_url` | string | no (`http://localhost:4566`) | miniblue KV data-plane base URL. |

| Output | Notes |
|--------|-------|
| `id` | Vault ID (synthetic). |
| `vault_uri` | Data-plane endpoint. |
| `name` | Consumed by SecretProviderClass `keyvaultName`. |
| `seeded_secret_names` | Names generated + seeded into the data plane. |

> Stability: values regenerate only on taint or a `secret_length` change. miniblue's KV data plane
> is in-memory — if the **miniblue** container is restarted (not k3s), re-seed with `terraform apply`
> (taint the secret) or `scripts/50-...`.
