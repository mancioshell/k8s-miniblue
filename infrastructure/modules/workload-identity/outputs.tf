# MODULE OUTPUTS
output "namespace" {
  value       = helm_release.webhook.namespace
  description = "Namespace the Azure Workload Identity webhook was installed into."
}

output "release_name" {
  value       = helm_release.webhook.name
  description = "Helm release name of the Azure Workload Identity webhook."
}

output "ready" {
  value       = helm_release.webhook.id
  description = "Sentinel for downstream dependencies that need the webhook installed first."
}
