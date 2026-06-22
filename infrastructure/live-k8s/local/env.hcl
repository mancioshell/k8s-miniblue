# The single "local" environment for this feature (research D1/D6).
locals {
  env_name      = "local"
  naming_suffix = "mb-local"
  location      = "westeurope"

  # Source of truth for services that need Workload Identity.
  # For each entry, Terraform creates:
  #   - one User-Assigned Managed Identity (uaid-mb-local-<name>)
  #   - one Federated Identity Credential bound to that identity
  # namespace and service_account must match what service-chart-template renders
  # (helpers.tpl: name = chart name = directory key, sa = <name>-sa).
  # To add a service: add one entry here AND create gitops/local/values/<name>/.
  services = {}
}
