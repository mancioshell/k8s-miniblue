# -----------------------------------------------------------------------
# aks — real Kubernetes cluster via miniblue's REAL AKS backend (AKS_BACKEND=k3s).
# Creating this resource makes miniblue launch a real rancher/k3s container;
# listClusterAdminCredential returns a working admin kubeconfig (research D2).
# This single resource IS both the Azure object AND the workload runtime.
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
  name       = join("-", compact(["aks", var.naming_suffix]))
  dns_prefix = replace(local.name, "-", "")
  tags       = merge(var.tags, var.additional_tags)
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = local.dns_prefix
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.vm_size
  }

  # User-Assigned MI threaded through for pod identity / IMDS auth.
  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  tags = local.tags

  lifecycle {
    # miniblue parity gap: the AKS emulator does not persist/return `support_plan`,
    # so every refresh shows it absent and the provider re-plans to set it. Ignoring
    # it keeps the stack idempotent (T044/FR-015). Remove when targeting real Azure.
    ignore_changes = [support_plan]
  }
}
