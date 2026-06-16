# REQUIRED MODULE PARAMETERS
variable "naming_suffix" {
  type        = string
  description = "Suffix composed into the registry name (cr<Suffix>, hyphens stripped)."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group that owns the registry."
}

variable "location" {
  type        = string
  description = "Emulated Azure region."
}

# OPTIONAL MODULE PARAMETERS
variable "sku" {
  type        = string
  default     = "Standard"
  description = "ACR SKU."
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "Error: sku not valid. Possible values are Basic, Standard and Premium."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Base tags applied to the registry."
}

variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged on top of var.tags."
}
