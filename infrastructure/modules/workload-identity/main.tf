# -----------------------------------------------------------------------
# workload-identity — Azure Workload Identity mutating admission webhook
# installed on the real k3s cluster via helm_release (pinned). research R5 /
# FR-013. The webhook mutates pods that carry the
# `azure.workload.identity/use: "true"` label: it projects a ServiceAccount
# token (audience api://AzureADTokenExchange) and injects the
# AZURE_* env vars (AUTHORITY_HOST / CLIENT_ID / TENANT_ID / FEDERATED_TOKEN_FILE)
# that the Azure SDK uses to exchange that token for an access token.
#
# The default AZURE_AUTHORITY_HOST (https://login.microsoftonline.com/) is left
# untouched on purpose: cluster-wiring's CoreDNS override resolves that host to
# miniblue, so the token exchange transparently hits the emulator.
# -----------------------------------------------------------------------
terraform {
  required_version = ">= 1.10.3"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.16.1"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

resource "helm_release" "webhook" {
  name             = "workload-identity-webhook"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://azure.github.io/azure-workload-identity/charts"
  chart      = "workload-identity-webhook"
  version    = var.chart_version

  # The single required value: the tenant the webhook stamps into AZURE_TENANT_ID.
  # Must match the tenant miniblue issues tokens for (lenient model — not enforced,
  # but kept consistent for realism).
  set {
    name  = "azureTenantID"
    value = var.tenant_id
  }
}
