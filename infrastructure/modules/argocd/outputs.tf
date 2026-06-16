# MODULE OUTPUTS
output "namespace" {
  value       = helm_release.argocd.namespace
  description = "Namespace ArgoCD is installed into."
}

output "chart_version" {
  value       = helm_release.argocd.version
  description = "Installed ArgoCD chart version."
}
