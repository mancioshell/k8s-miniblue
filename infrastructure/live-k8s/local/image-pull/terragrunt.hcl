include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/image-pull"
}

dependency "kubeconfig" {
  config_path = "../kubeconfig"
  mock_outputs = {
    kubeconfig_path = "${get_repo_root()}/kubeconfig"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

# Runs after the cluster is wired (node/k3s ready). Independent of the DNS/CA step,
# but kept ordered behind it so the kubeconfig + cluster are settled first.
dependency "cluster_wiring" {
  config_path = "../cluster-wiring"
  mock_outputs = {
    ready = "mock-ready"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

inputs = {
  kubeconfig_path = dependency.kubeconfig.outputs.kubeconfig_path

  # Private-registry pull auth (Reflector source secret). Empty token = public
  # images, so the unit is a no-op (no controller, no secret). Same env vars the
  # cluster-wiring unit used to consume — now routed here.
  registry_host = get_env("REGISTRY_HOST", "ghcr.io")
  ghcr_username = get_env("GHCR_USERNAME", "")
  ghcr_token    = get_env("GHCR_TOKEN", "")
}
