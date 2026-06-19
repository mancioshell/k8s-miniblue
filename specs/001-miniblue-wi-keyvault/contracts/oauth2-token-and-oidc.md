# Contract: OAuth2 token + OIDC discovery / JWKS (AAD emulation)

The emulator MUST behave as the Azure AD authority for the Workload Identity flow: serve OIDC
discovery + a resolvable JWKS, and honor the federated `client_assertion` token exchange. Inbound
assertion validation is **lenient** (no cryptographic verification of the cluster signature);
fidelity is at the protocol/shape level.

## Authority host & TLS

- Reachable as `https://login.microsoftonline.com` (and `login.windows.net` / `sts.windows.net`)
  via in-cluster DNS, or directly via the configured `AZURE_AUTHORITY_HOST`.
- miniblue's CA cert SANs include those authority hosts.

## OIDC discovery

```
GET https://<authority>/{tenantId}/v2.0/.well-known/openid-configuration
→ 200
{
  "issuer": "https://<authority>/{tenantId}/v2.0",
  "token_endpoint": "https://<authority>/{tenantId}/oauth2/v2.0/token",
  "jwks_uri": "https://<authority>/{tenantId}/discovery/v2.0/keys",
  ...
}
```
`jwks_uri` MUST resolve (today it 404s — this contract closes that gap).

## JWKS (NEW)

```
GET https://<authority>/{tenantId}/discovery/v2.0/keys
→ 200
{ "keys": [ { "kty":"RSA", "use":"sig", "kid":"<kid>", "n":"<base64url>", "e":"AQAB", "alg":"RS256" } ] }
```
The published key MUST match the key used to sign issued access tokens.

## Token endpoint — federated (Workload Identity) grant

```
POST https://<authority>/{tenantId}/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=<UAMI clientId>
&scope=https://vault.azure.net/.default
&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
&client_assertion=<projected ServiceAccount token>
→ 200
{ "token_type": "Bearer", "expires_in": 3600, "access_token": "<RS256 JWT>" }
```

### Requirements
- The `client_assertion` grant MUST be accepted (the existing endpoint already issues a token for
  any grant; this contract pins the federated grant explicitly).
- The issued `access_token` MUST be **RS256-signed** (replacing `alg:none`) with the JWKS-published
  key, and carry claims `aud` (the requested resource, e.g. `https://vault.azure.net`), `iss`
  (`https://<authority>/{tenantId}/v2.0`), `tid`, `oid`, `sub`, `appid`, `iat`, `nbf`, `exp`.
- Inbound `client_assertion` is NOT cryptographically validated (lenient emulator) — but it MAY be
  decoded to echo `sub`/`appid` for realism.

## Acceptance (maps to SC-003, SC-004, FR-006, FR-007)

- A pod's `WorkloadIdentityCredential` obtains an access token by POSTing its projected token as
  `client_assertion`, with no IMDS endpoint involved.
- OIDC discovery → `jwks_uri` → JWKS resolves end-to-end and the JWKS key verifies the token header
  `kid`.
