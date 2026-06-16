# MODULE OUTPUTS
output "id" {
  value       = local.id
  description = "Container registry resource ID (synthetic — emulator stub)."
}

output "login_server" {
  value       = local.login_server
  description = "ACR login server — the nominal (ACR-shaped) image path; effective bytes via local OCI registry (research R1)."
}

output "name" {
  value       = local.name
  description = "Container registry name."
}
