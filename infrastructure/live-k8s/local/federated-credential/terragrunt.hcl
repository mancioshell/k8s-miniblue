include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/federated-credential"
}

dependency "rg" {
  config_path = "../resource-group"
  mock_outputs = {
    resource_group_name = "rg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

dependency "managed_identity" {
  config_path = "../managed-identity"
  mock_outputs = {
    service_identities = {}
  }
  mock_outputs_allowed_terraform_commands  = ["validate", "plan", "console"]
  mock_outputs_merge_strategy_with_state   = "shallow"
}

# Service list comes from env.hcl — the single source of truth.
# For each service, the managed-identity unit has already created a dedicated identity;
# here we join the env definition with its identity ID to build the FIC inputs.
locals {
  env_locals = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

inputs = {
  resource_group_name = dependency.rg.outputs.resource_group_name

  # Must equal the k3s service-account-issuer stamped onto projected tokens (T016).
  issuer = get_env("MINIBLUE_SA_ISSUER", "https://miniblue.local/oidc")

  services = {
    for name, identity in dependency.managed_identity.outputs.service_identities : name => {
      namespace                 = lookup(lookup(local.env_locals.services, name, {}), "namespace", name)
      service_account           = lookup(lookup(local.env_locals.services, name, {}), "service_account", "${name}-sa")
      user_assigned_identity_id = identity.id
    }
  }
}
