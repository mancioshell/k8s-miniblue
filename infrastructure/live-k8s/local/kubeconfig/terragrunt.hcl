include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/kubeconfig"
}

dependency "aks" {
  config_path = "../aks"
  mock_outputs = {
    id = "/subscriptions/mock/resourceGroups/rg-mock/providers/Microsoft.ContainerService/managedClusters/aks-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

inputs = {
  aks_cluster_id  = dependency.aks.outputs.id
  kubeconfig_path = get_env("KUBECONFIG_FILE", "${get_repo_root()}/kubeconfig")
}
