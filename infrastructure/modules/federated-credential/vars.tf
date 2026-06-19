# REQUIRED MODULE PARAMETERS
variable "resource_group_name" {
  type        = string
  description = "Resource group that holds the parent user-assigned managed identity."
}

variable "user_assigned_identity_id" {
  type        = string
  description = "Resource ID of the parent user-assigned managed identity (managed-identity output `id`)."
}

variable "issuer" {
  type        = string
  description = "OIDC issuer of the projected ServiceAccount tokens (k3s service-account-issuer, MINIBLUE_SA_ISSUER)."
}

# OPTIONAL MODULE PARAMETERS
variable "services" {
  type = map(object({
    namespace       = string
    service_account = string
  }))
  default = {
    service-a = { namespace = "service-a", service_account = "service-a-sa" }
    service-b = { namespace = "service-b", service_account = "service-b-sa" }
  }
  description = "Services to bind: map key -> { namespace, service_account }. Subject = system:serviceaccount:<namespace>:<service_account>."
}

variable "audience" {
  type        = string
  default     = "api://AzureADTokenExchange"
  description = "Token audience the federated credential accepts (Workload Identity default)."
}
