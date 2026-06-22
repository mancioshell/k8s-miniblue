# -----------------------------------------------------------------------
# managed-identity — real User-Assigned Managed Identity.
# miniblue now implements the Microsoft.ManagedIdentity ARM control plane
# (userAssignedIdentities CRUD), so this module provisions a real
# azurerm_user_assigned_identity. clientId/principalId are returned by the
# emulator deterministically from the resource ID, so applies are idempotent and
# the chart wiring stays stable across runs.
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
  tags = merge(var.tags, var.additional_tags)
}

resource "azurerm_user_assigned_identity" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

# One dedicated identity per service (Workload Identity — each pod exchanges its own token).
resource "azurerm_user_assigned_identity" "service" {
  for_each = var.services

  name                = join("-", compact(["uaid", var.naming_suffix, each.key]))
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}
