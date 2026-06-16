#!/usr/bin/env bash
# T047 — Tear everything down. `terragrunt destroy` removes the Azure objects AND the backing
# k3s container (miniblue cascades the real AKS backend on cluster/RG delete). Then remove the
# local registry + miniblue containers and the local kubeconfig.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

LIVE_DIR="${REPO_ROOT}/infrastructure/live-k8s/local"

# 1) Destroy the whole stack in reverse dependency order. run-all covers the platform
#    add-ons (secrets-csi, argocd), the cluster wiring, the kubeconfig, and the Azure
#    objects + real AKS (which tears down the k3s container) — all from one command.
if [[ -d "${LIVE_DIR}" ]]; then
  log "terragrunt run-all destroy over infrastructure/live-k8s/local (add-ons, wiring, AKS + k3s, RG/MI/ACR/KV)"
  (cd "${LIVE_DIR}" && terragrunt run-all destroy --terragrunt-non-interactive -- -lock-timeout=5m) || \
    warn "terragrunt destroy reported errors"

  # 1b) Purge the per-unit .terragrunt-cache directories. miniblue is ephemeral, so a stale
  #     cache (downloaded modules + generated backend/provider) can carry drift into the next
  #     startup; removing it forces a clean re-init on the following apply.
  log "removing .terragrunt-cache directories under infrastructure/live-k8s/local"
  find "${LIVE_DIR}" -type d -name '.terragrunt-cache' -prune -exec rm -rf {} + 2>/dev/null || \
    warn "could not remove some .terragrunt-cache directories"
fi

# 2) Remove the miniblue container and the network.
for c in "${MINIBLUE_CONTAINER}"; do
  if docker inspect "${c}" >/dev/null 2>&1; then
    log "removing container ${c}"
    docker rm -f "${c}" >/dev/null || true
  fi
done
docker network rm "${MINIBLUE_NETWORK}" >/dev/null 2>&1 || true
docker logout "${REGISTRY_HOST}" >/dev/null 2>&1 || true

# 3) Remove the local kubeconfig.
rm -f "${KUBECONFIG_FILE}" 2>/dev/null || true

# 4) Untrust miniblue's cert from the Windows CurrentUser\Root store (added by startup.sh).
#    No-op on non-Windows hosts. Matches by O=miniblue so it works across cert regenerations.
if command -v powershell.exe >/dev/null 2>&1; then
  log "removing trusted miniblue cert(s) from Windows CurrentUser\\Root store"
  MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -NonInteractive -Command "
    \$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root','CurrentUser')
    \$store.Open('ReadWrite')
    \$mb = \$store.Certificates | Where-Object { \$_.Subject -match 'O=miniblue' }
    if (\$mb) { \$mb | ForEach-Object { \$store.Remove(\$_); Write-Host ('[-] removed ' + \$_.Thumbprint) } }
    else { Write-Host '[=] no miniblue cert in store' }
    \$store.Close()
  " 2>/dev/null || warn "could not clean up the trust store (remove manually if needed)"
fi
rm -f "${MINIBLUE_CERT_FILE}" 2>/dev/null || true

ok "teardown complete"
