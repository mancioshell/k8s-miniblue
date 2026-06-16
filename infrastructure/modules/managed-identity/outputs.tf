# MODULE OUTPUTS
output "id" {
  value       = local.id
  description = "User-assigned managed identity resource ID (synthetic — emulator stub)."
}

output "client_id" {
  value       = local.client_id
  description = "Client ID — used by the SecretProviderClass (userAssignedIdentityID) for IMDS auth."
}

output "principal_id" {
  value       = local.principal_id
  description = "Principal ID — informational (miniblue KV data plane does not enforce it)."
}
