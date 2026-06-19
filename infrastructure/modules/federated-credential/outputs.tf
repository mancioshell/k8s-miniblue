# MODULE OUTPUTS
output "ids" {
  value       = { for k, fic in azurerm_federated_identity_credential.this : k => fic.id }
  description = "Map of service key -> federated identity credential resource ID."
}

output "subjects" {
  value       = { for k, fic in azurerm_federated_identity_credential.this : k => fic.subject }
  description = "Map of service key -> the ServiceAccount subject the credential binds."
}
