# federated-credential (Azure Workload Identity FICs)

Registers one `azurerm_federated_identity_credential` per service, binding the
shared user-assigned managed identity to each service's Kubernetes ServiceAccount
for Azure Workload Identity (FR-014 / R5 / US3).

For every entry in `var.services` the credential is registered with:

- **issuer** = `var.issuer` — the k3s `service-account-issuer` (`MINIBLUE_SA_ISSUER`),
  matching the `iss` claim of the projected ServiceAccount token (T016).
- **subject** = `system:serviceaccount:<namespace>:<service_account>` — matching the
  annotated SA created by the service chart (`<service>-sa`, T018).
- **audience** = `api://AzureADTokenExchange` — the Workload Identity exchange audience.

miniblue does not enforce the FIC at token-exchange time (lenient model), but the
credential is still registered so the topology matches a real Azure deployment.

| Input | Default | Required | Notes |
|-------|---------|----------|-------|
| `resource_group_name` | — | yes | RG of the parent UAMI. |
| `user_assigned_identity_id` | — | yes | `managed-identity` output `id`. |
| `issuer` | — | yes | `MINIBLUE_SA_ISSUER`. |
| `services` | `service-a`, `service-b` | no | `key -> { namespace, service_account }`. |
| `audience` | `api://AzureADTokenExchange` | no | Token exchange audience. |
