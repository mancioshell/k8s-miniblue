# REQUIRED MODULE PARAMETERS
variable "aks_cluster_id" {
  type        = string
  description = "AKS cluster resource ID (from the aks unit). Forces this module to run after the cluster exists and re-run if it is recreated."
}

variable "kubeconfig_path" {
  type        = string
  description = "Absolute path where the host-reachable kubeconfig is written."
}

# OPTIONAL MODULE PARAMETERS
variable "aks_container_filter" {
  type        = string
  default     = "miniblue-aks-"
  description = "docker ps name filter that matches the miniblue-spawned k3s container."
}
