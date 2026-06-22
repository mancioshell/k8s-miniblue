# REQUIRED MODULE PARAMETERS
variable "resource_group_name" {
  type        = string
  description = "Resource group that holds the parent user-assigned managed identities."
}

variable "issuer" {
  type        = string
  description = "OIDC issuer of the projected ServiceAccount tokens (k3s service-account-issuer, MINIBLUE_SA_ISSUER)."
}

# OPTIONAL MODULE PARAMETERS
variable "services" {
  type = map(object({
    namespace                 = string
    service_account           = string
    user_assigned_identity_id = string
  }))
  default     = {}
  description = "Services to bind: map key -> { namespace, service_account, user_assigned_identity_id }. Each entry creates one federated credential on the given identity. SA subject = system:serviceaccount:<namespace>:<service_account>."
}

variable "audience" {
  type        = string
  default     = "api://AzureADTokenExchange"
  description = "Token audience the federated credential accepts (Workload Identity default)."
}
