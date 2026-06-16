# -----------------------------------------------------------------------
# resource-group — container for all emulated Azure resources (miniblue).
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
  name = join("-", compact(["rg", var.naming_suffix]))
  tags = merge(var.tags, var.additional_tags)
}

resource "azurerm_resource_group" "this" {
  name     = local.name
  location = var.location
  tags     = local.tags
}
