# -----------------------------------------------------------------------
# managed-identity — EMULATOR STUB.
# miniblue does NOT implement the Microsoft.ManagedIdentity ARM control plane:
# creating a User-Assigned Identity returns 404 (see API parity matrix). The CSI
# Azure provider authenticates at runtime via the IMDS token endpoint (parity:
# Full), which issues tokens for ANY client_id without the identity existing as
# an ARM resource. So this module exposes deterministic constant identifiers
# instead of provisioning a real resource. RG + AKS remain real.
# -----------------------------------------------------------------------
terraform {
  required_version = ">= 1.10.3"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.116.0"
    }
  }
}

locals {
  name = join("-", compact(["uaid", var.naming_suffix]))

  # Fixed identifiers — miniblue IMDS accepts any client_id; KV data plane does
  # not enforce the principal. Kept stable so the SecretProviderClass wiring is
  # deterministic across applies.
  client_id    = "22222222-2222-2222-2222-222222222222"
  principal_id = "33333333-3333-3333-3333-333333333333"
  id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/${var.resource_group_name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${local.name}"
}
