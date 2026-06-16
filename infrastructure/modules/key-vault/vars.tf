# REQUIRED MODULE PARAMETERS
variable "naming_suffix" {
  type        = string
  description = "Suffix composed into the vault name (kv-<suffix>, max 24 chars)."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group that owns the vault."
}

variable "location" {
  type        = string
  description = "Emulated Azure region."
}

variable "managed_identity_principal_id" {
  type        = string
  description = "Principal ID of the User-Assigned MI granted secret read access (from managed-identity)."
}

# OPTIONAL MODULE PARAMETERS
variable "sku_name" {
  type        = string
  default     = "standard"
  description = "Key Vault SKU."
  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "Error: sku_name not valid. Possible values are standard and premium."
  }
}

variable "random_secret_names" {
  type        = list(string)
  default     = ["app-greeting-secret"]
  description = "Secret names to generate (random value) and seed into the miniblue KV data plane. The chart's SecretProviderClass references these by name."
}

variable "secret_length" {
  type        = number
  default     = 32
  description = "Character length of each generated random secret value."
}

variable "keyvault_dataplane_url" {
  type        = string
  default     = "http://localhost:4566"
  description = "Base URL of the miniblue Key Vault data plane (host-published port). Seeding targets <url>/keyvault/<vault>/secrets/<name>."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Base tags applied to the vault."
}

variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged on top of var.tags."
}
