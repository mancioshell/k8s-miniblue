#!/usr/bin/env bash
# Shared environment + helpers for the runbook scripts.
# Source this from every script: `source "$(dirname "$0")/lib/common.sh"`
set -euo pipefail

# ---------------------------------------------------------------------------
# Repo layout
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # scripts/
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export SCRIPT_DIR REPO_ROOT

# ---------------------------------------------------------------------------
# Pinned images (keep in sync with versions.md)
# ---------------------------------------------------------------------------
# The real AKS backend needs the `full` image variant, which is NOT published on any
# registry: every published tag (latest, 0.7.0, sha-*) is FROM scratch with NO docker CLI,
# so miniblue can't shell out to launch k3s and falls back to the ARM-only stub backend.
# We build `miniblue:full` locally from the pinned source (target=full adds the docker CLI).
export MINIBLUE_IMAGE="${MINIBLUE_IMAGE:-miniblue:full}"
export MINIBLUE_SRC_REPO="${MINIBLUE_SRC_REPO:-https://github.com/moabukar/miniblue.git}"
export MINIBLUE_SRC_REF="${MINIBLUE_SRC_REF:-v0.7.0}"
export MINIBLUE_CONTAINER="${MINIBLUE_CONTAINER:-miniblue}"

# ---------------------------------------------------------------------------
# miniblue endpoints
#   - data plane:        4566
#   - ARM metadata host: 4567 (azurerm provider talks to this)
# ---------------------------------------------------------------------------
export MINIBLUE_DATA_PORT="${MINIBLUE_DATA_PORT:-4566}"
export MINIBLUE_ARM_PORT="${MINIBLUE_ARM_PORT:-4567}"
export MINIBLUE_HOST="${MINIBLUE_HOST:-localhost}"
export ARM_METADATA_HOSTNAME="${ARM_METADATA_HOSTNAME:-${MINIBLUE_HOST}:${MINIBLUE_ARM_PORT}}"

# Real AKS backend: miniblue launches a real rancher/k3s container per cluster.
export AKS_BACKEND="${AKS_BACKEND:-k3s}"

# ---------------------------------------------------------------------------
# Fake ARM credentials (miniblue requires NO real auth; values are placeholders)
# ---------------------------------------------------------------------------
export ARM_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID:-00000000-0000-0000-0000-000000000000}"
export ARM_TENANT_ID="${ARM_TENANT_ID:-11111111-1111-1111-1111-111111111111}"
export ARM_CLIENT_ID="${ARM_CLIENT_ID:-22222222-2222-2222-2222-222222222222}"
export ARM_CLIENT_SECRET="${ARM_CLIENT_SECRET:-miniblue-fake-secret}"
export ARM_SKIP_PROVIDER_REGISTRATION="${ARM_SKIP_PROVIDER_REGISTRATION:-true}"

# ---------------------------------------------------------------------------
# Image & chart registry — GitHub Container Registry (ghcr.io).
# Replaces the former local OCI registry: image AND chart bytes live remotely and
# ArgoCD / k3s pull them directly. PRIVATE packages need pull auth, provided to the
# cluster as a dockerconfigjson imagePullSecret created by the cluster-wiring module
# (from GHCR_USERNAME/GHCR_TOKEN) and to ArgoCD as a private OCI Helm repo credential.
# ---------------------------------------------------------------------------
export REGISTRY_HOST="${REGISTRY_HOST:-ghcr.io}"
export GHCR_OWNER="${GHCR_OWNER:-mancioshell}"
# Namespace prefix for all images, e.g. ghcr.io/mancioshell (image = <prefix>/<service>).
export IMAGE_REGISTRY="${IMAGE_REGISTRY:-${REGISTRY_HOST}/${GHCR_OWNER}}"
# OCI repo the SHARED Helm chart is pushed to, e.g. oci://ghcr.io/mancioshell/charts.
export CHART_OCI_REPO="${CHART_OCI_REPO:-oci://${REGISTRY_HOST}/${GHCR_OWNER}/charts}"
# Single generic chart reused by every springboot service (under gitops/local/shared-charts/).
export SHARED_CHART_NAME="${SHARED_CHART_NAME:-service-chart-template}"
# Auth for `docker login` / `helm push` and private k3s pull. Token = GitHub PAT with
# read:packages (pull) + write:packages (push). Provide via the gitignored .env.
export GHCR_USERNAME="${GHCR_USERNAME:-${GHCR_OWNER}}"
export GHCR_TOKEN="${GHCR_TOKEN:-}"

# Shared docker network so miniblue's k3s container shares the host's egress path.
export MINIBLUE_NETWORK="${MINIBLUE_NETWORK:-miniblue-net}"

# miniblue self-signed cert (copied out of the container by 00-up-miniblue.sh). azurerm/terraform
# reach the HTTPS metadata host over TLS, so it must be trusted via SSL_CERT_FILE.
export MINIBLUE_CERT_FILE="${MINIBLUE_CERT_FILE:-${REPO_ROOT}/.miniblue-cert.pem}"
if [[ -f "${MINIBLUE_CERT_FILE}" ]]; then
  # terraform.exe is a native Windows (Go) binary and cannot open MSYS-style /c/... paths;
  # hand it a Windows path (C:/...) when running under Git-Bash/MSYS.
  if command -v cygpath >/dev/null 2>&1; then
    export SSL_CERT_FILE="$(cygpath -m "${MINIBLUE_CERT_FILE}")"
  else
    export SSL_CERT_FILE="${MINIBLUE_CERT_FILE}"
  fi
fi

# Kubeconfig fetched via listClusterAdminCredential (15-get-credentials.sh).
export KUBECONFIG_FILE="${KUBECONFIG_FILE:-${REPO_ROOT}/kubeconfig}"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"
}

ensure_network() {
  if ! docker network inspect "${MINIBLUE_NETWORK}" >/dev/null 2>&1; then
    log "creating docker network ${MINIBLUE_NETWORK}"
    docker network create "${MINIBLUE_NETWORK}" >/dev/null
  fi
}
