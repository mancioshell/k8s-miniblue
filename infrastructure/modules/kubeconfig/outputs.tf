# MODULE OUTPUTS
output "kubeconfig_path" {
  value       = var.kubeconfig_path
  description = "Path to the host-reachable kubeconfig written by this module."
}

output "kubeconfig" {
  value       = data.local_file.kubeconfig.content
  sensitive   = true
  description = "Raw kubeconfig YAML (server rewritten to the host-mapped k3s API port)."
}
