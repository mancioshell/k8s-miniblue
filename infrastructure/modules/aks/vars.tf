# REQUIRED MODULE PARAMETERS
variable "naming_suffix" {
  type        = string
  description = "Suffix composed into the cluster name (aks-<suffix>)."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group that owns the cluster."
}

variable "location" {
  type        = string
  description = "Emulated Azure region."
}

variable "identity_id" {
  type        = string
  description = "User-Assigned MI resource ID attached to the cluster (from managed-identity)."
}

# OPTIONAL MODULE PARAMETERS
variable "kubernetes_version" {
  type        = string
  default     = null
  description = "Kubernetes version. Null lets miniblue/k3s pick the version bundled with the pinned backend."
}

variable "node_count" {
  type        = number
  default     = 1
  description = "Default node pool size (single-node k3s)."
}

variable "vm_size" {
  type        = string
  default     = "Standard_DS2_v2"
  description = "Node VM size (nominal; ignored by the k3s backend)."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Base tags applied to the cluster."
}

variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged on top of var.tags."
}
