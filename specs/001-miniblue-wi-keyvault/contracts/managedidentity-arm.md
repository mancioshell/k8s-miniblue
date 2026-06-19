# Contract: Microsoft.ManagedIdentity ARM control plane

The emulator MUST implement the `Microsoft.ManagedIdentity` ARM resources so that
`azurerm_user_assigned_identity` and `azurerm_federated_identity_credential` apply for real
(replacing today's stub). Routes follow miniblue's existing per-service ARM pattern.

## User-Assigned Identity

### Create / update
```
PUT /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{name}?api-version=2023-01-31
{ "location": "<loc>", "tags": { ... } }
→ 200/201
{
  "id": "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{name}",
  "name": "{name}",
  "location": "<loc>",
  "properties": {
    "clientId": "<uuid>",
    "principalId": "<uuid>",
    "tenantId": "<uuid>"
  }
}
```

### Get / delete
```
GET    .../userAssignedIdentities/{name}?api-version=2023-01-31  → 200 (same shape)  | 404 if absent
DELETE .../userAssignedIdentities/{name}?api-version=2023-01-31  → 200/204
```

### Requirements
- `clientId`/`principalId` MUST be stable across applies for a given `{sub}/{rg}/{name}` (deterministic)
  so chart wiring (`managedIdentityClientId`) stays fixed.
- `location` required (Azure parity); missing → `400` Azure error envelope.

## Federated Identity Credential (nested child)

### Create / update
```
PUT .../userAssignedIdentities/{name}/federatedIdentityCredentials/{ficName}?api-version=2023-01-31
{
  "properties": {
    "issuer": "<k3s service-account-issuer URL>",
    "subject": "system:serviceaccount:<namespace>:<serviceAccountName>",
    "audiences": ["api://AzureADTokenExchange"]
  }
}
→ 200/201  (echoes id + properties)
```

### Get / list / delete
```
GET    .../federatedIdentityCredentials/{ficName}  → 200 | 404
GET    .../federatedIdentityCredentials            → 200 { "value": [ ... ] }
DELETE .../federatedIdentityCredentials/{ficName}  → 200/204
```

### Requirements
- Parent UAMI MUST exist (else `404`/`400`).
- `issuer`, `subject`, `audiences` required.
- `id` = parent id + `/federatedIdentityCredentials/{ficName}`.

## Acceptance (maps to FR-009, FR-010, US3)

- `terraform apply` of `azurerm_user_assigned_identity` + `azurerm_federated_identity_credential`
  succeeds against miniblue and the objects are retrievable via GET.
- The created FIC `subject` matches the annotated ServiceAccount used by the workload, closing the
  federation loop.
