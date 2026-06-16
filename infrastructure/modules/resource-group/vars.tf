# REQUIRED MODULE PARAMETERS
variable "naming_suffix" {
  type        = string
  description = "Suffix composed into the resource group name (e.g. mb-local)."
}

variable "location" {
  type        = string
  description = "Emulated Azure region for the resource group."
}

# OPTIONAL MODULE PARAMETERS
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Base tags applied to the resource group."
}

variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged on top of var.tags."
}
