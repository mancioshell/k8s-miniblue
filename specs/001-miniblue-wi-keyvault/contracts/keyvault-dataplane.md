# Contract: Key Vault data-plane (canonical host)

The emulator MUST serve the Key Vault secrets data-plane API on the **canonical host**
`https://<vault>.vault.azure.net`, matching the shape the Azure SDKs/CSI provider expect. Token
authentication is accepted but validated leniently (emulator).

## Host & TLS

- Requests arrive with `Host: <vault>.vault.azure.net` (resolved to miniblue via in-cluster DNS).
- TLS is served by miniblue's self-signed **CA** cert, whose SANs now include `*.vault.azure.net`.
- Authorization: `Authorization: Bearer <access_token>` accepted; missing/invalid token MAY still be
  served (lenient) but the canonical 401 challenge shape SHOULD be available for fidelity.

## Endpoints

### GET a secret

```
GET https://<vault>.vault.azure.net/secrets/{name}?api-version=7.4
Authorization: Bearer <token>
→ 200
{
  "id": "https://<vault>.vault.azure.net/secrets/{name}/<version>",
  "value": "<secret-value>",
  "attributes": { "enabled": true, "created": <epoch>, "updated": <epoch> }
}
```
Unknown secret → `404` with the Azure error envelope (`{"error":{"code":"SecretNotFound",...}}`).

### SET a secret

```
PUT https://<vault>.vault.azure.net/secrets/{name}?api-version=7.4
Content-Type: application/json
{ "value": "<secret-value>" }
→ 200  (same body shape as GET)
```

### DELETE a secret

```
DELETE https://<vault>.vault.azure.net/secrets/{name}?api-version=7.4
→ 200
```

### LIST secrets

```
GET https://<vault>.vault.azure.net/secrets?api-version=7.4
→ 200
{ "value": [ { "id": "https://<vault>.vault.azure.net/secrets/{name}", "attributes": {...} } ], "nextLink": null }
```
`value` MUST be redacted (omitted) in the list response.

## Behavioral requirements

- `api-version` query parameter is accepted and does not cause failure (lenient).
- The legacy non-standard `/keyvault/<vault>/secrets/...` path is **not** required and may be
  removed; the canonical host is the only supported addressing (seeding uses the canonical path).
- Store semantics are unchanged (`kv:<vault>:<name>`); only the front-door routing is new.

## Acceptance (maps to SC-001, SC-002)

- A standard Azure Key Vault SDK call to `https://<vault>.vault.azure.net/secrets/<name>` returns the
  stored value without any URL rewriting in the path.
- The Secrets Store CSI Azure provider mounts the secret using only the canonical host.
