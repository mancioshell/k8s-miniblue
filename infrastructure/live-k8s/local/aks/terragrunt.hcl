include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/aks"
}

dependency "rg" {
  config_path = "../resource-group"
  mock_outputs = {
    resource_group_name = "rg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

dependency "mi" {
  config_path = "../managed-identity"
  mock_outputs = {
    id = "/subscriptions/mock/resourceGroups/rg-mock/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uaid-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

inputs = {
  resource_group_name = dependency.rg.outputs.resource_group_name
  identity_id         = dependency.mi.outputs.id
}
