# -----------------------------------------------------------------------
# cluster-wiring — host/k8s glue that must run AFTER the cluster exists and
# BEFORE the platform add-ons:
#   (1) pre-create each app namespace + a dockerconfigjson imagePullSecret so the
#       node can pull PRIVATE images from ghcr.io (no k3s restart — the registry is
#       remote with normal DNS/TLS, so no node-level mirror/auth rewrite is needed);
#   (2) install the miniblue KV/IMDS shim.
# The two steps are independent (step 1 no longer restarts k3s), so no ordering
# dependency is required between them.
#
# These are inherently imperative host operations (docker/kubectl/iptables), so they
# are null_resource local-exec wrappers around proven scripts. Re-runnable each apply.
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

resource "null_resource" "image_pull_secrets" {
  triggers = {
    kubeconfig_path = var.kubeconfig_path
    registry        = var.registry_host
    namespaces      = join(",", var.app_namespaces)
    secret_name     = var.pull_secret_name
    always_run      = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.module}/scripts/image-pull-secret.sh"
    environment = {
      KUBECONFIG       = var.kubeconfig_path
      REGISTRY_HOST    = var.registry_host
      GHCR_USERNAME    = var.ghcr_username
      GHCR_TOKEN       = var.ghcr_token
      PULL_SECRET_NAME = var.pull_secret_name
      APP_NAMESPACES   = join(" ", var.app_namespaces)
    }
  }
}

resource "null_resource" "kv_proxy" {
  triggers = {
    kubeconfig_path = var.kubeconfig_path
    miniblue_port   = var.miniblue_data_port
    always_run      = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.module}/scripts/install-kv-proxy.sh"
    environment = {
      KUBECONFIG           = var.kubeconfig_path
      AKS_CONTAINER_FILTER = var.aks_container_filter
      MINIBLUE_DATA_PORT   = var.miniblue_data_port
      PROXY_PY             = "${path.module}/files/proxy.py"
      KV_CA_OUT            = var.kv_ca_out
    }
  }
}
