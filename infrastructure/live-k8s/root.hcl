# ---------------------------------------------------------------------------
# Terragrunt root — single source of truth for backend, provider, common inputs.
# Targets the miniblue Azure emulator (no real Azure). State is LOCAL (research D6):
# constitution requires remote/locked state only for *shared* environments; this is a
# single, non-shared, local environment.
# ---------------------------------------------------------------------------

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  naming_suffix = local.env_vars.locals.naming_suffix
  location      = local.env_vars.locals.location

  # miniblue endpoint wiring (overridable via env; defaults match scripts/lib/common.sh).
  arm_metadata_hostname = get_env("ARM_METADATA_HOSTNAME", "localhost:4567")
  subscription_id       = get_env("ARM_SUBSCRIPTION_ID", "00000000-0000-0000-0000-000000000000")
  tenant_id             = get_env("ARM_TENANT_ID", "11111111-1111-1111-1111-111111111111")
  client_id             = get_env("ARM_CLIENT_ID", "22222222-2222-2222-2222-222222222222")
  client_secret         = get_env("ARM_CLIENT_SECRET", "miniblue-fake-secret")

  common_tags = {
    project     = "k8s-miniblue"
    environment = "local"
    managed_by  = "terragrunt"
  }
}

# Local state backend — one state file per unit under infrastructure/live/.terraform-state/.
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

# azurerm provider generation — points at miniblue via metadata_host + fake credentials,
# skips provider registration. Modules NEVER hardcode this (contract guarantee #2).
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "azurerm" {
      features {
        key_vault {
          # miniblue is ephemeral and does not implement soft-delete purge/recovery;
          # disabling these keeps create + `terragrunt run-all destroy` clean.
          purge_soft_delete_on_destroy    = false
          recover_soft_deleted_key_vaults = false
        }
      }

      skip_provider_registration = true
      use_cli                    = false
      use_msi                    = false

      subscription_id = "${local.subscription_id}"
      tenant_id       = "${local.tenant_id}"
      client_id       = "${local.client_id}"
      client_secret   = "${local.client_secret}"

      # miniblue HTTPS metadata host (host:port, NO scheme — azurerm prepends https://).
      metadata_host = "${local.arm_metadata_hostname}"
    }
  EOF
}

# Inputs every module receives (those not consumed are ignored by Terraform).
inputs = {
  naming_suffix = local.naming_suffix
  location      = local.location
  tags          = local.common_tags
}
