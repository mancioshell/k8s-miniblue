# REQUIRED MODULE PARAMETERS
variable "kubeconfig_path" {
  type        = string
  description = "Path to the AKS admin kubeconfig written by scripts/startup.sh."
}

# OPTIONAL MODULE PARAMETERS
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace for the CSI driver + Azure provider DaemonSets."
}

variable "csi_driver_chart_version" {
  type        = string
  default     = "1.4.6"
  description = "Pinned secrets-store-csi-driver chart version (see versions.md)."
}

variable "azure_provider_chart_version" {
  type        = string
  default     = "1.6.0"
  description = "Pinned csi-secrets-store-provider-azure chart version (see versions.md)."
}
