# REQUIRED MODULE PARAMETERS
variable "kubeconfig_path" {
  type        = string
  description = "Path to the AKS admin kubeconfig written by scripts/startup.sh."
}

variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID the webhook stamps into AZURE_TENANT_ID on mutated pods."
}

# OPTIONAL MODULE PARAMETERS
variable "namespace" {
  type        = string
  default     = "azure-workload-identity-system"
  description = "Namespace for the Azure Workload Identity webhook."
}

variable "chart_version" {
  type        = string
  default     = "1.3.0"
  description = "Pinned azure-workload-identity workload-identity-webhook chart version (see versions.md)."
}
