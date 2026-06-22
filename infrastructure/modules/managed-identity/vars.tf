# REQUIRED MODULE PARAMETERS
variable "naming_suffix" {
  type        = string
  description = "Suffix composed into the managed identity name (uaid-<suffix>)."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group that owns the identity (from the resource-group module)."
}

variable "location" {
  type        = string
  description = "Emulated Azure region."
}

# OPTIONAL MODULE PARAMETERS
variable "services" {
  type = map(object({
    namespace       = string
    service_account = string
  }))
  default     = {}
  description = "Per-service workload identity map (key = service name). Each entry creates a dedicated user-assigned managed identity named uaid-<naming_suffix>-<key>. Outputs are collected in service_identities."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Base tags applied to the identity."
}

variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged on top of var.tags."
}
