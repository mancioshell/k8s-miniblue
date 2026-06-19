# Phase 1 Data Model: miniblue Workload Identity + standard Key Vault data-plane API

Entities are the resources the emulator and the IaC must represent. miniblue persists ARM/data-plane
objects in its in-memory `store.Store` (key conventions noted); the IaC layer persists the bindings
in Terraform state.

---

## UserAssignedIdentity (ARM, miniblue: NEW)

Represents `Microsoft.ManagedIdentity/userAssignedIdentities/{name}`. Promotes today's stub into a
real ARM object.

| Field | Type | Notes |
|---|---|---|
| `id` | string | `/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{name}` |
| `name` | string | identity name (`uaid-<suffix>`) |
| `location` | string | from request |
| `properties.clientId` | string (uuid) | stable per identity; surfaced to chart as `clientID` |
| `properties.principalId` | string (uuid) | stable per identity |
| `properties.tenantId` | string (uuid) | emulator tenant (`11111111-…`) |
| `tags` | map<string,string> | optional |

- **Store key**: `uaid:<sub>:<rg>:<name>`.
- **Validation**: `name` required; `location` required (Azure parity). clientId/principalId
  generated deterministically if absent so wiring stays stable across applies.
- **Lifecycle**: PUT (create/update) → GET → DELETE.

## FederatedIdentityCredential (ARM, miniblue: NEW)

Nested child of a UserAssignedIdentity:
`.../userAssignedIdentities/{name}/federatedIdentityCredentials/{ficName}`. This is the core new
entity — it binds the cluster's SA token to the identity.

| Field | Type | Notes |
|---|---|---|
| `id` | string | parent id + `/federatedIdentityCredentials/{ficName}` |
| `name` | string | FIC name (one per service, e.g. `service-a`) |
| `properties.issuer` | string (URL) | the k3s SA token issuer (`service-account-issuer`) |
| `properties.subject` | string | `system:serviceaccount:<namespace>:<serviceAccountName>` |
| `properties.audiences` | string[] | typically `["api://AzureADTokenExchange"]` |

- **Store key**: `fic:<sub>:<rg>:<name>:<ficName>`.
- **Validation**: `issuer`, `subject`, `audiences` required; parent UAMI must exist.
- **Relationship**: many FICs → one UAMI (one per service ServiceAccount).
- **Lifecycle**: PUT → GET → LIST (under parent) → DELETE.

## KeyVaultSecret (data-plane, miniblue: EXISTING, new host route)

| Field | Type | Notes |
|---|---|---|
| `id` | string | `https://<vault>.vault.azure.net/secrets/<name>` (already minted) |
| `value` | string | secret value (redacted in List) |
| `attributes` | object | enabled / timestamps |

- **Store key**: `kv:<vault>:<name>` (unchanged).
- **New access path**: `https://<vault>.vault.azure.net/secrets/<name>?api-version=...` resolved via
  the host-suffix middleware (R1) to the existing handler. The legacy `/keyvault/<vault>/secrets/…`
  path is not required and may be removed.

## OAuth2 Token + signing key (auth, miniblue: EXTENDED)

Represents the AAD token endpoint behavior and the new signing material.

| Field | Type | Notes |
|---|---|---|
| `access_token` | string (JWT) | now **RS256-signed** (was `alg:none`); claims `aud`,`iss`,`oid`,`sub`,`tid`,`appid`,`iat`,`nbf`,`exp` |
| `token_type` | string | `Bearer` |
| `expires_in` | int | seconds |
| signing key (RSA) | std-lib `crypto/rsa` keypair | generated at startup, kept in process; public part published via JWKS |

- **Grants accepted** (lenient): `client_credentials` (incl. `client_assertion` /
  `client_assertion_type=…jwt-bearer`), and the existing grants.
- **JWKS**: `/{tenantId}/discovery/v2.0/keys` returns the public RSA key as a JWK set (consistent
  with the `jwks_uri` already advertised by OIDC discovery).

## ServiceAccount binding (Kubernetes, chart: NEW template)

Not an Azure entity but the cluster-side half of the federation.

| Field | Type | Notes |
|---|---|---|
| `metadata.name` | string | per service (e.g. `service-a`) |
| `metadata.annotations["azure.workload.identity/client-id"]` | string | UAMI `clientId` |
| `metadata.annotations["azure.workload.identity/tenant-id"]` | string | tenant |
| pod label `azure.workload.identity/use` | string | `"true"` — triggers the webhook |

- **Relationship**: the FIC `subject` = `system:serviceaccount:<ns>:<this SA name>`. This is the
  join key between the Azure FederatedIdentityCredential and the Kubernetes ServiceAccount.

---

## Entity relationships

```text
UserAssignedIdentity (clientId, principalId)
        │ 1
        │
        │ N
FederatedIdentityCredential (issuer, subject, audiences)
        │  subject = system:serviceaccount:<ns>:<sa>
        ▼
Kubernetes ServiceAccount (annotated clientId + pod label use=true)
        │ pod uses SA → webhook injects projected token + AZURE_* env
        ▼
WorkloadIdentityCredential → OAuth2 token endpoint (client_assertion → RS256 access_token)
        │ Bearer access_token
        ▼
KeyVaultSecret @ https://<vault>.vault.azure.net/secrets/<name>
```
