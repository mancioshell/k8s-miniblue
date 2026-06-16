# MODULE OUTPUTS
output "namespace" {
  value       = helm_release.csi_driver.namespace
  description = "Namespace the CSI driver + Azure provider are installed into."
}

output "driver_chart_version" {
  value       = helm_release.csi_driver.version
  description = "Installed CSI driver chart version."
}

output "provider_chart_version" {
  value       = helm_release.azure_provider.version
  description = "Installed Azure Key Vault provider chart version."
}
