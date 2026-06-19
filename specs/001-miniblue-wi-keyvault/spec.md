# Feature Specification: miniblue Workload Identity + standard Key Vault data-plane API

**Feature Branch**: `001-miniblue-wi-keyvault`

**Created**: 2026-06-19

**Status**: Draft

**Input**: User description: "Voglio modificare miniblue in modo che supporti sia workload identity. Ed esporre il servizio di keyvault con le api arm standard di azure"

## Overview

The k8s-miniblue demo currently bridges the gaps in the miniblue Azure emulator with a
custom in-cluster shim (the `cluster-wiring` module): an IMDS DNAT rule, a TLS proxy that
rewrites `<vault>.vault.azure.net/secrets/...` requests to miniblue's non-standard
`/keyvault/<vault>/secrets/...` path, and a self-signed certificate for `*.vault.azure.net`.
This exists because (a) miniblue exposes Key Vault on a non-standard URL shape and (b) miniblue
has no Azure AD Workload Identity (federated credential) flow, so pod identity has to be faked
through IMDS interception.

This feature makes the emulator itself faithful to the real Azure contracts so that **standard,
unmodified Azure clients** (the Azure SDKs and the official Secrets Store CSI Azure provider)
can authenticate via **Workload Identity** and read secrets from Key Vault using the **standard
data-plane API**, eliminating the custom interception shim.

## Clarifications

### Session 2026-06-19

- Q: How strictly must miniblue validate the federated token (assertion → access token) against registered federated credentials? → A: Lenient (Option B) — miniblue issues an access token for any well-formed federated request and does NOT enforce the registered federated credential at runtime; the federated credential is infrastructure-only (must apply cleanly via Terraform), and the Secrets Store CSI driver must operate in the standard Workload Identity mode against the canonical Key Vault host.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read a Key Vault secret via the standard data-plane API (Priority: P1)

A developer (or any standard Azure client/SDK) requests a secret from Key Vault using the
canonical vault address `https://<vault>.vault.azure.net/secrets/<name>?api-version=<v>` and
receives the standard response, with no URL rewriting in between.

**Why this priority**: This is the foundational contract. Without standard data-plane
addressing, no unmodified Azure SDK or the CSI Azure provider can talk to the emulator, and the
rewriting proxy cannot be removed. It delivers value on its own (standard KV access) even before
Workload Identity is added.

**Independent Test**: Point an unmodified Azure Key Vault SDK (or `curl` against the canonical
host, with DNS routed to miniblue and miniblue's CA trusted) at `https://<vault>.vault.azure.net/secrets/<name>?api-version=<v>`
and confirm the secret value comes back in the standard envelope (`id`, `value`, `attributes`),
without the `cluster-wiring` URL-rewrite proxy running.

**Acceptance Scenarios**:

1. **Given** a secret seeded in vault `kv-mb-local`, **When** a client GETs
   `https://kv-mb-local.vault.azure.net/secrets/app-greeting-secret?api-version=<supported>`,
   **Then** miniblue returns HTTP 200 with the standard Key Vault secret JSON (`id`, `value`,
   `attributes`).
2. **Given** the same vault, **When** a client lists secrets via the standard list endpoint,
   **Then** miniblue returns the standard list shape with secret **values redacted**.
3. **Given** a non-existent secret, **When** a client GETs it, **Then** miniblue returns the
   standard Azure Key Vault 404 error envelope.

---

### User Story 2 - Authenticate a workload via Workload Identity (Priority: P1)

A pod uses the **standard Azure Workload Identity** credential chain — a projected service
account token is exchanged at the token endpoint (federated `client_assertion` / JWT-bearer
grant) for an access token scoped to Key Vault — with **no IMDS interception**.

**Why this priority**: This is the explicit second half of the request and the only way to drop
the IMDS DNAT. Combined with Story 1 it lets a real workload read a secret end-to-end the way it
would on a production AKS cluster.

**Independent Test**: Deploy a pod configured for standard Workload Identity (projected SA token
+ authority host pointing at miniblue) bound to a user-assigned identity that has a federated
credential, and confirm it acquires a Key Vault token and reads the secret — with the IMDS DNAT
rule absent.

**Acceptance Scenarios**:

1. **Given** a user-assigned identity with a federated identity credential bound to the
   cluster's issuer/subject/audience, **When** a workload presents its projected token to the
   token endpoint using the federated grant, **Then** miniblue issues an access token for the
   requested Key Vault resource.
2. **Given** that token, **When** the workload calls the standard Key Vault data-plane API,
   **Then** the secret is returned (Story 1 contract).
3. **Given** the OIDC discovery document advertised by miniblue, **When** a client fetches the
   issuer's discovery and signing-key (JWKS) endpoints, **Then** both resolve and are internally
   consistent with the tokens miniblue issues.

---

### User Story 3 - Provision the federated identity binding as infrastructure (Priority: P2)

The platform engineer declares the federated identity credential (the binding between the
user-assigned identity and the cluster's OIDC issuer/subject/audience) as Terraform/Terragrunt
infrastructure, applied as part of the normal stack bring-up.

**Why this priority**: Makes the Workload Identity path reproducible and GitOps-friendly rather
than a manual step, but the runtime flow (Stories 1–2) can be demonstrated before the IaC is
wired.

**Independent Test**: Run the stack apply and confirm the federated identity credential object
exists in the emulator and the workload authenticates on first sync, with no manual token or
secret seeding for identity.

**Acceptance Scenarios**:

1. **Given** the infrastructure definitions, **When** the stack is applied, **Then** a federated
   identity credential is created on the user-assigned identity and is visible to the emulator.
2. **Given** a re-apply, **When** nothing changed, **Then** the federated credential provisioning
   is idempotent (no spurious diffs).

---

### Edge Cases

- A workload presents a token whose issuer/subject/audience does **not** match any registered
  federated credential — **resolved (lenient)**: miniblue still issues the access token; the
  federated credential is not enforced at runtime (see Clarifications 2026-06-19).
- A Key Vault request arrives **without** an `api-version` or with an unsupported one — define
  whether miniblue tolerates it or returns the standard "api-version required" error.
- A Key Vault request reaches miniblue addressed by the **legacy** non-standard path
  (`/keyvault/<vault>/secrets/...`) after the standard host routing is added — define whether the
  legacy path stays for backward compatibility or is removed.
- The vault host TLS certificate is not trusted by the client — define how trust is established
  without the old per-run cert-generation step.
- The Secrets Store CSI driver still requires a shared kubelet mount in k3s-in-docker — clarify
  this remains a node concern, independent of the Azure-emulation changes in this feature.

## Requirements *(mandatory)*

### Functional Requirements

#### Key Vault standard data-plane API

- **FR-001**: miniblue MUST serve the Key Vault data-plane API addressed by the **standard vault
  host** (`<vault>.vault.azure.net`) so that unmodified Azure SDKs and the official Secrets Store
  CSI Azure provider resolve the vault by its canonical name.
- **FR-002**: miniblue MUST support the standard secret operations (get, set, list, delete) at the
  standard paths and honor the standard `api-version` query parameter.
- **FR-003**: miniblue MUST return the **standard Azure Key Vault response shapes** — secret
  envelope (`id`, `value`, `attributes`), list responses with secret **values redacted**, and the
  standard Azure error envelope for not-found and other errors.
- **FR-004**: miniblue MUST terminate TLS for the vault host so that a client trusting miniblue's
  certificate authority can call `https://<vault>.vault.azure.net/...` directly, removing the need
  for an external TLS-terminating, URL-rewriting proxy.

#### Workload Identity

- **FR-005**: miniblue MUST accept registration of a **federated identity credential** on a
  user-assigned managed identity, capturing the binding attributes (issuer, subject, audience).
- **FR-006**: miniblue MUST accept a **federated token request** (client-assertion / JWT-bearer
  grant) at the token endpoint and issue an access token scoped to the requested resource
  (e.g. Key Vault). Validation is **lenient**: the token is issued for any well-formed federated
  request and is **not** gated on a matching registered federated credential at runtime (the
  federated credential is infrastructure-only — see FR-005 and Clarifications 2026-06-19).
- **FR-007**: miniblue MUST expose an **OIDC discovery document and signing-key (JWKS) surface**
  that resolve successfully and are internally consistent with the access/ID tokens it issues.
- **FR-008**: A workload using the **standard Azure Workload Identity credential chain** MUST be
  able to obtain a Key Vault access token from miniblue **without any IMDS interception**
  (no DNAT redirect of the IMDS address).

#### Integration / shim removal

- **FR-009**: With FR-001..FR-008 in place, the demo MUST reach a Key Vault secret end-to-end
  **without** the `cluster-wiring` IMDS DNAT rule, the KV URL-rewriting proxy, or the per-run
  `*.vault.azure.net` certificate generation.
- **FR-010**: The modified emulator MUST remain compatible with the existing stack provisioning
  for all **other** Azure objects already used by the demo (resource group, managed identity,
  ACR, AKS, the existing ARM/metadata surface) — i.e. no regression of current functionality.
- **FR-011**: The modified miniblue MUST live in a **maintained fork** of the upstream project,
  pinned to a specific ref, and be consumed by this repository through the existing
  source-build flow (`MINIBLUE_SRC_REPO` / `MINIBLUE_SRC_REF` building the custom `full` image) —
  preserving the "consume miniblue as a pinned artifact" boundary, now pointed at the fork.

### Behavior decisions (confirmed)

- **FR-012**: The scope of this feature is to **replace** the `cluster-wiring` IMDS/proxy shim
  with the standard Workload-Identity + standard Key Vault data-plane path (standards-only). The
  IMDS DNAT, the KV URL-rewriting proxy, and the per-run `*.vault.azure.net` certificate
  generation are removed; there is a single, standards-faithful path (no selectable fallback).
- **FR-013**: The pod-side Workload Identity wiring MUST be provided by the **official
  `azure-workload-identity` mutating admission webhook** (the same mechanism Azure uses on AKS):
  an annotated ServiceAccount per service plus the `azure.workload.identity/use: "true"` pod label,
  with the webhook injecting the projected token volume and the `AZURE_*` environment variables.
  Manual chart-level token/env injection is explicitly **not** chosen.

### Key Entities

- **Federated Identity Credential**: the binding between a user-assigned managed identity and an
  OIDC issuer/subject/audience; the basis on which the emulator decides to honor a federated token
  request.
- **User-Assigned Managed Identity**: existing entity; gains an associated federated credential
  and remains the identity a Key Vault token is issued for.
- **OIDC Issuer / Signing Keys**: the discovery + JWKS surface the emulator advertises and against
  which issued tokens are (at least nominally) consistent.
- **Cluster OIDC Issuer (k3s)**: the service-account-token issuer the cluster exposes and whose
  signing keys back the projected tokens; the federated credential trusts this issuer.
- **Kubernetes ServiceAccount**: per-service identity holder, annotated with the user-assigned
  identity's client-id; its `system:serviceaccount:<ns>:<name>` is the federated credential subject.
- **Key Vault Secret**: existing entity; now addressable and returned through the standard
  data-plane contract.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An **unmodified** Azure Key Vault client (SDK or the official Secrets Store CSI
  Azure provider) retrieves a seeded secret from miniblue using the canonical
  `https://<vault>.vault.azure.net/secrets/<name>` address — with **zero** client/provider code or
  configuration changes specific to miniblue's old URL shape.
- **SC-002**: A pod obtains a Key Vault secret using the **standard Workload Identity** credential
  chain (projected token → token exchange → KV call) with the IMDS DNAT rule **removed**.
- **SC-003**: The `cluster-wiring` IMDS DNAT, KV URL-rewrite proxy, and `*.vault.azure.net`
  certificate generation are **deleted** from the bring-up and the demo still reaches the secret
  end-to-end (verified by `verify.sh`).
- **SC-004**: A clean stack apply provisions the federated identity credential and the workload
  authenticates on **first** ArgoCD sync, with no manual identity/token seeding.
- **SC-005**: No regression — every Azure object and flow the demo uses today (RG, MI, ACR, AKS,
  ArgoCD delivery, secret seeding) continues to work against the modified emulator.

## Assumptions

- The demo continues to target the local single-node k3s cluster launched by miniblue's real AKS
  backend; multi-node and cloud AKS are out of scope.
- DNS routing of the standard Azure hosts (`<vault>.vault.azure.net` and the AAD authority host)
  to the miniblue endpoint, plus trust of miniblue's certificate authority inside the cluster,
  remains necessary and acceptable; this feature removes the **URL-rewriting** proxy and the
  **IMDS DNAT**, not necessarily all DNS/trust wiring.
- The Secrets Store CSI driver's requirement for a shared kubelet mount in k3s-in-docker is a
  node-level concern unrelated to Azure emulation and is **out of scope** for this feature.
- Token validation by the emulator is intentionally **lenient** (confirmed — see Clarifications
  2026-06-19): fidelity is required at the **protocol/shape** level (endpoints, grants, response
  envelopes, resolvable OIDC/JWKS), not cryptographic AAD validation, and the registered federated
  credential is not enforced at runtime. The Terraform/Terragrunt apply of the federated credential
  and the standard-mode Secrets Store CSI driver are the parts that must work correctly.
- The modified miniblue is built from source via the existing flow (`MINIBLUE_SRC_REPO` /
  `MINIBLUE_SRC_REF`) pointed at the **maintained fork** (FR-011).
- The pod-side Workload Identity flow relies on the **official `azure-workload-identity` webhook**
  add-on being installed in the cluster, plus a per-service annotated ServiceAccount (FR-013).
- The cluster's k3s **OIDC issuer** must be reachable/advertisable so the emulator can treat it as
  the federated credential issuer; enabling the service-account issuer on k3s is in scope for the
  Workload Identity flow.
- Backward compatibility of the legacy `/keyvault/<vault>/secrets/...` path is **not** required and
  may be dropped once standard host routing exists (seeding during apply will use the standard
  data-plane path).
