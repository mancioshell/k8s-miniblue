include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/cluster-wiring"
}

# Needs the host-reachable kubeconfig produced by the kubeconfig unit.
dependency "kubeconfig" {
  config_path = "../kubeconfig"
  mock_outputs = {
    kubeconfig_path = "${get_repo_root()}/kubeconfig"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

inputs = {
  kubeconfig_path = dependency.kubeconfig.outputs.kubeconfig_path

  # GHCR pull auth for PRIVATE packages: pre-create each app namespace and a
  # dockerconfigjson imagePullSecret in it so the node can pull from ghcr.io.
  # Empty token = public packages, the step is skipped (no secret written).
  registry_host    = get_env("REGISTRY_HOST", "ghcr.io")
  ghcr_username    = get_env("GHCR_USERNAME", "")
  ghcr_token       = get_env("GHCR_TOKEN", "")
  pull_secret_name = "ghcr-pull"
  app_namespaces   = ["service-a", "service-b"]

  miniblue_data_port = get_env("MINIBLUE_DATA_PORT", "4566")
  kv_ca_out          = "${get_repo_root()}/.miniblue-kv-ca.pem"
}
