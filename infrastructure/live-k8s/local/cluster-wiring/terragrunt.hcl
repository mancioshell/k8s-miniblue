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

  # miniblue's self-signed CA (exported by startup) — distributed as the
  # miniblue-kv-ca ConfigMap so the CSI provider-azure trusts miniblue's TLS.
  miniblue_ca_path = "${get_repo_root()}/.miniblue-cert.pem"
}
