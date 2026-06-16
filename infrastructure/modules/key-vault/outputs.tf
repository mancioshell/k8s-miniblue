# MODULE OUTPUTS
output "id" {
  value       = local.id
  description = "Key Vault resource ID (synthetic — emulator stub)."
}

output "vault_uri" {
  value       = local.vault_uri
  description = "Vault URI (data-plane endpoint for secret resolution)."
}

output "name" {
  value       = local.name
  description = "Key Vault name — consumed by the SecretProviderClass keyvaultName."
}

output "seeded_secret_names" {
  value       = sort(keys(random_password.secret))
  description = "Names of the secrets generated and seeded into the KV data plane."
}
