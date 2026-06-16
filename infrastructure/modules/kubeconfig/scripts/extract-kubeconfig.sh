#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# extract-kubeconfig.sh — write a HOST-reachable kubeconfig for miniblue's k3s.
# Invoked by the `kubeconfig` Terraform module (null_resource local-exec).
#
# miniblue returns a kubeconfig whose server is the INTERNAL k3s port
# (https://127.0.0.1:6443), but the API server is published on a RANDOM host port
# that only `docker inspect` knows. We read k3s.yaml from the live container and
# rewrite the server to https://localhost:<mapped-port> so terraform's helm/kubernetes
# providers (running on the host) can reach it.
#
# Env: KUBECONFIG_OUT (required), AKS_CONTAINER_FILTER (default "miniblue-aks-").
# -----------------------------------------------------------------------------
set -euo pipefail

: "${KUBECONFIG_OUT:?KUBECONFIG_OUT is required}"
filter="${AKS_CONTAINER_FILTER:-miniblue-aks-}"

k3s_container="$(docker ps --filter "name=${filter}" --format '{{.Names}}' | head -n1)"
[[ -n "${k3s_container}" ]] || { echo "no running ${filter}* container — did the AKS unit apply?" >&2; exit 1; }

host_port="$(docker inspect -f '{{(index (index .NetworkSettings.Ports "6443/tcp") 0).HostPort}}' "${k3s_container}")"
[[ -n "${host_port}" ]] || { echo "could not determine k3s API host port for ${k3s_container}" >&2; exit 1; }

mkdir -p "$(dirname "${KUBECONFIG_OUT}")"
# MSYS_NO_PATHCONV stops Git-Bash from mangling the in-container path on Windows.
MSYS_NO_PATHCONV=1 docker exec "${k3s_container}" cat /etc/rancher/k3s/k3s.yaml \
  | sed "s#https://127.0.0.1:6443#https://localhost:${host_port}#g; s#https://0.0.0.0:6443#https://localhost:${host_port}#g" \
  > "${KUBECONFIG_OUT}"

[[ -s "${KUBECONFIG_OUT}" ]] || { echo "empty kubeconfig — check: docker exec ${k3s_container} cat /etc/rancher/k3s/k3s.yaml" >&2; exit 1; }
chmod 600 "${KUBECONFIG_OUT}"
echo "kubeconfig written: ${KUBECONFIG_OUT} (k3s api on localhost:${host_port})" >&2
