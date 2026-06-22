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

# Per-service identity details — consumed by the federated-credential live unit.
output "service_identities" {
  value = {
    for k, v in azurerm_user_assigned_identity.service : k => {
      id           = v.id
      client_id    = v.client_id
      principal_id = v.principal_id
    }
  }
  description = "Map of service name => { id, client_id, principal_id } for per-service managed identities."
}
