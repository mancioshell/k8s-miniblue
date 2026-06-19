# Implementation Plan: miniblue Workload Identity + standard Key Vault data-plane API

**Branch**: `001-miniblue-wi-keyvault` | **Date**: 2026-06-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-miniblue-wi-keyvault/spec.md`

## Summary

Make the miniblue emulator faithful to two real Azure contracts so the demo can drop its custom
interception shim: (1) serve the **Key Vault data-plane API on the canonical host**
`<vault>.vault.azure.net` (not the bespoke `/keyvault/<vault>/...` path), and (2) support
**Azure AD Workload Identity** — register federated identity credentials on a user-assigned
identity and honor the federated (`client_assertion`) token exchange — so a pod authenticates the
exact way it would on real AKS (annotated ServiceAccount + the official
`azure-workload-identity` webhook). The modified emulator ships from a **maintained fork** built
into the custom `full` image. With these in place the `cluster-wiring` IMDS DNAT, the KV
URL-rewriting proxy, and the per-run `*.vault.azure.net` certificate generation are **removed**.

## Technical Context

**Language/Version**: Go 1.26 (miniblue fork); HCL (Terraform `>= 1.10.3` / Terragrunt); Helm 3 /
Kubernetes YAML; bash (orchestration scripts).

**Primary Dependencies**: miniblue fork — `go-chi/chi v5.2.5`, std-lib `crypto/rsa` + `crypto/x509`
(RS256 token signing + JWKS and TLS SANs — no new module dependency). Repo — `hashicorp/azurerm`
provider, k3s (miniblue real AKS backend), Secrets Store CSI driver + Azure provider, the new
**`azure-workload-identity` webhook** add-on, ArgoCD.

**Storage**: miniblue in-memory `store.Store` for the new user-assigned-identity and
federated-credential ARM objects; Terraform local state for the IaC bindings.

**Testing**: Go unit/handler tests in the fork (existing `*_test.go` pattern, e.g.
`internal/services/aks/handler_test.go`); end-to-end via `scripts/verify.sh`; manual contract
checks with `curl`/Azure SDK against the canonical hosts.

**Target Platform**: Local single-node k3s launched by miniblue's real AKS backend on Docker
(Windows/Git-Bash or Linux/macOS host).

**Project Type**: Two coordinated components — an upstream Go service **fork** (the emulator) and
this infrastructure/GitOps repository that consumes it.

**Performance Goals**: Not performance-sensitive (local dev emulator); correctness/fidelity of the
Azure contracts is the goal, not throughput.

**Constraints**: Token validation may be **lenient** (local emulator) — fidelity is required at the
protocol/shape level (endpoints, grants, response envelopes, OIDC discovery/JWKS resolvability),
not full cryptographic AAD validation. DNS routing of canonical hosts to miniblue + CA trust inside
the cluster remain acceptable; only the **URL-rewriting proxy** and the **IMDS DNAT** are removed.

**Scale/Scope**: Two services (`service-a`, `service-b`), one local environment, one vault, one
user-assigned identity with per-service federated credentials.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is still the unfilled template — there
are no ratified principles to gate against. The repository's documented conventions are applied as
the working bar instead:

- **Pinned-artifact boundary** ("consume miniblue as released, pinned artifacts; never commit its
  upstream source"): **Preserved** — the fork is consumed via the existing
  `MINIBLUE_SRC_REPO` / `MINIBLUE_SRC_REF` source-build at startup; its source is not committed into
  this repo (`tmp/` stays gitignored). The only change is repointing the pin to the fork.
- **Standards-only simplification**: this feature *reduces* net complexity (removes the DNAT +
  proxy + cert shim) — aligned with the "start simple / use standard mechanisms" intent.
- **Security**: no secrets committed; WI replaces a faked IMDS path with the real token-exchange
  pattern (a security-fidelity improvement). New TLS SANs are self-signed CA material generated at
  runtime, not committed.

**Verdict: PASS** (no violations; Complexity Tracking left empty).

## Project Structure

### Documentation (this feature)

```text
specs/001-miniblue-wi-keyvault/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (external Azure contracts miniblue must match)
│   ├── keyvault-dataplane.md
│   ├── oauth2-token-and-oidc.md
│   └── managedidentity-arm.md
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (the two components)

```text
# Component A — miniblue FORK (Go) — built into the custom `full` image
internal/services/keyvault/        # add host-based (<vault>.vault.azure.net) routing adapter
internal/services/auth/            # add JWKS endpoint; RS256-sign issued tokens; accept client_assertion grant
internal/services/managedidentity/ # NEW: Microsoft.ManagedIdentity ARM control plane
                                   #   userAssignedIdentities/{name} (PUT/GET/DELETE)
                                   #   …/federatedIdentityCredentials/{fic} (PUT/GET/DELETE/LIST)
internal/server/server.go          # register managedidentity; install host-routing middleware
cmd/miniblue/main.go               # extend cert SANs (*.vault.azure.net, AAD authority hosts)

# Component B — THIS repo (HCL / Helm / scripts)
infrastructure/modules/managed-identity/      # promote stub → real UAMI (azurerm) + federated credential support
infrastructure/modules/workload-identity/     # NEW: install azure-workload-identity webhook + k3s issuer enablement
infrastructure/modules/cluster-wiring/        # SLIM DOWN: drop IMDS DNAT + KV proxy + cert-gen; keep DNS/CA-trust (+ CSI shared-mount)
infrastructure/live-k8s/local/<units>/        # new federated-credential / workload-identity units; rewire deps
gitops/local/shared-charts/service-chart-template/
    templates/serviceaccount.yaml             # NEW: annotated SA (azure.workload.identity/client-id) + pod label
    templates/secretproviderclass.yaml        # switch useVMManagedIdentity → workload-identity mode
scripts/startup.sh, scripts/teardown.sh       # remove shim steps; add webhook/issuer wiring
.env.example, README.md, versions.md          # config + docs for the fork pin and webhook
```

**Structure Decision**: Two coordinated components. **Component A** is the maintained miniblue
**fork** (Go) where the protocol fidelity is implemented (KV host routing, WI token exchange +
OIDC/JWKS, ManagedIdentity ARM control plane, TLS SANs); it is consumed as a pinned source-built
image, not vendored into this repo. **Component B** is this repository's Terraform/Terragrunt
modules, Helm chart, and scripts that provision the federated bindings, install the official
webhook, switch the workloads to Workload Identity, and delete the interception shim.

## Complexity Tracking

> No Constitution Check violations — section intentionally empty.
