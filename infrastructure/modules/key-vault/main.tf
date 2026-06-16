# -----------------------------------------------------------------------
# key-vault — EMULATOR STUB.
# miniblue does NOT implement the Key Vault ARM control plane: vault create and
# access policies return 404 (see API parity matrix). It DOES implement the Key
# Vault secrets data plane (parity: Full), keyed by vault NAME, with no RBAC /
# access-policy enforcement. The CSI provider reads secrets straight from that
# data plane (seeded by the null_resource.seed local-exec below). So this module just
# exposes the vault name/URI as constants instead of provisioning ARM resources.
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
    null = {
      source  = "hashicorp/null"
      version = "= 3.2.3"
    }
  }
}

locals {
  # Key Vault names disallow hyphens beyond the standard pattern; keep <= 24 chars.
  name      = substr(replace(join("-", compact(["kv", var.naming_suffix])), "--", "-"), 0, 24)
  vault_uri = "https://${local.name}.vault.azure.net/"
  id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/${var.resource_group_name}/providers/Microsoft.KeyVault/vaults/${local.name}"
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
# Seed each secret into the miniblue Key Vault data plane (parity: Full),
# keyed by vault NAME. Runs from the host against the published data-plane
# port (default localhost:4566), so it is independent of the in-cluster
# network wiring (scripts/startup.sh restarts k3s — NOT miniblue — so seeded
# values survive those restarts). PUT is idempotent; triggers re-seed only when
# the value, vault name, or endpoint changes (keeps idempotency checks green).
# -----------------------------------------------------------------------
resource "null_resource" "seed" {
  for_each = random_password.secret

  triggers = {
    vault      = local.name
    secret     = each.key
    endpoint   = var.keyvault_dataplane_url
    value_hash = nonsensitive(sha256(each.value.result))
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    on_failure  = fail

    environment = {
      KV_URL  = "${var.keyvault_dataplane_url}/keyvault/${local.name}/secrets/${each.key}"
      KV_BODY = jsonencode({ value = each.value.result })
    }

    command = <<-EOT
      set -euo pipefail
      code=$(curl -s -o /dev/null -w '%%{http_code}' -X PUT \
        -H 'Content-Type: application/json' \
        "$KV_URL" --data "$KV_BODY")
      case "$code" in
        2*) echo "[+] seeded KV secret (HTTP $code)";;
        *)  echo "[x] KV seed failed (HTTP $code) at $KV_URL" >&2; exit 1;;
      esac
    EOT
  }
}
