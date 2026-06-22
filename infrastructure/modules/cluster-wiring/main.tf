# -----------------------------------------------------------------------
# cluster-wiring — host/k8s glue that must run AFTER the cluster exists and
# BEFORE the platform add-ons: slim canonical-host wiring — CoreDNS overrides
# (*.vault.azure.net + AAD authority hosts -> miniblue on the host) + a CA trust
# ConfigMap so the CSI provider-azure trusts miniblue's TLS. The former KV
# URL-rewrite proxy, the per-run *.vault.azure.net cert-gen and the IMDS DNAT are
# GONE: miniblue now serves the standard KV data-plane + AAD authority on a single
# host-routed HTTPS listener, and pods authenticate via Workload Identity (no IMDS).
#
# Private-image pull credentials are NOT handled here anymore: the `image-pull`
# unit installs the Reflector controller + one annotated source secret that is
# auto-mirrored into every namespace, so app namespaces are created solely by
# ArgoCD (no pre-seeding, no hardcoded namespace list).
#
# This is an inherently imperative host operation (docker/kubectl), so it is a
# null_resource local-exec wrapper around a proven script. Re-runnable each apply.
# -----------------------------------------------------------------------
terraform {
  required_version = ">= 1.10.3"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "= 3.2.3"
    }
  }
}

resource "null_resource" "dns_ca_trust" {
  triggers = {
    kubeconfig_path = var.kubeconfig_path
    miniblue_ca     = var.miniblue_ca_path
    always_run      = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.module}/scripts/install-dns-ca-trust.sh"
    environment = {
      KUBECONFIG           = var.kubeconfig_path
      AKS_CONTAINER_FILTER = var.aks_container_filter
      MINIBLUE_CA_PATH     = var.miniblue_ca_path
    }
  }
}
