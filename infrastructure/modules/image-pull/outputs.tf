# MODULE OUTPUTS
output "pull_secret_name" {
  value       = var.pull_secret_name
  description = "Name of the dockerconfigjson imagePullSecret reflected into every namespace."
}

output "ready" {
  value       = coalesce(one(null_resource.ghcr_pull_source[*].id), "disabled-public-images")
  description = "Sentinel downstream units depend on to ensure the pull-secret reflector is in place before app pods schedule."
}
