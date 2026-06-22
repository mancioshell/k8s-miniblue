# REQUIRED MODULE PARAMETERS
variable "kubeconfig_path" {
  type        = string
  description = "Path to the host-reachable kubeconfig (from the kubeconfig unit)."
}

# OPTIONAL MODULE PARAMETERS
variable "aks_container_filter" {
  type        = string
  default     = "miniblue-aks-"
  description = "docker ps name filter that matches the miniblue-spawned k3s container."
}

variable "miniblue_ca_path" {
  type        = string
  description = "Host path to miniblue's self-signed CA PEM (exported by startup). Distributed as the miniblue-kv-ca ConfigMap the CSI provider trusts."
}
