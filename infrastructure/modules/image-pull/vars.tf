# REQUIRED MODULE PARAMETERS
variable "kubeconfig_path" {
  type        = string
  description = "Path to the host-reachable kubeconfig (from the kubeconfig unit)."
}

# OPTIONAL MODULE PARAMETERS
variable "registry_host" {
  type        = string
  default     = "ghcr.io"
  description = "Container registry host the imagePullSecret authenticates against (e.g. ghcr.io)."
}

variable "ghcr_username" {
  type        = string
  default     = ""
  description = "Username for the imagePullSecret (GitHub owner/user)."
}

variable "ghcr_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "PAT with read:packages for pulling private images. Empty = public images (no controller, no secret created)."
}

variable "pull_secret_name" {
  type        = string
  default     = "ghcr-pull"
  description = "Name of the dockerconfigjson imagePullSecret reflected into every namespace (must match the chart's imagePullSecrets reference)."
}

variable "namespace" {
  type        = string
  default     = "reflector-system"
  description = "Namespace hosting the Reflector controller and the annotated source pull secret."
}

variable "reflector_chart_version" {
  type        = string
  default     = "10.0.50"
  description = "Pinned emberstack/reflector Helm chart version."
}
