# -----------------------------------------------------------------------
# bootstrap/secrets-csi — Secrets Store CSI Driver + Azure Key Vault provider
# installed on the real k3s cluster via helm_release (pinned). research D3/R2.
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

resource "helm_release" "csi_driver" {
  name             = "csi-secrets-store"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = var.csi_driver_chart_version

  # Sync mounted secrets into native Kubernetes Secrets (consumed as env vars).
  set {
    name  = "syncSecret.enabled"
    value = "true"
  }
}

resource "helm_release" "azure_provider" {
  name      = "csi-azure-provider"
  namespace = var.namespace

  repository = "https://azure.github.io/secrets-store-csi-driver-provider-azure/charts"
  chart      = "csi-secrets-store-provider-azure"
  version    = var.azure_provider_chart_version

  # The CSI driver is installed separately (helm_release.csi_driver); disable the
  # bundled subchart to avoid a duplicate DaemonSet collision.
  set {
    name  = "secrets-store-csi-driver.install"
    value = "false"
  }

  # miniblue trust: the provider talks HTTPS to the miniblue-kv-proxy, which
  # presents a self-signed cert for *.vault.azure.net. Mount that CA over the
  # provider container's system trust bundle so its Go TLS client trusts it.
  values = [yamlencode({
    linux = {
      # provider DaemonSet runs hostNetwork=true; ClusterFirstWithHostNet makes it
      # resolve via CoreDNS (which maps *.vault.azure.net -> the proxy node IP).
      dnsPolicy = "ClusterFirstWithHostNet"
      volumes = [{
        name = "miniblue-kv-ca"
        configMap = {
          name = "miniblue-kv-ca"
        }
      }]
      volumeMounts = [{
        name      = "miniblue-kv-ca"
        mountPath = "/etc/ssl/certs/ca-certificates.crt"
        subPath   = "ca-certificates.crt"
        readOnly  = true
      }]
    }
  })]

  depends_on = [helm_release.csi_driver]
}
