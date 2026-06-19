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

variable "registry_host" {
  type        = string
  default     = "ghcr.io"
  description = "Container registry host the imagePullSecret authenticates against (e.g. ghcr.io)."
}

variable "ghcr_username" {
  type        = string
  default     = ""
  description = "Username for the imagePullSecret (GitHub owner/user). Empty = skip secret creation."
}

variable "ghcr_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "PAT with read:packages for pulling private images. Empty = public packages (no imagePullSecret created)."
}

variable "pull_secret_name" {
  type        = string
  default     = "ghcr-pull"
  description = "Name of the dockerconfigjson imagePullSecret created in each app namespace."
}

variable "app_namespaces" {
  type        = list(string)
  default     = []
  description = "App namespaces to pre-create and seed with the imagePullSecret (ArgoCD adopts them at sync)."
}

variable "miniblue_ca_path" {
  type        = string
  description = "Host path to miniblue's self-signed CA PEM (exported by startup). Distributed as the miniblue-kv-ca ConfigMap the CSI provider trusts."
}
