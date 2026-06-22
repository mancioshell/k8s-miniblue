include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/key-vault"
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
    principal_id = "00000000-0000-0000-0000-000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

locals {
  env_locals = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

inputs = {
  resource_group_name           = dependency.rg.outputs.resource_group_name
  managed_identity_principal_id = dependency.mi.outputs.principal_id
  random_secret_names           = [for _, svc in local.env_locals.services : svc.secret_name]
}
