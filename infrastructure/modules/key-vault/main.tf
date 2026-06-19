# -----------------------------------------------------------------------
# key-vault — REAL Azure Resource Manager resources against miniblue.
# The miniblue fork implements BOTH the Key Vault ARM control plane
# (Microsoft.KeyVault/vaults create/get/delete) and the secrets data plane,
# advertising a CANONICAL data-plane host (properties.vaultUri =
# https://<name>.vault.azure.net/). azurerm parses a secret ID by its URL host, so the
# vault must be encoded in the host — hence the canonical FQDN, resolved to miniblue by:
#   - CoreDNS for in-cluster pods (the CSI provider), and
#   - a hosts-file entry on the terraform host (added by scripts/startup.sh).
# Both land on miniblue, which keys secrets by vault NAME, so terraform-written secrets
# and CSI-read secrets share one data plane. miniblue enforces no RBAC/access-policy.
# -----------------------------------------------------------------------
terraform {
  required_version = ">= 1.10.3"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.116.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.6.3"
    }
  }
}

locals {
  # Key Vault names disallow hyphens beyond the standard pattern; keep <= 24 chars.
  name = substr(replace(join("-", compact(["kv", var.naming_suffix])), "--", "-"), 0, 24)
  tags = merge(var.tags, var.additional_tags)
}

# -----------------------------------------------------------------------
# Randomly-generated secret values (one per name). Marked sensitive by the
# provider; the value lives ONLY in miniblue's KV data plane + this state —
# never in the image, chart, or Git (SC-003). Stable across applies: it only
# regenerates on taint or when var.secret_length changes.
# -----------------------------------------------------------------------
resource "random_password" "secret" {
  for_each = toset(var.random_secret_names)

  length           = var.secret_length
  special          = true
  override_special = "!#%*-_=+.~"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

# -----------------------------------------------------------------------
# The Key Vault (ARM control plane). The access policy grants the platform's
# User-Assigned MI secret read — shape parity with real Azure; miniblue does not
# enforce it (the CSI authenticates via Workload Identity).
# -----------------------------------------------------------------------
resource "azurerm_key_vault" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = var.sku_name

  # miniblue is ephemeral and does not implement soft-delete purge; keep teardown clean
  # (provider features.key_vault.purge_soft_delete_on_destroy is also disabled in root.hcl).
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = var.tenant_id
    object_id = var.managed_identity_principal_id

    secret_permissions = ["Get", "List"]
  }

  tags = local.tags
}

# -----------------------------------------------------------------------
# Secrets (data plane). azurerm PUTs each value to the canonical vault host and
# reads it back by the versioned secret ID; miniblue stores it keyed by vault name,
# where the in-cluster CSI provider reads it.
# -----------------------------------------------------------------------
resource "azurerm_key_vault_secret" "this" {
  for_each = random_password.secret

  name         = each.key
  value        = each.value.result
  key_vault_id = azurerm_key_vault.this.id
}
