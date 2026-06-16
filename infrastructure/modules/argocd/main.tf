# -----------------------------------------------------------------------
# modules/argocd — install ArgoCD onto the real k3s cluster (helm_release),
# pinned chart. Registers two repositories for the multi-source GitOps pattern:
#   1. the GitOps Git repo (Application manifests + per-service values / $values)
#   2. the OCI Helm repo on ghcr.io that hosts the SHARED chart (service-chart-template)
# research D5.
# -----------------------------------------------------------------------
terraform {
  required_version = ">= 1.10.3"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.16.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "= 1.14.0"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# Applies raw YAML without resolving the GroupVersionKind at PLAN time, so the root
# Application can be created in the same run that installs its CRD (depends_on the helm
# release). The built-in kubernetes provider can't do this.
provider "kubectl" {
  config_path      = var.kubeconfig_path
  load_config_file = true
}

locals {
  argocd_namespace = "argocd"

  # Inject username/password only for a PRIVATE GitOps repo (token provided).
  gitops_repo_auth = var.gitops_repo_token != "" ? {
    username = var.gitops_repo_username
    password = var.gitops_repo_token
  } : {}

  # Register the GitOps repo only when a URL is given. Empty = ArgoCD-only install
  # (GitOps is wired by scripts/startup.sh when GITOPS_REPO_URL is set).
  gitops_repo_entry = var.gitops_repo_url != "" ? {
    gitops-repo = merge({
      url  = var.gitops_repo_url
      type = "git"
      name = "gitops-repo"
    }, local.gitops_repo_auth)
  } : {}

  # Inject username/password only for a PRIVATE OCI registry (token provided).
  oci_repo_auth = var.oci_registry_token != "" ? {
    username = var.oci_registry_username
    password = var.oci_registry_token
  } : {}

  # Register the OCI Helm repo (ghcr.io/<owner>/charts) so ArgoCD can pull the shared
  # chart for the multi-source Applications. Empty url = not registered yet.
  oci_repo_entry = var.oci_chart_repo_url != "" ? {
    charts-oci = merge({
      url       = var.oci_chart_repo_url
      type      = "helm"
      name      = "charts-oci"
      enableOCI = "true"
    }, local.oci_repo_auth)
  } : {}

  # Multi-source pattern: ArgoCD needs BOTH the Git repo (manifests + $values) and
  # the OCI Helm repo (shared chart).
  repositories = merge(local.gitops_repo_entry, local.oci_repo_entry)

  # Root App-of-Apps manifest, applied via kubectl_manifest AFTER the helm release installs
  # the argoproj.io CRDs (depends_on below). It can't be a kubernetes_manifest (that provider
  # resolves the GVK against the live API at PLAN time, before the CRD exists), nor a Helm
  # `extraObjects` entry (Helm builds/validates the CR against discovery before its CRD is
  # registered in the same release).
  root_app_manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = local.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_repo_revision
        path           = "gitops/local/argocd-apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = local.argocd_namespace
      }
      syncPolicy = {
        automated   = { selfHeal = true, prune = true }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = local.argocd_namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  # Insecure server (local dev; access via port-forward). Configure repository access for
  # the GitOps Git repo (desired state, and the chart source under charts/).
  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = true
        }
        repositories = local.repositories
      }
    })
  ]
}

# Root App-of-Apps. Created only when enabled; depends_on the helm release so the
# argoproj.io CRDs exist before this Application is applied (kubectl_manifest applies at
# APPLY time, after the CRDs are registered).
resource "kubectl_manifest" "root_app" {
  count      = var.enable_root_app ? 1 : 0
  yaml_body  = yamlencode(local.root_app_manifest)
  depends_on = [helm_release.argocd]
}

