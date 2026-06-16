#!/usr/bin/env bash
# T023/T043 — Consolidated end-to-end verification (idempotent, re-runnable).
#   - ArgoCD pods Running + server reachable
#   - (US3) Application Synced + Healthy
#   - (US4) seeded Key Vault secret visible in the app pod
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require kubectl
export KUBECONFIG="${KUBECONFIG_FILE}"
[[ -s "${KUBECONFIG_FILE}" ]] || die "kubeconfig missing — run scripts/startup.sh"

APP_NAMESPACE="${APP_NAMESPACE:-service-a}"
APP_LABEL="${APP_LABEL:-app.kubernetes.io/name=service-a}"
SECRET_ENV_VAR="${SECRET_ENV_VAR:-APP_GREETING_SECRET}"

fail=0

# --- ArgoCD platform -------------------------------------------------------
log "checking ArgoCD pods"
if kubectl -n argocd get pods >/dev/null 2>&1; then
  not_ready=$(kubectl -n argocd get pods --no-headers 2>/dev/null | grep -cv 'Running\|Completed' || true)
  if [[ "${not_ready}" -eq 0 ]]; then ok "ArgoCD pods Running"; else warn "ArgoCD has ${not_ready} non-Running pod(s)"; fail=1; fi
else
  warn "ArgoCD namespace not found (run scripts/startup.sh)"; fail=1
fi

# --- ArgoCD Application sync/health (US3) ----------------------------------
if kubectl -n argocd get application service-a >/dev/null 2>&1; then
  sync=$(kubectl -n argocd get application service-a -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  health=$(kubectl -n argocd get application service-a -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  if [[ "${sync}" == "Synced" && "${health}" == "Healthy" ]]; then
    ok "Application Synced + Healthy"
  else
    warn "Application sync=${sync:-?} health=${health:-?}"; fail=1
  fi
else
  warn "Application service-a not found yet (US3 not applied)"
fi

# --- Runtime secret injection (US4) ----------------------------------------
pod=$(kubectl -n "${APP_NAMESPACE}" get pod -l "${APP_LABEL}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "${pod}" ]]; then
  val=$(kubectl -n "${APP_NAMESPACE}" exec "${pod}" -- printenv "${SECRET_ENV_VAR}" 2>/dev/null || true)
  if [[ -n "${val}" ]]; then ok "secret ${SECRET_ENV_VAR} present in pod (runtime-injected)"; else warn "secret ${SECRET_ENV_VAR} not visible in pod"; fail=1; fi
else
  warn "app pod not found in namespace ${APP_NAMESPACE} (US4/US3 not applied)"
fi

[[ "${fail}" -eq 0 ]] && { ok "verification passed"; exit 0; } || { warn "verification incomplete — see warnings above"; exit 1; }
