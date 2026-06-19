# MODULE OUTPUTS
output "kv_ca_configmap" {
  value       = "miniblue-kv-ca"
  description = "Name of the kube-system ConfigMap holding the miniblue CA bundle the CSI provider trusts."
}

output "ready" {
  value       = null_resource.dns_ca_trust.id
  description = "Sentinel that downstream units (argocd, secrets-csi) depend on to enforce ordering."
}
