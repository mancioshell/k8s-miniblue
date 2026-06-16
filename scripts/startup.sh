#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# startup.sh — bring up the WHOLE local stack in one command (merge of the former
# up-platform.sh + up-infra.sh). Two phases run in order:
#
#   1) PLATFORM substrate — miniblue with its REAL AKS backend (AKS_BACKEND=k3s).
#      Image/chart bytes live in GitHub Container Registry (ghcr.io); k3s pulls them
#      directly, so there is no local OCI registry to start.
#
#   2) INFRA stack — a single `terragrunt run-all` over infrastructure/live-k8s/local whose
#      dependency graph drives the ordering end-to-end:
#
#        resource-group ─┬─ managed-identity ─┐
#                        ├─ container-registry │
#                        └─ key-vault          │
#                                     aks ◄─────┘   (real k3s via miniblue AKS backend)
#                                      └─ kubeconfig          (host-reachable kubeconfig, TF output)
#                                            └─ cluster-wiring (ghcr-pull imagePullSecret + KV/IMDS shim)
#                                                  ├─ argocd       (ArgoCD + CRDs + optional root app)
#                                                  └─ secrets-csi  (Secrets Store CSI + Azure provider)
#
# Everything that used to be shell glue (get-credentials, pull-secret, kv-proxy) now
# lives in Terraform modules wired by terragrunt dependencies, so a single apply
# creates the cluster, derives its kubeconfig, wires cross-service reachability, and
# installs the platform add-ons — in order. The ONLY non-Terraform step is trusting
# miniblue's self-signed cert so terraform.exe (native Windows) can verify the HTTPS
# ARM metadata host.
#
# Env: AUTO_APPROVE (default true) gates the apply.
# GitOps: enabled in this apply when GITOPS_REPO_URL is set (typically via .env);
#         leave it empty to install ArgoCD only (root app OFF).
# Idempotent / re-runnable end to end.
# -----------------------------------------------------------------------------
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require docker
require terragrunt
require terraform
require kubectl

# Load local secrets/overrides (e.g. GHCR_USERNAME/GHCR_TOKEN for the private-image
# pull secret created by the cluster-wiring unit, and GITOPS_REPO_URL to wire GitOps)
# from a gitignored .env. Without this the imagePullSecret step is silently skipped.
if [[ -f "${REPO_ROOT}/.env" ]]; then
  log "loading ${REPO_ROOT}/.env"
  set -a; source "${REPO_ROOT}/.env"; set +a
fi

export AUTO_APPROVE="${AUTO_APPROVE:-true}"

# -----------------------------------------------------------------------------
# Phase 1 — miniblue with the REAL AKS backend.
#
# The real AKS backend is enabled by AKS_BACKEND=k3s, but miniblue shells out to the `docker`
# CLI to launch the rancher/k3s container — and EVERY published image (latest, 0.7.0, sha-*) is
# FROM scratch with no docker CLI, so it silently falls back to the ARM-only stub backend. The
# `full` variant (docker build --target=full) bundles the docker CLI and is NOT published on any
# registry, so we BUILD it locally from the pinned source. miniblue then warm-pulls rancher/k3s
# and launches a real k3s container per AKS cluster create.
# -----------------------------------------------------------------------------
start_miniblue() {
  if docker inspect "${MINIBLUE_CONTAINER}" >/dev/null 2>&1; then
    local state
    state="$(docker inspect -f '{{.State.Status}}' "${MINIBLUE_CONTAINER}")"
    if [[ "${state}" == "running" ]]; then
      ok "miniblue already running (${MINIBLUE_CONTAINER})"
      return 0
    fi
    log "removing stale miniblue container (${state})"
    docker rm -f "${MINIBLUE_CONTAINER}" >/dev/null
  fi

  # Build the `full` image locally if absent (not available on any registry).
  if ! docker image inspect "${MINIBLUE_IMAGE}" >/dev/null 2>&1; then
    local src_dir="${REPO_ROOT}/tmp/miniblue-src"
    if [[ ! -d "${src_dir}/.git" ]]; then
      require git   # only needed to clone the miniblue source when the image is absent
      log "cloning miniblue source (${MINIBLUE_SRC_REF}) → ${src_dir}"
      rm -rf "${src_dir}"
      git clone --depth 1 --branch "${MINIBLUE_SRC_REF}" "${MINIBLUE_SRC_REPO}" "${src_dir}"
    fi
    log "building ${MINIBLUE_IMAGE} (docker build --target=full)"
    docker build --target=full -t "${MINIBLUE_IMAGE}" "${src_dir}"
  else
    log "using existing local image ${MINIBLUE_IMAGE}"
  fi

  log "starting miniblue with real AKS backend (AKS_BACKEND=${AKS_BACKEND})"
  # MSYS_NO_PATHCONV stops Git-Bash on Windows from mangling the unix socket path; the doubled
  # leading slash keeps the source as a literal unix path inside the Docker (WSL2) VM.
  MSYS_NO_PATHCONV=1 docker run -d \
    --name "${MINIBLUE_CONTAINER}" \
    --network "${MINIBLUE_NETWORK}" \
    -p "${MINIBLUE_DATA_PORT}:4566" \
    -p "${MINIBLUE_ARM_PORT}:4567" \
    -e "AKS_BACKEND=${AKS_BACKEND}" \
    -v "//var/run/docker.sock:/var/run/docker.sock" \
    "${MINIBLUE_IMAGE}" >/dev/null

  log "waiting for miniblue ARM metadata host on ${ARM_METADATA_HOSTNAME}"
  for _ in $(seq 1 30); do
    if curl -fsSk "https://${ARM_METADATA_HOSTNAME}/metadata/endpoints?api-version=2022-09-01" >/dev/null 2>&1 \
       || curl -fsS "http://${MINIBLUE_HOST}:${MINIBLUE_DATA_PORT}/health" >/dev/null 2>&1; then
      # Copy out the self-signed cert so terraform/azurerm can trust the HTTPS metadata host.
      if docker cp "${MINIBLUE_CONTAINER}:/home/nonroot/.miniblue/cert.pem" "${MINIBLUE_CERT_FILE}" >/dev/null 2>&1; then
        ok "miniblue cert copied → ${MINIBLUE_CERT_FILE}"
      else
        warn "could not copy miniblue cert (TLS trust may fail) — check container path"
      fi
      ok "miniblue is up (data:${MINIBLUE_DATA_PORT} arm:${MINIBLUE_ARM_PORT})"
      return 0
    fi
    sleep 2
  done

  die "miniblue did not become ready in time — check: docker logs ${MINIBLUE_CONTAINER}"
}

# -----------------------------------------------------------------------------
# GitOps wiring — part of the single stack apply (no separate step).
# When GITOPS_REPO_URL is set (typically via .env), the argocd unit creates the root
# App-of-Apps now, so the same `run-all apply` that builds the cluster also points
# ArgoCD at the repo + shared OCI chart. ArgoCD's automated sync then reconciles
# continuously — publishing a new chart/values version is what rolls out app changes.
# Leave GITOPS_REPO_URL empty to install ArgoCD only (root app stays OFF).
# Creds flow to the argocd unit as TF_VAR_* env vars; run-all threads them through.
# -----------------------------------------------------------------------------
wire_gitops_env() {
  GITOPS_REPO_URL="${GITOPS_REPO_URL:-}"
  if [[ -n "${GITOPS_REPO_URL}" ]]; then
    export ENABLE_ROOT_APP="true"
    export GITOPS_REPO_URL
    export GITOPS_REPO_REVISION="${GITOPS_REPO_REVISION:-main}"

    # Private GitOps repo auth (empty token = public repo, no auth).
    export TF_VAR_gitops_repo_token="${GITOPS_REPO_TOKEN:-}"
    export TF_VAR_gitops_repo_username="${GITOPS_REPO_USERNAME:-git}"

    # Private OCI Helm repo (ghcr.io) hosting the shared chart for the multi-source apps.
    # Reuse the GHCR credentials from common.sh/.env; empty token = public chart (no auth).
    export OCI_CHART_REPO_URL="${OCI_CHART_REPO_URL:-${REGISTRY_HOST}/${GHCR_OWNER}/charts}"
    export TF_VAR_oci_registry_username="${GHCR_USERNAME:-${GHCR_OWNER}}"
    export TF_VAR_oci_registry_token="${GHCR_TOKEN:-}"

    log "GitOps ON -> ${GITOPS_REPO_URL} (revision ${GITOPS_REPO_REVISION})"
  else
    log "GitOps OFF (set GITOPS_REPO_URL — e.g. in .env — to enable the root app)"
  fi
}

# -----------------------------------------------------------------------------
# Trust miniblue's self-signed cert so the azurerm provider can reach the HTTPS ARM
# metadata host. On Windows, terraform.exe is a NATIVE binary that uses the Windows
# certificate store and IGNORES SSL_CERT_FILE — and azurerm offers no way to skip TLS
# verification — so the cert must be imported into the user trust store
# (CurrentUser\Root, no admin needed). Idempotent; teardown.sh removes it.
# No-op on Linux/macOS, where SSL_CERT_FILE (set in lib/common.sh) is honoured.
# -----------------------------------------------------------------------------
trust_miniblue_cert() {
  command -v powershell.exe >/dev/null 2>&1 || { log "non-Windows host — relying on SSL_CERT_FILE, skipping trust-store import"; return 0; }
  [[ -f "${MINIBLUE_CERT_FILE}" ]] || die "miniblue cert not found: ${MINIBLUE_CERT_FILE} — phase 1 (miniblue) must run first"

  local win_cert
  win_cert="$(cygpath -w "${MINIBLUE_CERT_FILE}")"
  log "trusting miniblue cert in Windows CurrentUser\\Root store (idempotent)"

  MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -NonInteractive -Command "
    \$ErrorActionPreference = 'Stop'
    \$cert  = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2('${win_cert}')
    \$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root','CurrentUser')
    \$store.Open('ReadWrite')
    if (\$store.Certificates | Where-Object { \$_.Thumbprint -eq \$cert.Thumbprint }) {
      Write-Host ('[=] already trusted: ' + \$cert.Thumbprint)
    } else {
      \$store.Add(\$cert)
      Write-Host ('[+] added to CurrentUser\\Root: ' + \$cert.Thumbprint)
    }
    \$store.Close()
  " || die "failed to import miniblue cert into the Windows trust store"

  ok "miniblue cert trusted (terraform.exe can now verify https://${ARM_METADATA_HOSTNAME})"
}

# -----------------------------------------------------------------------------
# Apply the entire dependency graph. `run-all` plans then applies every unit under
# infrastructure/live-k8s/local in topological order, threading real outputs between them (the
# kubeconfig unit's path flows into cluster-wiring, argocd and secrets-csi).
# -----------------------------------------------------------------------------
apply_stack() {
  cd "${REPO_ROOT}/infrastructure/live-k8s/local"

  log "validating all units"
  terragrunt run-all validate

  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    log "applying the whole stack (AUTO_APPROVE=true)"
    terragrunt run-all apply --terragrunt-non-interactive -- -lock-timeout=5m
  else
    warn "AUTO_APPROVE=false — terragrunt will prompt per unit."
    terragrunt run-all apply -- -lock-timeout=5m
  fi

  cd "${REPO_ROOT}"
}

log "=== startup: platform + infra (AUTO_APPROVE=${AUTO_APPROVE}) ==="
ensure_network
start_miniblue           # phase 1: miniblue (real AKS/k3s)
wire_gitops_env          # export GitOps TF_VAR_* env when GITOPS_REPO_URL is set
trust_miniblue_cert      # so terraform.exe can verify the miniblue HTTPS metadata host
apply_stack              # phase 2: the whole terragrunt stack

ok "stack up — kubeconfig: ${KUBECONFIG_FILE}"
log "use it:        export KUBECONFIG=\"${KUBECONFIG_FILE}\""
log "publish app:   run the build-publish.yml / publish-chart.yml GitHub Actions"
if [[ -n "${GITOPS_REPO_URL}" ]]; then
  log "GitOps:        ON -> ${GITOPS_REPO_URL} (${GITOPS_REPO_REVISION}) — ArgoCD reconciles automatically"
  log "watch sync:    KUBECONFIG=\"${KUBECONFIG_FILE}\" kubectl -n argocd get applications"
else
  log "GitOps:        OFF — set GITOPS_REPO_URL (e.g. in .env) and re-run to enable"
fi
