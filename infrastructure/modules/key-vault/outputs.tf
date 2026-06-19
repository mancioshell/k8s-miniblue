# MODULE OUTPUTS
output "id" {
  value       = azurerm_key_vault.this.id
  description = "Key Vault resource ID."
}

output "vault_uri" {
  value       = azurerm_key_vault.this.vault_uri
  description = "Vault URI (canonical data-plane endpoint for secret resolution)."
}

output "name" {
  value       = azurerm_key_vault.this.name
  description = "Key Vault name — consumed by the SecretProviderClass keyvaultName."
}

output "seeded_secret_names" {
  value       = sort(keys(azurerm_key_vault_secret.this))
  description = "Names of the secrets generated and stored in the vault."
}
