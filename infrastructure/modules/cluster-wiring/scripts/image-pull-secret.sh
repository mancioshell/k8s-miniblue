#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# image-pull-secret.sh — pre-create each app namespace and a dockerconfigjson
# imagePullSecret in it so the k3s node can pull PRIVATE images from a remote
# registry (ghcr.io). No node-level registries.yaml rewrite and no k3s restart:
# the registry is remote with normal DNS + valid TLS, so a standard Kubernetes
# imagePullSecret is all that is needed.
#
# ArgoCD (CreateNamespace=true) adopts the pre-created namespaces idempotently;
# it never prunes this secret because it does not track it.
#
# Invoked by the `cluster-wiring` Terraform module (null_resource local-exec).
# Env: KUBECONFIG, REGISTRY_HOST, GHCR_USERNAME, GHCR_TOKEN, PULL_SECRET_NAME,
#      APP_NAMESPACES (space-separated).
# -----------------------------------------------------------------------------
set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG is required}"
registry="${REGISTRY_HOST:-ghcr.io}"
username="${GHCR_USERNAME:-}"
token="${GHCR_TOKEN:-}"
secret_name="${PULL_SECRET_NAME:-ghcr-pull}"
namespaces="${APP_NAMESPACES:-}"

if [[ -z "${token}" ]]; then
  echo "GHCR_TOKEN empty — assuming PUBLIC packages; skipping imagePullSecret creation" >&2
  exit 0
fi

if [[ -z "${namespaces}" ]]; then
  echo "APP_NAMESPACES empty — nothing to seed" >&2
  exit 0
fi

for ns in ${namespaces}; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f - >&2
  kubectl -n "${ns}" create secret docker-registry "${secret_name}" \
    --docker-server="${registry}" \
    --docker-username="${username}" \
    --docker-password="${token}" \
    --dry-run=client -o yaml | kubectl apply -f - >&2
  echo "ensured imagePullSecret '${secret_name}' (${registry}) in namespace '${ns}'" >&2
done
