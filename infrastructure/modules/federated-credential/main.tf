# -----------------------------------------------------------------------
# federated-credential — Azure federated identity credentials (FICs) that bind a
# user-assigned managed identity to one or more Kubernetes ServiceAccounts for
# Azure Workload Identity (FR-014 / R5 / US3).
#
# Each FIC tells Azure AD: "a projected ServiceAccount token whose `iss` is
# `var.issuer` and whose `sub` is system:serviceaccount:<ns>:<sa>, presented with
# audience `var.audience`, may exchange for an access token of this identity."
# miniblue does NOT enforce the FIC at token-exchange time (lenient model), but the
# credential is still registered so the topology matches a real Azure deployment.
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

resource "azurerm_federated_identity_credential" "this" {
  for_each = var.services

  name                = "fic-${each.key}"
  resource_group_name = var.resource_group_name
  parent_id           = each.value.user_assigned_identity_id
  audience            = [var.audience]
  issuer              = var.issuer
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}
