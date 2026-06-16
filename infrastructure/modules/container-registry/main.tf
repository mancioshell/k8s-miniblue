# -----------------------------------------------------------------------
# container-registry — EMULATOR STUB.
# miniblue's ACR control plane accepts CREATE but rejects UPDATE (405), causing
# re-apply failures, and its ACR data plane is only a Docker v2 stub (research
# R1) — effective image bytes are served by GitHub Container Registry (ghcr.io).
# Nothing in the workload consumes these outputs (the chart pulls from ghcr.io), so
# this module exposes ACR-shaped identifiers as constants instead of calling ARM.
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
  # ACR names disallow hyphens — PascalCase then strip spaces.
  raw_name     = join("-", compact(["cr", var.naming_suffix]))
  name         = replace(title(replace(local.raw_name, "-", " ")), " ", "")
  login_server = "${lower(local.name)}.azurecr.io"
  id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/${var.resource_group_name}/providers/Microsoft.ContainerRegistry/registries/${local.name}"
}
