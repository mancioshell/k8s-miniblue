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

# Parent UAMI the federated credentials attach to.
dependency "managed_identity" {
  config_path = "../managed-identity"
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uaid-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "console"]
}

inputs = {
  resource_group_name       = dependency.rg.outputs.resource_group_name
  user_assigned_identity_id = dependency.managed_identity.outputs.id

  # Must equal the k3s service-account-issuer stamped onto projected tokens (T016).
  issuer = get_env("MINIBLUE_SA_ISSUER", "https://miniblue.local/oidc")
}
