include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/managed-identity"
}

dependency "rg" {
  config_path = "../resource-group"
  mock_outputs = {
    resource_group_name = "rg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

locals {
  env_locals = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

inputs = {
  resource_group_name = dependency.rg.outputs.resource_group_name
  # Project only namespace + service_account — secret_name is KV-specific and not
  # part of the managed-identity module's services type.
  services = {
    for k, v in local.env_locals.services : k => {
      namespace       = v.namespace
      service_account = v.service_account
    }
  }
}
