include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/argocd"
}

dependency "kubeconfig" {
  config_path = "../kubeconfig"
  mock_outputs = {
    kubeconfig_path = "${get_repo_root()}/kubeconfig"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

# Ordering: ArgoCD installs after the cluster is wired (pull secret + KV/IMDS shim ready).
dependency "cluster_wiring" {
  config_path = "../cluster-wiring"
  mock_outputs = {
    ready = "mock-ready"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

inputs = {
  kubeconfig_path = dependency.kubeconfig.outputs.kubeconfig_path

  # GitOps is enabled directly by scripts/startup.sh when GITOPS_REPO_URL is set
  # (run-all threads these via the environment). Empty repo url = ArgoCD only, no root app.
  enable_root_app      = tobool(get_env("ENABLE_ROOT_APP", "false"))
  gitops_repo_url      = get_env("GITOPS_REPO_URL", "")
  gitops_repo_revision = get_env("GITOPS_REPO_REVISION", "main")

  # OCI Helm repo (ghcr.io/<owner>/charts) for the shared chart in the multi-source apps.
  # Set by scripts/startup.sh; creds flow via TF_VAR_oci_registry_username/token.
  oci_chart_repo_url = get_env("OCI_CHART_REPO_URL", "")
}
