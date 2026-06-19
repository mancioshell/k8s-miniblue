include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/workload-identity"
}

dependency "kubeconfig" {
  config_path = "../kubeconfig"
  mock_outputs = {
    kubeconfig_path = "${get_repo_root()}/kubeconfig"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

# Needs the CoreDNS overrides (login.microsoftonline.com -> miniblue) in place so the
# webhook-injected token exchange reaches the emulator.
dependency "cluster_wiring" {
  config_path = "../cluster-wiring"
  mock_outputs = {
    ready = "mock-ready"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

inputs = {
  kubeconfig_path = dependency.kubeconfig.outputs.kubeconfig_path
  tenant_id       = get_env("ARM_TENANT_ID", "11111111-1111-1111-1111-111111111111")
}
