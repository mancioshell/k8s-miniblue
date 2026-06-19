# key-vault

Provisions a **real** Key Vault against miniblue using the Azure Resource Manager provider:
`azurerm_key_vault` (control plane) + `azurerm_key_vault_secret` (data plane). Secret values are
**randomly generated** (`random_password`) and live only in the vault data plane and Terraform
state, never in the image/chart/Git (SC-003).

The miniblue fork implements the Key Vault ARM control plane and advertises a **canonical**
data-plane host (`properties.vaultUri = https://<name>.vault.azure.net/`). azurerm parses a secret
ID by its URL **host**, so the vault must be encoded there (not the path). That FQDN resolves to
miniblue via CoreDNS in-cluster (the CSI provider) and via a hosts-file entry on the terraform host
(added by `scripts/startup.sh` → `trust_miniblue_dns`, removed by `scripts/teardown.sh`). miniblue
keys secrets by vault **name**, so terraform-written and CSI-read secrets share one data plane.
miniblue enforces no RBAC/access-policy (the access policy below is shape parity only).

| Input | Type | Required | Notes |
|-------|------|----------|-------|
| `naming_suffix` | string | yes | `kv-<suffix>` (<= 24 chars). |
| `resource_group_name` | string | yes | From the resource-group module. |
| `location` | string | yes | Emulated region. |
| `managed_identity_principal_id` | string | yes | UAMI principal granted `Get`/`List` (miniblue does not enforce it). |
| `tenant_id` | string | no (`11111111-…`) | Tenant for the vault + access policy (miniblue's fixed local tenant). |
| `sku_name` | string | no (`standard`) | Validated: standard/premium. |
| `random_secret_names` | list(string) | no (`["app-greeting-secret"]`) | Secrets to generate + store; referenced by the chart's SecretProviderClass. |
| `secret_length` | number | no (`32`) | Length of each generated value. |

| Output | Notes |
|--------|-------|
| `id` | Key Vault resource ID. |
| `vault_uri` | Canonical data-plane endpoint. |
| `name` | Consumed by SecretProviderClass `keyvaultName`. |
| `seeded_secret_names` | Names generated + stored in the vault. |

> Stability: values regenerate only on taint or a `secret_length` change. miniblue's data plane is
> in-memory — if the **miniblue** container is restarted (not k3s), re-run `scripts/startup.sh` (or
> `terraform apply`) to recreate the vault + secrets. The generated provider in `root.hcl` disables
> Key Vault soft-delete purge/recovery (miniblue does not implement it) so `destroy` stays clean.
