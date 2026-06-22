# -----------------------------------------------------------------------
# image-pull — cluster-wide private-registry pull credentials WITHOUT
# pre-creating per-app namespaces. Installs the emberstack Reflector
# controller and creates ONE annotated dockerconfigjson source secret;
# Reflector auto-copies it into EVERY namespace (including ones ArgoCD
# creates on the fly via CreateNamespace=true), so any pod can pull
# private images from ghcr.io by referencing imagePullSecrets: [ghcr-pull].
#
# This decouples "a service exists" (a gitops/local/values/<svc>/ dir that
# ArgoCD discovers) from any Terraform-side namespace list: namespaces are
# created ONLY by ArgoCD when a service is committed, and the pull secret
# follows automatically — no pre-seeding, no hardcoded app_namespaces.
#
# Empty ghcr_token = PUBLIC images -> the whole unit is a no-op (no
# controller, no secret).
# -----------------------------------------------------------------------
terraform {
  required_version = ">= 1.10.3"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.16.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "= 3.2.3"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

locals {
  # Private images need the pull secret; public images need nothing.
  enabled = var.ghcr_token != "" ? 1 : 0
}

# Reflector controller — watches annotated secrets and mirrors them into every
# namespace (current and future), keeping the copies in sync.
resource "helm_release" "reflector" {
  count = local.enabled

  name             = "reflector"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://emberstack.github.io/helm-charts"
  chart      = "reflector"
  version    = var.reflector_chart_version
}

# The single annotated dockerconfigjson source secret Reflector fans out.
# Imperative (kubectl) by design — a sensitive registry credential built from
# env, mirrored to all namespaces by the controller above.
resource "null_resource" "ghcr_pull_source" {
  count = local.enabled

  triggers = {
    kubeconfig_path = var.kubeconfig_path
    registry        = var.registry_host
    secret_name     = var.pull_secret_name
    namespace       = var.namespace
    always_run      = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.module}/scripts/ghcr-pull-source.sh"
    environment = {
      KUBECONFIG       = var.kubeconfig_path
      REGISTRY_HOST    = var.registry_host
      GHCR_USERNAME    = var.ghcr_username
      GHCR_TOKEN       = var.ghcr_token
      PULL_SECRET_NAME = var.pull_secret_name
      SOURCE_NAMESPACE = var.namespace
    }
  }

  depends_on = [helm_release.reflector]
}
