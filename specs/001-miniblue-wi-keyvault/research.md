# Phase 0 Research: miniblue Workload Identity + standard Key Vault data-plane API

All Technical Context unknowns are resolved below. Each item records the **decision**, the
**rationale**, and the **alternatives considered**. Findings are grounded in the upstream miniblue
source (cloned read-only to `tmp/miniblue/`, ref `v0.7.0`) and this repository's current wiring.

---

## R1 — Key Vault on the canonical host `<vault>.vault.azure.net`

**Current state**: `internal/server/server.go` uses a single path-based `chi` router with **no
host-based routing**. `internal/services/keyvault/handler.go` registers the non-standard path
`/keyvault/{vaultName}/secrets/{secretName}` (GET/PUT/DELETE/List); secret IDs are already minted as
`https://<vault>.vault.azure.net/secrets/<name>`. The demo today only reaches this via the
`cluster-wiring` URL-rewriting proxy.

**Decision**: Add a **host-aware routing adapter** in front of the existing keyvault handler. A
small middleware (registered early on `s.router`) inspects the request `Host` header: when it ends
with `.vault.azure.net`, it extracts the vault name from the left-most label and internally rewrites
the request path from `/secrets/...` to the handler's existing `/keyvault/<vault>/secrets/...`
shape (or sets the `vaultName` route param directly). The canonical data-plane routes
`GET/PUT/DELETE /secrets/{name}` and `GET /secrets` are registered on a host-scoped sub-router so
the existing handler logic and store keys (`kv:<vault>:<name>`) are reused unchanged. The
`api-version` query parameter is accepted and echoed/ignored (lenient), matching the existing
`APIVersionCheck` middleware behavior.

**Rationale**: Reuses all existing storage, ID-minting, and error envelopes; the change is purely a
front-door routing concern. The legacy `/keyvault/...` path is not required and may be removed once
the canonical host is served (seeding moves to the canonical path). No proxy needed once the host is
served directly.

**Alternatives considered**:
- *chi host matcher per vault* — rejected: vault names are dynamic; a suffix-match middleware is
  simpler and covers any vault.
- *Keep the rewriting proxy* — rejected: the whole point (US1/FR-012) is to remove the shim.

---

## R2 — TLS certificate SANs for the canonical hosts

**Current state**: `cmd/miniblue/main.go:generateAndSaveCert` builds a **self-signed CA** cert
(`IsCA: true`) with `DNSNames: ["localhost"]` + loopback IPs, served on HTTP `:4566` and HTTPS
`:4567` for the same handler. The cert is cached/reused in `LOCAL_AZURE_CERT_DIR` (`~/.miniblue`).

**Decision**: Extend the `DNSNames` list to include `*.vault.azure.net`, `vault.azure.net`, and the
AAD authority hosts the SDKs use — `login.microsoftonline.com`, `login.windows.net`,
`sts.windows.net` — plus keep `localhost`. Because the cert is already a self-signed **CA**, the
cluster only needs to trust this one CA (as it already does); SNI for the canonical hosts then
succeeds without per-run cert generation in `cluster-wiring`. Regeneration must trigger when the
cached cert lacks the new SANs (bump validity/SAN check or a one-time cache invalidation).

**Rationale**: Moves the `*.vault.azure.net` cert responsibility from the shim into the emulator
itself — the faithful place for it. One CA trust anchor already exists in the cluster.

**Alternatives considered**:
- *Separate leaf certs per host* — rejected: a single wildcard+SAN CA cert is simpler and already
  the established pattern.

---

## R3 — Workload Identity token exchange (`client_assertion`)

**Current state**: `internal/services/auth/handler.go` already exposes
`/{tenantId}/oauth2/v2.0/token` and `/{tenantId}/oauth2/token`, and `Token()` mints a JWT for **any**
request via `mockJWT()` with header `alg:none`. OIDC discovery (`.well-known/openid-configuration`)
is served and advertises `jwks_uri = base/{tenantId}/discovery/v2.0/keys` — **but no handler exists
for that JWKS path** (would 404).

**Decision**: The federated-credential grant (`grant_type=client_credentials` with
`client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer` and a
`client_assertion` = the projected SA token) is accepted by the existing token endpoint — it
already issues a token for any grant. Two fidelity gaps are closed: (a) **add the JWKS endpoint**
`/{tenantId}/discovery/v2.0/keys` returning a JWK set; (b) **sign issued tokens RS256** with a
stable RSA key generated at startup and published in that JWKS (replacing `alg:none`). Validation of
the inbound `client_assertion` remains **lenient** (the emulator does not cryptographically verify
the cluster's signature) — fidelity is at the protocol/shape level per the spec constraints.

**Rationale**: Real SDK code paths (`WorkloadIdentityCredential`) POST the assertion and parse a
normal token + a resolvable `jwks_uri`; closing the JWKS 404 and signing RS256 makes discovery
self-consistent without requiring full AAD crypto. Std-lib `crypto/rsa` avoids a new dependency.

**Alternatives considered**:
- *Keep `alg:none`* — rejected: discovery advertises a JWKS; leaving it 404 is an avoidable
  inconsistency and some SDKs reject `alg:none`.
- *Add `golang-jwt`* — rejected: the handler already hand-rolls base64url JWTs; RS256 signing is a
  few std-lib lines, no new module needed.
- *Fully validate the assertion against the k3s JWKS* — deferred: unnecessary for a local emulator
  and adds cross-component coupling; noted as a possible future fidelity upgrade.

---

## R4 — `Microsoft.ManagedIdentity` ARM control plane (UAMI + federated credentials)

**Current state**: **No** handler implements `Microsoft.ManagedIdentity` — it only appears in the
`subscriptions` provider list. Each Azure service registers its own
`/subscriptions/.../providers/Microsoft.X/...` route (e.g. `aci`, `acr`, `aks`). Today this repo's
`managed-identity` module is an explicit **stub** (per its header comment): creating a UAMI returns
404, so it fabricates constant `client_id`/`principal_id` and relies on IMDS issuing tokens for any
client_id.

**Decision**: Add a **new `internal/services/managedidentity` handler** that implements the ARM
control plane, mirroring the existing per-service route pattern and using `store.Store`:
- `PUT/GET/DELETE /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{name}`
  returning `id`, `properties.clientId`, `properties.principalId`, `properties.tenantId`.
- `PUT/GET/DELETE/LIST .../userAssignedIdentities/{name}/federatedIdentityCredentials/{ficName}`
  storing `properties.issuer`, `properties.subject`, `properties.audiences`.
Register it in `internal/server/server.go`. This lets `azurerm_user_assigned_identity` and
`azurerm_federated_identity_credential` apply for real, so the binding becomes declarative IaC
(US3/FR-009/FR-010) instead of a stub.

**Rationale**: Federated credentials are the heart of the WI feature and must be expressible as
Terraform. Implementing the ARM resource follows the emulator's own established conventions and
removes the need for the constant-stub workaround.

**Alternatives considered**:
- *Keep the stub + only emulate the token exchange* — rejected: US3 explicitly requires the
  federated credential to exist as managed IaC; a stub can't be `azurerm_federated_identity_credential`.

---

## R5 — k3s OIDC issuer + the `azure-workload-identity` webhook

**Current state**: miniblue's real AKS backend runs single-node **k3s** in Docker. Pods today get
KV secrets via the Secrets Store CSI driver with `useVMManagedIdentity: "true"` (IMDS), wired by the
`cluster-wiring` DNAT. No workload-identity webhook is installed.

**Decision**:
- **Enable the SA token issuer** on k3s via kube-apiserver args (`--kube-apiserver-arg` for
  `service-account-issuer` and `service-account-jwks-uri`) so projected ServiceAccount tokens carry
  a stable issuer/audience. Because miniblue's assertion validation is lenient (R3), publicly
  exposing the cluster JWKS to miniblue is **optional**; the issuer value is still set for fidelity
  and to match the federated-credential `issuer`.
- **Install the official `azure-workload-identity` mutating webhook** (Helm) via a new
  `infrastructure/modules/workload-identity` module. It watches pods labeled
  `azure.workload.identity/use: "true"` whose ServiceAccount is annotated with
  `azure.workload.identity/client-id`, and injects the projected token volume +
  `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_FEDERATED_TOKEN_FILE` / `AZURE_AUTHORITY_HOST`
  env. `AZURE_AUTHORITY_HOST` is pointed at miniblue.

**Rationale**: This is exactly how real AKS does Workload Identity (the user's chosen Option A —
"come fa Azure su AKS"). Using the official webhook maximizes fidelity and means the app/CSI code
paths are unmodified Azure SDK behavior.

**Alternatives considered**:
- *Manually inject the token volume + env in the Helm chart (no webhook)* — rejected by the user in
  favor of the official webhook (higher fidelity).
- *Drop k3s issuer config and rely purely on lenient validation* — partially kept (issuer set for
  fidelity, validation lenient), but issuer is still configured to keep the federated-credential
  subject/issuer meaningful.

---

## R6 — ServiceAccount + chart wiring; CSI vs direct SDK

**Current state**: `gitops/.../service-chart-template/templates/secretproviderclass.yaml` uses
`usePodIdentity:"false"`, `useVMManagedIdentity:"true"`, `userAssignedIdentityID:<clientId>`. Values
carry `managedIdentityClientId` + `tenantId` per service.

**Decision**: Add an **annotated ServiceAccount** template to the shared chart
(`azure.workload.identity/client-id: <UAMI clientId>`, `azure.workload.identity/tenant-id`) and the
pod label `azure.workload.identity/use: "true"`; deployments must reference that SA. Switch the
SecretProviderClass to **workload-identity mode**: `useVMManagedIdentity:"false"`,
`usePodIdentity:"false"`, `clientID:<UAMI clientId>` (the Azure CSI provider supports WI). The CSI
driver is **retained** (keeps the existing env-injection UX); the app does not need code changes.
Whether to additionally demonstrate app-level `WorkloadIdentityCredential` (no CSI) is **out of
scope** here — noted as a follow-up.

**Rationale**: One SA per service (not per pod) is the real Azure model; the webhook needs the SA
annotation + pod label. Keeping CSI in WI mode is the smallest change that exercises the real WI
token on the provider side.

**Alternatives considered**:
- *Remove CSI, read KV in-app via azidentity* — deferred (larger app change; spec keeps app
  untouched).
- *Per-pod identity annotations* — rejected: Azure WI binds identity to the ServiceAccount.

---

## R7 — Decommissioning the `cluster-wiring` shim

**Decision**: Remove from `cluster-wiring`: the **IMDS DNAT** (no longer used — WI replaces IMDS),
the **KV URL-rewriting proxy** (KV now served on the canonical host directly, R1), and the **per-run
`*.vault.azure.net` cert generation** (now in miniblue's own cert, R2). **Keep**: CoreDNS overrides
mapping `*.vault.azure.net` and the AAD authority host(s) to miniblue, and the **CA-trust**
distribution (the cluster must still trust miniblue's self-signed CA). The existing CSI shared-mount
fix stays (tracked separately/out of scope of this spec).

**Rationale**: Satisfies FR-012 ("replace the shim, standards-only") while acknowledging that DNS
name resolution + CA trust for a local self-hosted endpoint are legitimate, non-interception
infrastructure concerns (per the spec's Constraints).

**Alternatives considered**:
- *Remove DNS overrides too (real public Azure DNS)* — impossible locally; the emulator must be
  resolvable under the canonical names.

---

## Resolved unknowns summary

| Unknown (Technical Context) | Resolution |
|---|---|
| KV canonical-host serving approach | R1 — host-suffix middleware → existing keyvault handler |
| TLS trust for canonical hosts | R2 — extend miniblue CA cert SANs |
| WI token exchange feasibility | R3 — existing token endpoint + JWKS endpoint + RS256 signing (lenient validation) |
| Federated credential as IaC | R4 — new `managedidentity` ARM handler (UAMI + FIC) |
| Token injection mechanism | R5 — official `azure-workload-identity` webhook + k3s issuer |
| Chart / CSI auth mode | R6 — annotated SA + WI-mode SecretProviderClass, CSI retained |
| Shim removal boundary | R7 — drop DNAT + proxy + cert-gen; keep DNS + CA trust |
