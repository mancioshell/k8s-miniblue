# MODULE OUTPUTS
output "id" {
  value       = azurerm_kubernetes_cluster.this.id
  description = "AKS cluster resource ID."
}

output "name" {
  value       = azurerm_kubernetes_cluster.this.name
  description = "AKS cluster name."
}

# Kubeconfig from miniblue's listClusterUserCredential — exposed via kube_config
# (miniblue does NOT populate kube_admin_config / listClusterAdminCredential).
# Output names kept admin-shaped so the bootstrap layer + 15-get-credentials.sh
# stay unchanged.
output "kube_admin_config" {
  value       = azurerm_kubernetes_cluster.this.kube_config
  sensitive   = true
  description = "Kubeconfig block: host, client_certificate, client_key, cluster_ca_certificate."
}

output "kube_admin_config_raw" {
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
  description = "Raw kubeconfig YAML (written to disk by 15-get-credentials.sh)."
}

output "host" {
  value       = azurerm_kubernetes_cluster.this.kube_config[0].host
  sensitive   = true
  description = "Cluster API server host."
}
