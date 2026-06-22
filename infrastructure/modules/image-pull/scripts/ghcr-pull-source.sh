#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# ghcr-pull-source.sh — create ONE annotated dockerconfigjson source secret that
# the emberstack Reflector controller auto-copies into EVERY namespace, so any
# pod can pull private images from a remote registry (ghcr.io) without a
# per-namespace imagePullSecret being pre-seeded by Terraform.
#
# The reflector annotations enable automatic reflection to all namespaces
# (current and future). Pods reference the reflected copy by name
# (imagePullSecrets: [<PULL_SECRET_NAME>]).
#
# Invoked by the `image-pull` Terraform module (null_resource local-exec).
# Env: KUBECONFIG, REGISTRY_HOST, GHCR_USERNAME, GHCR_TOKEN, PULL_SECRET_NAME,
#      SOURCE_NAMESPACE.
# -----------------------------------------------------------------------------
set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG is required}"
registry="${REGISTRY_HOST:-ghcr.io}"
username="${GHCR_USERNAME:-}"
token="${GHCR_TOKEN:-}"
secret_name="${PULL_SECRET_NAME:-ghcr-pull}"
ns="${SOURCE_NAMESPACE:-reflector-system}"

if [[ -z "${token}" ]]; then
  echo "GHCR_TOKEN empty — assuming PUBLIC images; nothing to seed" >&2
  exit 0
fi

# Namespace is normally created by the reflector Helm release; ensure it exists.
kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f - >&2

# Source dockerconfigjson secret.
kubectl -n "${ns}" create secret docker-registry "${secret_name}" \
  --docker-server="${registry}" \
  --docker-username="${username}" \
  --docker-password="${token}" \
  --dry-run=client -o yaml | kubectl apply -f - >&2

# Reflector annotations: auto-reflect to ALL namespaces (current + future).
# Empty/absent allowed-namespaces + auto-namespaces means "all".
kubectl -n "${ns}" annotate secret "${secret_name}" --overwrite \
  reflector.v1.k8s.emberstack.com/reflection-allowed="true" \
  reflector.v1.k8s.emberstack.com/reflection-auto-enabled="true" >&2

echo "seeded reflector source secret '${secret_name}' (${registry}) in '${ns}' — auto-reflected to all namespaces" >&2
