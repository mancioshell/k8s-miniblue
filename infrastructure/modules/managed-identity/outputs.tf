# MODULE OUTPUTS
output "id" {
  value       = azurerm_user_assigned_identity.this.id
  description = "User-assigned managed identity resource ID."
}

output "client_id" {
  value       = azurerm_user_assigned_identity.this.client_id
  description = "Client ID — used for the ServiceAccount annotation + SecretProviderClass clientID (Workload Identity)."
}

output "principal_id" {
  value       = azurerm_user_assigned_identity.this.principal_id
  description = "Principal ID of the user-assigned identity."
}
