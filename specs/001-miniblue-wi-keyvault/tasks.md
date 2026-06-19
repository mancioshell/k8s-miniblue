# Tasks: miniblue Workload Identity + standard Key Vault data-plane API

**Input**: Design documents from `/specs/001-miniblue-wi-keyvault/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/)

**Tests**: The plan's Testing section explicitly calls for Go handler tests (repo `*_test.go` pattern)
plus `verify.sh` / `quickstart.md` validation, so a lean set of contract/handler test tasks is
included per story. They are not strict TDD gates.

## Components & path conventions

This feature spans **two repos** (see plan.md "Structure Decision"):

- **Component A — miniblue FORK (Go)**. Paths like `internal/...`, `cmd/...` are **relative to the
  fork repo root** (built into the custom `full` image via `MINIBLUE_SRC_REPO`/`MINIBLUE_SRC_REF`).
- **Component B — THIS repo** (`c:/git/k8s-miniblue`). Paths like `infrastructure/...`,
  `gitops/...`, `scripts/...` are relative to this repo root.

Tags: **[P]** = parallelizable (different files, no dependency). **[US1/US2/US3]** = owning story.
**[A]/[B]** = component.

---

## Phase 1: Setup (Shared)

**Purpose**: Establish the maintained fork and the build pin.

- [x] T001 [A] Create the maintained miniblue **fork** from upstream `v0.7.0`, push an initial
  branch/ref (e.g. `wi-keyvault`) to the fork remote.
- [x] T002 [B] Point the source-build pin at the fork: set `MINIBLUE_SRC_REPO` / `MINIBLUE_SRC_REF`
  (in `scripts/lib/common.sh` and/or `.env.example`) to the fork + ref; confirm the custom `full`
  image builds from it (`scripts/startup.sh` build path).
- [x] T003 [P] [B] Document the fork pin + build flow in `versions.md` / `README.md` (fork URL, ref,
  how to bump).

**Checkpoint**: Fork builds into the `full` image; pin is reproducible.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Cross-cutting emulator plumbing that BOTH US1 (KV host) and US2 (AAD authority host)
depend on. ⚠️ No story work starts until these are done.

- [x] T004 [A] Extend the TLS cert in `cmd/miniblue/main.go` (`generateAndSaveCert`): add SANs
  `*.vault.azure.net`, `vault.azure.net`, `login.microsoftonline.com`, `login.windows.net`,
  `sts.windows.net` (keep `localhost`); force regeneration when the cached cert lacks the new SANs
  (R2 / FR-004).
- [x] T005 [A] Add a **host-suffix routing middleware** in `internal/server/server.go` that
  inspects `Host` and dispatches canonical-host requests to the right handler (KV vs AAD). Provide
  the extension points; per-host route registration is done in US1/US2 (R1).
- [x] T006 [P] [B] Verify the in-cluster **CA trust** distribution still installs miniblue's CA
  (this remains after the shim is slimmed) — confirm the trust step in `cluster-wiring` is
  independent of the proxy/DNAT/cert-gen that will be removed.

**Checkpoint**: Canonical hosts terminate TLS on miniblue; host routing scaffold ready.

---

## Phase 3: User Story 1 — Key Vault standard data-plane API (P1) 🎯 MVP

**Goal**: Serve Key Vault on `https://<vault>.vault.azure.net/secrets/...` with standard shapes; drop
the KV URL-rewrite proxy. **Independent test**: unmodified SDK/`curl` GET on the canonical host
returns the secret envelope with the proxy off (quickstart §2).

### Tests (US1)

- [x] T007 [P] [US1] [A] Handler test `internal/services/keyvault/handler_host_test.go`: GET/PUT/
  DELETE/LIST on `Host: <vault>.vault.azure.net` → standard envelopes; List redacts `value`;
  missing secret → Azure 404 error envelope (contracts/keyvault-dataplane.md; FR-002/FR-003).

### Implementation (US1)

- [x] T008 [US1] [A] Register the canonical KV data-plane routes (`GET/PUT/DELETE /secrets/{name}`,
  `GET /secrets`) behind the host-suffix middleware, reusing the existing keyvault handler logic and
  `kv:<vault>:<name>` store keys (R1 / FR-001).
- [x] T009 [US1] [A] Accept + tolerate the `api-version` query param on the canonical routes (lenient,
  consistent with `APIVersionCheck`); resolves the api-version edge case (FR-002).
- [x] T010 [US1] [B] Remove the **KV URL-rewriting proxy** from `infrastructure/modules/cluster-wiring`
  (proxy deploy/config + `*.vault.azure.net` per-run cert-gen) (FR-009; SC-003).
- [x] T011 [US1] [B] Switch secret **seeding** during apply to the canonical data-plane host (drop the
  legacy `/keyvault/...` path usage; legacy path no longer required per Clarifications).

**Checkpoint**: KV reachable on the canonical host with no proxy; SC-001 demonstrable.

---

## Phase 4: User Story 2 — Workload Identity pod auth (P1)

**Goal**: Pod authenticates via the standard WI chain (projected token → federated token exchange →
KV call) with **no IMDS**. Per Clarification B, token issuance is **lenient** (not gated on a
registered FIC), so US2 does not depend on US3 at runtime. **Independent test**: WI-configured pod
reads a secret with the IMDS DNAT absent and zero IMDS calls in miniblue logs (quickstart §4).

### Tests (US2)

- [x] T012 [P] [US2] [A] Handler test `internal/services/auth/handler_wi_test.go`: federated grant
  (`grant_type=client_credentials` + `client_assertion_type=…jwt-bearer` + `client_assertion`)
  returns a Bearer token; `/{tenant}/discovery/v2.0/keys` resolves; the token header `kid` matches a
  JWKS key (contracts/oauth2-token-and-oidc.md; FR-006/FR-007).

### Implementation — emulator (US2 / Component A)

- [x] T013 [US2] [A] In `internal/services/auth/handler.go` add the **JWKS endpoint**
  `/{tenantId}/discovery/v2.0/keys` returning the public RSA key as a JWK set (closes the existing
  404 advertised by OIDC discovery) (FR-007).
- [x] T014 [US2] [A] Generate a stable RSA signing key at startup and **sign issued tokens RS256**
  (replace `alg:none`), publishing the key via the JWKS (T013); keep claims `aud/iss/tid/oid/sub/
  appid/iat/nbf/exp` (FR-007).
- [x] T015 [US2] [A] Ensure the token endpoint accepts the federated `client_assertion` grant
  **leniently** — issue a KV-scoped token for any well-formed request, no FIC enforcement
  (Clarification B / FR-006); optionally decode the assertion to echo `sub`/`appid`.

### Implementation — cluster wiring (US2 / Component B)

- [x] T016 [P] [US2] [B] Enable the k3s **service-account issuer** (kube-apiserver args
  `service-account-issuer` + `service-account-jwks-uri`) so projected tokens carry a stable issuer
  (R5); record the issuer value for the FIC subject/issuer use in US3.
- [x] T017 [US2] [B] New module `infrastructure/modules/workload-identity`: install the official
  **`azure-workload-identity` mutating webhook** (Helm `helm_release`), configured with tenant +
  `AZURE_AUTHORITY_HOST` pointing at miniblue (FR-013 / R5).
- [x] T018 [P] [US2] [B] Add an annotated **ServiceAccount** template
  `gitops/local/shared-charts/service-chart-template/templates/serviceaccount.yaml`
  (`azure.workload.identity/client-id` + `tenant-id`) and the pod label
  `azure.workload.identity/use: "true"`; point the Deployment at the SA (FR-013 / R6).
- [x] T019 [US2] [B] Switch `templates/secretproviderclass.yaml` from `useVMManagedIdentity:"true"`
  to **workload-identity mode** (`useVMManagedIdentity:"false"`, `usePodIdentity:"false"`,
  `clientID:<UAMI clientId>`); update `values.yaml` + per-service values accordingly (R6).
- [x] T020 [US2] [B] Remove the **IMDS DNAT** from `infrastructure/modules/cluster-wiring`
  (FR-008/FR-009; SC-002/SC-003).

**Checkpoint**: Pod gets a KV secret via WI; IMDS path gone; SC-002 demonstrable.

---

## Phase 5: User Story 3 — Federated credential as infrastructure (P2)

**Goal**: Declare the UAMI + federated credential as Terraform/Terragrunt and have them apply
cleanly against the emulator (the part the user emphasized). Runtime is already lenient (B), so this
story's value is **clean, idempotent apply**. **Independent test**: stack apply creates the FIC,
GET on the ARM path returns it, re-apply is a no-op (quickstart §3).

### Tests (US3)

- [x] T021 [P] [US3] [A] Handler test `internal/services/managedidentity/handler_test.go`: UAMI
  PUT/GET/DELETE returns `clientId/principalId/tenantId` (deterministic clientId); FIC
  PUT/GET/LIST/DELETE stores `issuer/subject/audiences`; FIC under a missing UAMI → 404
  (contracts/managedidentity-arm.md; FR-005).

### Implementation — emulator (US3 / Component A)

- [x] T022 [US3] [A] New package `internal/services/managedidentity/handler.go`: implement
  `Microsoft.ManagedIdentity/userAssignedIdentities/{name}` (PUT/GET/DELETE) with deterministic
  `clientId`/`principalId` per `{sub}/{rg}/{name}`, store key `uaid:<sub>:<rg>:<name>` (data-model).
- [x] T023 [US3] [A] In the same package, implement the nested
  `.../federatedIdentityCredentials/{fic}` (PUT/GET/DELETE/LIST) with
  `issuer/subject/audiences`, store key `fic:<sub>:<rg>:<name>:<fic>`; require the parent UAMI
  (FR-005 / contracts).
- [x] T024 [US3] [A] Register the `managedidentity` handler in `internal/server/server.go`
  (follow the existing per-service `Register` pattern; respect the `SERVICES` filter).

### Implementation — IaC (US3 / Component B)

- [x] T025 [US3] [B] Promote `infrastructure/modules/managed-identity` from stub → real
  `azurerm_user_assigned_identity` (keep deterministic ids as outputs so chart wiring is stable);
  remove the "EMULATOR STUB" 404 rationale (FR-010 — no regression of consumers).
- [x] T026 [US3] [B] Add `azurerm_federated_identity_credential` (per service) with `issuer` = the
  k3s issuer (T016), `subject` = `system:serviceaccount:<ns>:<sa>` (matching T018),
  `audience` = `api://AzureADTokenExchange`; expose as a new `infrastructure/live-k8s/local/<unit>`
  and wire its dependency graph (FR-005 / US3).
- [ ] T027 [US3] [B] Confirm **idempotency**: a second `terragrunt apply` shows no spurious diffs on
  the UAMI/FIC (SC-004 AS2).

**Checkpoint**: Federated credential exists as applied IaC; SC-004 demonstrable.

---

## Phase 6: Polish & Cross-Cutting

**Purpose**: Finish the shim teardown, scripts, docs, and full validation.

- [x] T028 [B] Slim `infrastructure/modules/cluster-wiring` to **DNS overrides + CA trust only**
  (CoreDNS `*.vault.azure.net` + AAD authority host → miniblue); confirm DNAT/proxy/cert-gen are
  fully gone and the shared-mount fix (out of scope) is untouched (FR-009 / Assumptions).
- [x] T029 [P] [B] Update `scripts/startup.sh` and `scripts/teardown.sh`: drop the removed shim
  steps; add the webhook install + k3s issuer enablement; keep DNS/CA-trust + `.terragrunt-cache`
  purge.
- [x] T030 [P] [B] Update `README.md` / `.env.example` / `versions.md`: WI flow, webhook add-on,
  fork pin, canonical-host KV, removed shim components.
- [ ] T031 [B] Run `quickstart.md` end-to-end + `scripts/verify.sh`: both services healthy via WI,
  KV on canonical host, no IMDS/proxy (SC-003/SC-005).
- [ ] T032 [P] [B] Regression pass — confirm RG / MI / ACR / AKS / ArgoCD delivery / secret seeding
  still work against the modified emulator (SC-005 / FR-010).

---

## Dependencies & Execution Order

### Phase order

1. **Setup (P1)** → 2. **Foundational (P2)** blocks everything → 3. **US1**, 4. **US2**,
5. **US3** → 6. **Polish**.

### Story dependencies

- **US1 (P1)** and **US2 (P1)**: both start after Foundational; independent of each other (US1 = KV
  host; US2 = token/identity). US2's *end-to-end* secret read consumes the US1 KV contract, but the
  token-exchange half is independently testable.
- **US3 (P2)**: independent of US2 at **runtime** (Clarification B — FIC not enforced). Its `subject`
  must match the SA from T018 and its `issuer` the value from T016, so schedule T026 after those, but
  the emulator ARM work (T022–T024) has no cross-story dependency.
- **Polish (T028)** depends on T010 + T020 (both shim removals) being done.

### Within a story

- Handler tests → implementation; emulator routes before the IaC/chart that exercises them.
- `server.go` is touched by T005 (foundational) and T024 (US3) — **not** parallel with each other.
- `cluster-wiring` is touched by T010, T020, T028 — sequence them (same module).

### Parallel opportunities

- Setup: T003 ∥ (T001→T002).
- Foundational: T006 ∥ (T004, T005).
- US2 emulator (T013/T014/T015 same file → sequential) ∥ US2 wiring (T016 ∥ T018).
- US3 emulator (T021→T022→T023→T024) ∥ US3 IaC drafting (T025), converging at T026.
- Polish: T029 ∥ T030 ∥ T032 (different files); T031 last.

---

## MVP & incremental delivery

- **MVP = Foundational + US1**: standard KV data-plane on the canonical host, proxy removed (SC-001).
- **+ US2**: real Workload Identity pod auth, IMDS removed (SC-002) — the headline of the request.
- **+ US3**: federated credential as clean, idempotent IaC (SC-004) — the Terraform half the user
  emphasized.
- **+ Polish**: shim fully deleted, scripts/docs updated, full `verify.sh`/regression green
  (SC-003/SC-005).
