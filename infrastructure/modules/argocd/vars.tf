# REQUIRED MODULE PARAMETERS
variable "kubeconfig_path" {
  type        = string
  description = "Path to the AKS admin kubeconfig written by scripts/startup.sh."
}

variable "gitops_repo_url" {
  type        = string
  default     = ""
  description = "GitOps Git repo URL that ArgoCD watches (desired state). Empty = install ArgoCD only, no repo registered and no root app. Set via GITOPS_REPO_URL in scripts/startup.sh."
}

# OPTIONAL MODULE PARAMETERS
variable "argocd_chart_version" {
  type        = string
  default     = "7.7.11"
  description = "Pinned argo/argo-cd Helm chart version (see versions.md)."
}

variable "gitops_repo_revision" {
  type        = string
  default     = "main"
  description = "Branch/revision of the GitOps repo the root app tracks."
}

variable "gitops_repo_username" {
  type        = string
  default     = "git"
  description = "Username for a PRIVATE GitOps repo (any non-empty value for a PAT, e.g. 'git' or 'x-access-token'). Ignored when gitops_repo_token is empty."
}

variable "gitops_repo_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "PAT for a PRIVATE GitOps repo. Empty = public repo (no auth). Pass via TF_VAR_gitops_repo_token — never commit it."
}

variable "enable_root_app" {
  type        = bool
  default     = false
  description = "Create the root App-of-Apps now. Defaults false until the GitOps repo is populated (US3)."
}

variable "oci_chart_repo_url" {
  type        = string
  default     = ""
  description = "OCI Helm repo URL (no oci:// scheme) ArgoCD pulls the shared chart from, e.g. ghcr.io/mancioshell/charts. Empty = not registered."
}

variable "oci_registry_username" {
  type        = string
  default     = ""
  description = "Username for a PRIVATE OCI registry (GitHub owner/user). Ignored when oci_registry_token is empty."
}

variable "oci_registry_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "PAT with read:packages for pulling the shared chart from a PRIVATE OCI registry. Empty = public (no auth). Pass via TF_VAR_oci_registry_token."
}
